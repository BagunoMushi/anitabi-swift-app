//
//  WorkRegionOverlay.swift
//  anitabi
//
//  作品モードの圧暗レイヤー。作品の点群の凸包を約 1km 膨らませ、その**外側だけ**を暗くする。
//  実装は「世界矩形を外環・凸包を内環に持つ 1 枚の MKPolygon」。MKPolygonRenderer は
//  interiorPolygons を even-odd の穴として描くので、これだけで反転マスクになる。
//
//  暗幕の外をタップ＝作品モードの終了、という導線もここの内外判定に乗せる。
//

import MapKit
import UIKit

final class WorkRegionOverlay: MKPolygon {
    /// 内環（膨らませた凸包）の座標。タップの内外判定に使う。
    var hull: [CLLocationCoordinate2D] = []

    /// 点群から圧暗レイヤーを作る。作れない場合（点なし・180 度経線跨ぎ）は nil。
    static func make(for coordinates: [CLLocationCoordinate2D], bufferMeters: Double = 1_000) -> WorkRegionOverlay? {
        guard !coordinates.isEmpty else { return nil }

        let lngs = coordinates.map(\.longitude)
        guard let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }
        // データはほぼ日本国内なので、跨線ケースは正しく畳まず素直に諦める（防御だけ）。
        guard maxLng - minLng < 180 else { return nil }

        let hull = buffered(hull: convexHull(coordinates), of: coordinates, meters: bufferMeters)
        guard hull.count >= 3 else { return nil }

        let interior = MKPolygon(coordinates: hull, count: hull.count)
        let world = MKMapRect.world
        var corners = [
            MKMapPoint(x: world.minX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.minY),
            MKMapPoint(x: world.maxX, y: world.maxY),
            MKMapPoint(x: world.minX, y: world.maxY),
        ]
        let overlay = WorkRegionOverlay(points: &corners, count: corners.count, interiorPolygons: [interior])
        overlay.hull = hull
        return overlay
    }

    /// 暗幕の内側（＝作品の領域）か。
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        Self.polygon(hull, contains: coordinate)
    }

    // MARK: 幾何

    /// Andrew's monotone chain。緯度経度平面のまま計算する（日本スケールでは歪みが問題にならない）。
    private static func convexHull(_ input: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var unique = Set<Point>()
        for coordinate in input {
            unique.insert(Point(x: coordinate.longitude, y: coordinate.latitude))
        }
        let points: [Point] = unique.sorted { lhs, rhs in
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            return lhs.y < rhs.y
        }
        guard points.count >= 3 else { return input }

        func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [Point] = []
        for point in points {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [Point] = []
        for point in points.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        lower.removeLast()
        upper.removeLast()
        return (lower + upper).map { CLLocationCoordinate2D(latitude: $0.y, longitude: $0.x) }
    }

    /// 凸包を重心から外へ `meters` ぶん押し出す。頂点が 3 未満（1〜2 点・一直線）の作品は
    /// 多角形にならないので、重心まわりの円に置き換える。
    private static func buffered(
        hull: [CLLocationCoordinate2D],
        of all: [CLLocationCoordinate2D],
        meters: Double
    ) -> [CLLocationCoordinate2D] {
        let centroid = CLLocationCoordinate2D(
            latitude: all.reduce(0) { $0 + $1.latitude } / Double(all.count),
            longitude: all.reduce(0) { $0 + $1.longitude } / Double(all.count)
        )
        let latPerMeter = 1 / 111_320.0
        let lngPerMeter = 1 / (111_320.0 * max(cos(centroid.latitude * .pi / 180), 0.01))

        guard hull.count >= 3 else {
            let radius = all.reduce(meters) { current, coordinate in
                let dy = (coordinate.latitude - centroid.latitude) / latPerMeter
                let dx = (coordinate.longitude - centroid.longitude) / lngPerMeter
                return max(current, (dx * dx + dy * dy).squareRoot() + meters)
            }
            return (0..<24).map { step in
                let angle = Double(step) / 24 * 2 * .pi
                return CLLocationCoordinate2D(
                    latitude: centroid.latitude + sin(angle) * radius * latPerMeter,
                    longitude: centroid.longitude + cos(angle) * radius * lngPerMeter
                )
            }
        }

        return hull.map { vertex in
            let dy = (vertex.latitude - centroid.latitude) / latPerMeter
            let dx = (vertex.longitude - centroid.longitude) / lngPerMeter
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 1 else { return vertex }
            return CLLocationCoordinate2D(
                latitude: vertex.latitude + dy / length * meters * latPerMeter,
                longitude: vertex.longitude + dx / length * meters * lngPerMeter
            )
        }
    }

    private static func polygon(
        _ vertices: [CLLocationCoordinate2D],
        contains coordinate: CLLocationCoordinate2D
    ) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in vertices.indices {
            let a = vertices[i], b = vertices[j]
            if (a.latitude > coordinate.latitude) != (b.latitude > coordinate.latitude),
               coordinate.longitude < (b.longitude - a.longitude)
                   * (coordinate.latitude - a.latitude)
                   / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private struct Point: Hashable {
        let x: Double
        let y: Double
    }
}

// MARK: - 描画

final class WorkRegionRenderer: MKPolygonRenderer {
    /// 暗幕の濃さ。明るい地図では 6% で十分沈み、暗い地図では 12% ないと差が出ない。
    static func fillColor(for traits: UITraitCollection) -> UIColor {
        UIColor.black.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.12 : 0.06)
    }

    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        strokeColor = nil
        lineWidth = 0
    }
}
