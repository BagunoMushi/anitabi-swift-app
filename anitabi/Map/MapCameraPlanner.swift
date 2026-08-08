//
//  MapCameraPlanner.swift
//  anitabi
//
//  カメラの算数を 1 箇所に集める。ズーム値は Web 版（Mapbox GL）の定義に合わせる：
//
//      z = log2(360 × 表示幅pt / (256 × span.longitudeDelta))
//
//  揭示阶梯も密度テーブルも Web の z を前提に書かれているので、この式から外れると
//  標注の出方が丸ごとズレる。
//

import CoreLocation
import MapKit
import UIKit

enum MapCameraPlanner {

    /// 作品フィットの上限。これ以上寄ると「作品の広がり」ではなく 1 点の景色になる。
    static let maxFitZoom: Double = 17
    /// Web 版の flyTo と同じ体感（約 1.2 秒）。
    static let flyDuration: TimeInterval = 1.2

    // MARK: ズーム ↔ 範囲

    static func zoom(for region: MKCoordinateRegion, width: CGFloat) -> Double {
        zoom(longitudeDelta: region.span.longitudeDelta, width: width)
    }

    static func zoom(longitudeDelta: Double, width: CGFloat) -> Double {
        guard longitudeDelta > 0, width > 0 else { return 0 }
        return log2(360 * Double(width) / (256 * longitudeDelta))
    }

    static func longitudeDelta(zoom: Double, width: CGFloat) -> Double {
        guard width > 0 else { return 360 }
        return 360 * Double(width) / (256 * pow(2, zoom))
    }

    static func region(center: CLLocationCoordinate2D, zoom: Double, size: CGSize) -> MKCoordinateRegion {
        let lngDelta = longitudeDelta(zoom: zoom, width: size.width)
        // 経度方向の縮尺は緯度で縮む。緯度方向の span は画面比から起こす。
        let latDelta = lngDelta * Double(size.height / max(size.width, 1))
            * max(cos(center.latitude * .pi / 180), 0.01)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: min(max(latDelta, 0.0002), 180),
                longitudeDelta: min(max(lngDelta, 0.0002), 360)
            )
        )
    }

    /// 指定ズームちょうどの表示矩形。
    ///
    /// `setRegion` は「要求した範囲が必ず収まる」ように span を切り上げるので、緯度と画面比の
    /// 兼ね合いで実測ズームが 0.2 ほど浅くなる。MKMapRect は Mercator 投影後の単位＝画面ピクセルと
    /// 線形なので、画面比に合わせた矩形を渡せばズームが厳密に一致する。
    ///
    /// - Parameter verticalOffset: 正なら目標を画面のこのぶん**上**に置く（下半分はカードで隠れる）。
    static func mapRect(
        center: CLLocationCoordinate2D,
        zoom: Double,
        size: CGSize,
        verticalOffset: CGFloat = 0
    ) -> MKMapRect {
        let unitsPerPoint = MKMapSize.world.width / (256 * pow(2, zoom))
        let width = Double(size.width) * unitsPerPoint
        let height = Double(size.height) * unitsPerPoint
        let point = MKMapPoint(center)
        return MKMapRect(
            x: point.x - width / 2,
            y: point.y - height / 2 + Double(verticalOffset) * unitsPerPoint,
            width: width,
            height: height
        )
    }

    // MARK: 一覧から選んだ点へ寄る

    /// Web 版の密度テーブル。`priority` は最近傍までの距離（m）＝周りの混み具合なので、
    /// 「隣の点と区別が付く」ところまで寄る倍率がそのまま決まる。
    static func flyZoom(priority: Int?) -> Double {
        guard let priority else { return 15 }
        return switch priority {
        case let p where p > 64: 15
        case let p where p > 32: 16
        case let p where p > 16: 17
        case let p where p > 8: 18
        case let p where p > 4: 19
        case let p where p > 2: 20
        case let p where p > 1: 21
        default: 22
        }
    }

    // MARK: 作品フィット

    /// 作品の点群が収まる矩形。飛び地 1 点で全国表示になるのを防ぐため分位数で外れ値を落とす。
    /// - 上下 2% を捨てる
    /// - それでも P95 が P80 の 3 倍を超えるなら、尾が長すぎるので P80 で切る
    static func fitRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        guard coordinates.count > 4 else { return boundingRect(coordinates) }

        let lats = coordinates.map(\.latitude).sorted()
        let lngs = coordinates.map(\.longitude).sorted()
        let center = CLLocationCoordinate2D(
            latitude: lats[lats.count / 2],
            longitude: lngs[lngs.count / 2]
        )
        let metersPerLng = 111_320.0 * max(cos(center.latitude * .pi / 180), 0.01)
        let distances = coordinates
            .map { coordinate -> Double in
                let dy = (coordinate.latitude - center.latitude) * 111_320
                let dx = (coordinate.longitude - center.longitude) * metersPerLng
                return (dx * dx + dy * dy).squareRoot()
            }
            .sorted()

        func percentile(_ q: Double) -> Double {
            distances[min(max(Int(Double(distances.count - 1) * q), 0), distances.count - 1)]
        }
        let p80 = percentile(0.80)
        let p95 = percentile(0.95)
        let limit = p95 > p80 * 3 ? p80 : percentile(0.98)

        let kept = coordinates.filter { coordinate in
            let dy = (coordinate.latitude - center.latitude) * 111_320
            let dx = (coordinate.longitude - center.longitude) * metersPerLng
            return (dx * dx + dy * dy).squareRoot() <= limit + 1
        }
        return boundingRect(kept.isEmpty ? coordinates : kept)
    }

    private static func boundingRect(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard let first = coordinates.first else { return nil }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        // 1 点だけの作品は面積 0 になるので最低限の広がりを与える。
        if rect.size.width < 1 || rect.size.height < 1 {
            let padding = MKMapPointsPerMeterAtLatitude(first.latitude) * 400
            rect = rect.insetBy(dx: -padding, dy: -padding)
        }
        return rect
    }

    /// 四辺 7% ＋ 下辺にカードの高さ。Apple マップの「経路の全体表示」と同じ考え方。
    static func edgePadding(viewSize: CGSize, bottomInset: CGFloat) -> UIEdgeInsets {
        let inset = viewSize.width * 0.07
        return UIEdgeInsets(top: inset, left: inset, bottom: inset + bottomInset, right: inset)
    }

    /// フィット結果が寄りすぎないよう `maxFitZoom` で頭打ちにする。
    static func clampedToMaxZoom(_ rect: MKMapRect, viewSize: CGSize) -> MKMapRect {
        let region = MKCoordinateRegion(rect)
        let currentZoom = zoom(for: region, width: viewSize.width)
        guard currentZoom > maxFitZoom else { return rect }
        let scale = pow(2, currentZoom - maxFitZoom)
        let width = rect.size.width * scale
        let height = rect.size.height * scale
        return MKMapRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
