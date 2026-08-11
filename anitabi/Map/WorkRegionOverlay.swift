//
//  WorkRegionOverlay.swift
//  anitabi
//
//  作品モードの圧暗レイヤー。点群の凸包を約 1km 膨らませ、その**外側だけ**を暗くする。実装は
//  「世界矩形を外環・凸包を内環に持つ 1 枚の MKPolygon」—— renderer が内環を even-odd の穴として
//  描くので、これだけで反転マスクになる。暗幕の外のタップ判定もここに乗る。
//

import MapKit
import UIKit

final class WorkRegionOverlay: MKPolygon {
    /// 内環（膨らませた凸包）の座標。タップの内外判定に使う。
    var hull: [CLLocationCoordinate2D] = []

    /// 作品のテーマ色。Web 版は暗幕（fill 0.5）も縁取り線もテーマ色で描く。
    var themeColor: UIColor = .black

    /// 点群から圧暗レイヤーを作る。作れない場合は nil。Web 版 `Yo()` の移植で、判定範囲外の点を
    /// 含む作品は描かず（海外点で巨大な枠が出るのを防ぐ）、あとは凸包の真バッファを取る。
    static func make(for coordinates: [CLLocationCoordinate2D], bufferMeters: Double = 1_000) -> WorkRegionOverlay? {
        guard let hull = hull(for: coordinates, bufferMeters: bufferMeters) else { return nil }

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

    /// 圧暗レイヤーが**実際に描く**多角形の頂点（`make(for:)` の内環そのもの）。
    /// カメラのフィットもこれと**同じ頂点**を使う —— 別の点集合で組むと枠が画面に収まらない。
    /// `nil` は「圧暗レイヤーも描かれない」場合（判定範囲外・頂点 3 未満）と一致する。
    static func hull(
        for coordinates: [CLLocationCoordinate2D],
        bufferMeters: Double = 1_000
    ) -> [CLLocationCoordinate2D]? {
        guard !coordinates.isEmpty else { return nil }

        // Web の `l` フィルタと同値。
        let outOfRange = coordinates.contains {
            $0.longitude < 0 || $0.longitude > 153 || $0.latitude < 20 || $0.latitude > 45
        }
        guard !outOfRange else { return nil }

        let hull = bufferedHull(of: coordinates, meters: bufferMeters)
        return hull.count >= 3 ? hull : nil
    }

    /// 暗幕の内側（＝作品の領域）か。
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        Self.polygon(hull, contains: coordinate)
    }

    // MARK: 幾何

    /// 重心基準のローカルメートル平面（正距円筒近似）。日本スケールでは歪みが問題にならない。
    private struct Meters { var x: Double; var y: Double }

    /// `turf.convex` → `turf.buffer(d, meters)` 相当：凸包の各辺を外法線方向へ d 平行移動し、
    /// 頂点は半径 d の円弧（約 12° 刻み）で継ぐ。Web 版と同じ丸角の領域になる。
    private static func bufferedHull(of coordinates: [CLLocationCoordinate2D], meters d: Double) -> [CLLocationCoordinate2D] {
        let cLat = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let cLng = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        let mPerLat = 111_320.0
        let mPerLng = 111_320.0 * max(cos(cLat * .pi / 180), 0.01)
        func toMeters(_ c: CLLocationCoordinate2D) -> Meters {
            Meters(x: (c.longitude - cLng) * mPerLng, y: (c.latitude - cLat) * mPerLat)
        }
        func toCoordinate(_ p: Meters) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: cLat + p.y / mPerLat, longitude: cLng + p.x / mPerLng)
        }

        let points = coordinates.map(toMeters)
        let hull = convexHull(points)

        // 1〜2 点・一直線：Web は点を散らして三角形化→バッファ ≒ ほぼ円。最遠点半径 + d の円にする。
        guard hull.count >= 3 else {
            let radius = points.reduce(0.0) { max($0, ($1.x * $1.x + $1.y * $1.y).squareRoot()) } + d
            return (0..<36).map { step in
                let angle = Double(step) / 36 * 2 * .pi
                return toCoordinate(Meters(x: cos(angle) * radius, y: sin(angle) * radius))
            }
        }

        var out: [Meters] = []
        let n = hull.count
        for i in 0..<n {
            let p = hull[i]
            let q = hull[(i + 1) % n]
            let r = hull[(i + 2) % n]
            let dx = q.x - p.x, dy = q.y - p.y
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 0.001 else { continue }
            // CCW 凸包 → 外側は進行方向の右 = (dy, -dx)
            let nx = dy / len, ny = -dx / len
            out.append(Meters(x: p.x + nx * d, y: p.y + ny * d))
            out.append(Meters(x: q.x + nx * d, y: q.y + ny * d))

            let dx2 = r.x - q.x, dy2 = r.y - q.y
            let len2 = (dx2 * dx2 + dy2 * dy2).squareRoot()
            guard len2 > 0.001 else { continue }
            let a1 = atan2(ny, nx)
            var sweep = atan2(-dx2 / len2, dy2 / len2) - a1  // 次辺の外法線角 − 現辺の外法線角
            while sweep < 0 { sweep += 2 * .pi }
            guard sweep < .pi else { continue }  // 凸なら 180° 未満（数値ノイズ防御）
            let steps = Int(sweep / (.pi / 15))
            if steps > 0 {
                for s in 1...steps {
                    let angle = a1 + sweep * Double(s) / Double(steps + 1)
                    out.append(Meters(x: q.x + cos(angle) * d, y: q.y + sin(angle) * d))
                }
            }
        }
        return out.map(toCoordinate)
    }

    /// Andrew's monotone chain（メートル平面、CCW で返す）。
    private static func convexHull(_ input: [Meters]) -> [Meters] {
        var unique = Set<Point>()
        for p in input { unique.insert(Point(x: p.x, y: p.y)) }
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
        return (lower + upper).map { Meters(x: $0.x, y: $0.y) }
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
    /// 縁取りは**地面幅一定**の帯にする（Web の `2^(zoom-9)` px の階段を換算すると約 250m 一定）。
    /// `MKOverlayPathRenderer.lineWidth` はスクリーン固定幅なので使わず、描画コンテキスト
    /// （単位＝マップポイント）に地面幅を直接流し込む。250m は手機では太すぎるので 100m。
    private static let edgeGroundWidthMeters: Double = 100

    /// 近接ズームでの暴走防止（地面幅一定のままだと画面を食い尽くす）。
    private static let maxScreenWidthPoints: Double = 14

    override func applyStrokeProperties(to context: CGContext, atZoomScale zoomScale: MKZoomScale) {
        super.applyStrokeProperties(to: context, atZoomScale: zoomScale)
        let ground = MKMapPointsPerMeterAtLatitude(overlay.coordinate.latitude) * Self.edgeGroundWidthMeters
        let cap = Self.maxScreenWidthPoints / Double(zoomScale)  // pt → マップポイント換算
        context.setLineWidth(CGFloat(min(ground, cap)))
        context.setLineJoin(.round)
    }
}
