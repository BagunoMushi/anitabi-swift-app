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

    /// 作品のテーマ色。Web 版は暗幕（fill 0.5）も縁取り線もテーマ色で描く。
    var themeColor: UIColor = .black

    /// 点群から圧暗レイヤーを作る。作れない場合は nil。
    ///
    /// Web 版 `Yo()` の忠実な移植：
    /// 1. **判定範囲ガード** —— 1 点でも lng 0–153 / lat 20–45 の外にある作品は領域を描かない
    ///    （Web は空ポリゴンを流す。海外点を含む作品で巨大な枠が出るのを防ぐ仕様）。
    /// 2. `turf.convex()` → `turf.buffer(1000m)` —— 凸包の**真バッファ**（各辺を法線方向へ
    ///    平行移動し、頂点は円弧で継ぐ）。重心押し出しの近似ではない。
    static func make(for coordinates: [CLLocationCoordinate2D], bufferMeters: Double = 1_000) -> WorkRegionOverlay? {
        guard !coordinates.isEmpty else { return nil }

        // Web の `l` フィルタと同値。
        let outOfRange = coordinates.contains {
            $0.longitude < 0 || $0.longitude > 153 || $0.latitude < 20 || $0.latitude > 45
        }
        guard !outOfRange else { return nil }

        let hull = bufferedHull(of: coordinates, meters: bufferMeters)
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
    /// Web 版の縁取り線幅は `2^(zoom-9)` px の階段 —— 換算すると**地面幅ほぼ一定（約 250m）**の
    /// 太い帯である（z10:2px×124m/px ≒ z15:64px×3.9m/px ≒ 250m）。MKOverlayPathRenderer の
    /// `lineWidth` はスクリーン固定幅なので使わず、描画コンテキスト（単位＝マップポイント）に
    /// 直接地面幅を流し込んで同じ挙動を得る。
    /// 250m（Web 換算値）は手機の画面では太すぎるとのフィードバックにより 100m へ。
    /// z13 で約 6pt、z15 で約 26pt —— 見えるが主張しすぎない太さ。
    private static let edgeGroundWidthMeters: Double = 100

    /// 近接ズームでの暴走防止：Web は z15 で 64px まで太るが、手機では画面を食いすぎるので
    /// スクリーン上の最大幅を 14pt にクランプする。
    private static let maxScreenWidthPoints: Double = 14

    override func applyStrokeProperties(to context: CGContext, atZoomScale zoomScale: MKZoomScale) {
        super.applyStrokeProperties(to: context, atZoomScale: zoomScale)
        let ground = MKMapPointsPerMeterAtLatitude(overlay.coordinate.latitude) * Self.edgeGroundWidthMeters
        let cap = Self.maxScreenWidthPoints / Double(zoomScale)  // pt → マップポイント換算
        context.setLineWidth(CGFloat(min(ground, cap)))
        context.setLineJoin(.round)
    }
}
