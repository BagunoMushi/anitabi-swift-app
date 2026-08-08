//
//  MapAnnotationModel.swift
//  anitabi
//
//  設計稿の「密度策略」を実装する層。
//  ズーム 1 段につき 1 レイヤーだけ出す —— 作品聚合 → 地標圓點 → 劇照圖標 の 3 段。
//  Web 版のように全部を同時に描かない（5 万点をそのまま MapKit に渡すと破綻するため、
//  可視範囲で間引き、グリッドで束ねてから 1 画面あたり上限件数までに絞る）。
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - 標注

enum MapAnnotationItem: Identifiable {
    /// 低ズーム：作品単位。中心は可視範囲にある当該作品の点の重心。
    case work(id: Int, coordinate: CLLocationCoordinate2D, name: String, letter: String, color: Color, count: Int)
    /// 中ズーム：グリッドで束ねた点の塊。
    case cluster(id: String, coordinate: CLLocationCoordinate2D, count: Int, color: Color)
    /// 中〜高ズーム：単独の地標。
    case point(ScenePoint, color: Color)
    /// 高ズーム（z16 相当以上）：劇照サムネイル。
    case photo(ScenePoint, color: Color)

    var id: String {
        switch self {
        case .work(let id, _, _, _, _, _): "w\(id)"
        case .cluster(let id, _, _, _): "c\(id)"
        case .point(let p, _): "p\(p.id)"
        case .photo(let p, _): "i\(p.id)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .work(_, let c, _, _, _, _): c
        case .cluster(_, let c, _, _): c
        case .point(let p, _): p.coordinate
        case .photo(let p, _): p.coordinate
        }
    }

    var scenePoint: ScenePoint? {
        switch self {
        case .point(let p, _), .photo(let p, _): p
        default: nil
        }
    }
}

// MARK: - ズーム段

enum MapDetailTier {
    case works      // 全国〜広域
    case clusters   // 市域
    case points     // 街区
    case photos     // 現地（z16 相当）

    /// 可視範囲の緯度スパンから段を決める。境界値は設計稿の「放大逐级解锁」に合わせた。
    static func forSpan(_ latitudeDelta: CLLocationDegrees) -> MapDetailTier {
        switch latitudeDelta {
        case ..<0.006: .photos
        case ..<0.06: .points
        case ..<1.2: .clusters
        default: .works
        }
    }
}

// MARK: - 生成

enum MapAnnotationBuilder {

    /// 1 画面に出す標注の上限。これを超えると読めなくなるので priority 順に切る。
    static let screenLimit = 90

    struct Input {
        var points: [ScenePoint]
        var region: MKCoordinateRegion
        var color: (Int) -> Color
        var workName: (Int) -> String
        var workLetter: (Int) -> String
        /// 単一作品モードのときはその作品だけ描く（後続 brief 用の受け口）。
        var focusedBangumiID: Int?
    }

    static func build(_ input: Input) -> [MapAnnotationItem] {
        let region = input.region
        let tier = MapDetailTier.forSpan(region.span.latitudeDelta)

        // 画面外を落とす。少し広めに取ってスクロール時のちらつきを防ぐ。
        let latPad = region.span.latitudeDelta * 0.6
        let lngPad = region.span.longitudeDelta * 0.6
        let minLat = region.center.latitude - latPad
        let maxLat = region.center.latitude + latPad
        let minLng = region.center.longitude - lngPad
        let maxLng = region.center.longitude + lngPad

        var visible: [ScenePoint] = []
        visible.reserveCapacity(1024)
        for point in input.points {
            if let focus = input.focusedBangumiID, point.bangumiID != focus { continue }
            guard point.lat >= minLat, point.lat <= maxLat,
                  point.lng >= minLng, point.lng <= maxLng
            else { continue }
            visible.append(point)
        }

        switch tier {
        case .works:
            return buildWorkPins(visible, input: input)
        case .clusters:
            return buildClusters(visible, region: region, input: input)
        case .points:
            return topByPriority(visible)
                .map { .point($0, color: input.color($0.bangumiID)) }
        case .photos:
            return topByPriority(visible).map { point in
                point.image == nil
                    ? .point(point, color: input.color(point.bangumiID))
                    : .photo(point, color: input.color(point.bangumiID))
            }
        }
    }

    // MARK: 作品ピン

    private static func buildWorkPins(_ points: [ScenePoint], input: Input) -> [MapAnnotationItem] {
        var sums: [Int: (lat: Double, lng: Double, count: Int)] = [:]
        for point in points {
            var entry = sums[point.bangumiID] ?? (0, 0, 0)
            entry.lat += point.lat
            entry.lng += point.lng
            entry.count += 1
            sums[point.bangumiID] = entry
        }

        // 点数の多い作品＝その土地の代表作、を優先して 12 件まで。
        return sums
            .sorted { $0.value.count > $1.value.count }
            .prefix(12)
            .map { id, entry in
                .work(
                    id: id,
                    coordinate: CLLocationCoordinate2D(
                        latitude: entry.lat / Double(entry.count),
                        longitude: entry.lng / Double(entry.count)
                    ),
                    name: input.workName(id),
                    letter: input.workLetter(id),
                    color: input.color(id),
                    count: entry.count
                )
            }
    }

    // MARK: グリッド束ね

    private static func buildClusters(
        _ points: [ScenePoint],
        region: MKCoordinateRegion,
        input: Input
    ) -> [MapAnnotationItem] {
        // 画面を 8×8 程度に割る粒度。細かすぎると団子、粗すぎると数字だらけになる。
        let cellLat = region.span.latitudeDelta / 8
        let cellLng = region.span.longitudeDelta / 8
        guard cellLat > 0, cellLng > 0 else { return [] }

        struct Bucket {
            var latSum = 0.0
            var lngSum = 0.0
            var count = 0
            var best: ScenePoint?
            var perWork: [Int: Int] = [:]
        }

        var buckets: [String: Bucket] = [:]
        for point in points {
            let row = Int(floor(point.lat / cellLat))
            let col = Int(floor(point.lng / cellLng))
            let key = "\(row):\(col)"
            var bucket = buckets[key] ?? Bucket()
            bucket.latSum += point.lat
            bucket.lngSum += point.lng
            bucket.count += 1
            bucket.perWork[point.bangumiID, default: 0] += 1
            if (bucket.best?.priority ?? -1) < point.priority { bucket.best = point }
            buckets[key] = bucket
        }

        return buckets
            .sorted { $0.value.count > $1.value.count }
            .prefix(screenLimit)
            .compactMap { key, bucket -> MapAnnotationItem? in
                if bucket.count == 1, let single = bucket.best {
                    return .point(single, color: input.color(single.bangumiID))
                }
                // 塊の色＝その塊でいちばん点数の多い作品の色（設計稿の cluster 仕様）
                guard let dominant = bucket.perWork.max(by: { $0.value < $1.value })?.key else { return nil }
                return .cluster(
                    id: key,
                    coordinate: CLLocationCoordinate2D(
                        latitude: bucket.latSum / Double(bucket.count),
                        longitude: bucket.lngSum / Double(bucket.count)
                    ),
                    count: bucket.count,
                    color: input.color(dominant)
                )
            }
    }

    private static func topByPriority(_ points: [ScenePoint]) -> [ScenePoint] {
        guard points.count > screenLimit else { return points }
        return Array(points.sorted { $0.priority > $1.priority }.prefix(screenLimit))
    }
}
