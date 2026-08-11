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

    /// 作品の点群が収まる矩形。飛び地の離群点で「日本全体どころか太平洋まで」表示になるのを防ぐ。
    ///
    /// web 版 `fitBoundsByBangumi`（`4b970b29.js` の `Jo` 関数）の**逐字移植**。中央値からの
    /// 距離を分位数（P95/P80 など）で比較する方式は、ここでは**採らない**——実測（ハイスクール・
    /// フリート、bangumiId 144843、g.json 実データ）で機能しないことを確認済み：19 点中 9 点が
    /// 太平洋上の航路点で、全体のほぼ半数を離群点が占めるため、P95 も P80 も「離群点側」に
    /// 落ちてしまい、両者の比が閾値を超えない（＝異常検出そのものが働かない）。
    ///
    /// `Jo` は分位数ではなく**各点の「他の全点までの平均距離＝離心度」**を見る：
    /// 1. 点 i の離心度 = Σ(i から他の全点までの距離) / (n-1)
    /// 2. 閾値 = (離心度の最大値 + 平均値) / 2 × 0.8
    /// 3. 離心度が閾値を超える点を切り捨てる
    /// 4. 切り捨てた結果が 3 点未満なら間引き過ぎとみなし、元の点群をそのまま使う（web と同じ安全弁）
    ///
    /// 少数の孤立点となら「その点だけ平均距離が突出する」ので綺麗に落ちる。上記の実データでも
    /// 検証済み：ハイスクール・フリート 19 点（本土 10 ＋洋上 9）→ 13 点まで絞れる（P95/P80 方式は
    /// 1 点も落とせず全 19 点のまま）。響け！ユーフォニアム 582 点（本土 581 ＋飛び地 1）→
    /// 離群点 1 点だけを正しく検出、本編クラスタは無傷。
    static func fitRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        guard coordinates.count >= 4 else { return boundingRect(coordinates) }

        let locations = coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let n = locations.count
        var eccentricities = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var total = 0.0
            for j in 0..<n where j != i {
                total += locations[i].distance(from: locations[j])
            }
            eccentricities[i] = total / Double(n - 1)
        }
        let maxEccentricity = eccentricities.max() ?? 0
        let meanEccentricity = eccentricities.reduce(0, +) / Double(n)
        let cutoff = (maxEccentricity + meanEccentricity) / 2 * 0.8

        let kept = coordinates.indices
            .filter { eccentricities[$0] <= cutoff }
            .map { coordinates[$0] }
        return boundingRect(kept.count >= 3 ? kept : coordinates)
    }

    /// 与えられた座標を**そのまま**囲む矩形（離群点の切り捨てをしない）。
    /// 圧暗レイヤーの頂点（`WorkRegionOverlay.hull`）を収めるときはこちらを使う——
    /// あの多角形は既に全点から組まれているので、ここで間引くと枠が画面外にはみ出す。
    static func enclosingRect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        boundingRect(coordinates)
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

    /// 四辺 7% ＋ 上辺に安全区（Dynamic Island／ステータスバー）＋ 下辺にカードの高さ。
    /// Apple マップの「経路の全体表示」と同じ考え方。
    ///
    /// `topInset` を渡さなかった版は、枠の上端が Dynamic Island の下に潜っていた（実機）——
    /// 地図は `.ignoresSafeArea()` で窓いっぱいに広がっているので、安全区はここで明示するしかない。
    static func edgePadding(
        viewSize: CGSize,
        topInset: CGFloat = 0,
        bottomInset: CGFloat
    ) -> UIEdgeInsets {
        let inset = viewSize.width * 0.07
        return UIEdgeInsets(
            top: inset + topInset,
            left: inset,
            bottom: inset + bottomInset,
            right: inset
        )
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
