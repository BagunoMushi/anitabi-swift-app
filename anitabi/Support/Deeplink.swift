//
//  Deeplink.swift
//  anitabi
//
//  外部からの着地点を 1 つの値型に集約する（受け口は `anitabi://map?…` と web の `/map?…`）。
//  同じ値は状態復元（UserDefaults へ保存）にも使うので `Codable` —— `CLLocationCoordinate2D` は
//  `Codable` ではないので緯度・経度をバラして自前で書く。
//

import CoreLocation
import Foundation

struct MapDeepLink: Codable {

    /// 作品モードへ入る Bangumi ID（web `bangumiId`）。
    var bangumiID: Int?
    /// 選択する地標 ID（web `pid`）。
    var pointID: String?
    /// カメラ中心。URL 上は**web と同じく経度が先**（`c=lng,lat`）だが、並びを間違えないよう
    /// ここでは変換済みの形で持つ。
    var center: CLLocationCoordinate2D?
    /// ズーム（web `z`）。
    var zoom: Double?
    /// 複数作品フィルタ（web `bids`、カンマ区切り）。
    var bids: [Int] = []

    init(
        bangumiID: Int? = nil,
        pointID: String? = nil,
        center: CLLocationCoordinate2D? = nil,
        zoom: Double? = nil,
        bids: [Int] = []
    ) {
        self.bangumiID = bangumiID
        self.pointID = pointID
        self.center = center
        self.zoom = zoom
        self.bids = bids
    }

    /// 何も持たない（＝着地先が無い）かどうか。状態復元も Handoff もこれを見て黙る。
    var isEmpty: Bool {
        bangumiID == nil && pointID == nil && center == nil && bids.isEmpty
    }

    // MARK: - URL 解析

    private static let customScheme = "anitabi"
    /// `/map` を受け入れるホスト。ミラー（`w.junreimap.com`）の共有 URL も同じ形式なので拾う。
    private static let webHosts: Set<String> = [
        "anitabi.cn", "www.anitabi.cn", "ww.anitabi.cn", "w.junreimap.com",
    ]

    /// 受け入れる形式に合わない／パラメータが 1 つも読めないときは `nil`。個々のパラメータは
    /// 壊れていても黙って捨てる —— 共有アプリを経由した URL は普通に壊れる。
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let isCustomScheme = components.scheme == Self.customScheme
            && (components.host?.lowercased() == "map" || components.path == "/map")
        let isWebMap = components.scheme == "https"
            && Self.webHosts.contains(components.host?.lowercased() ?? "")
            && components.path == "/map"
        guard isCustomScheme || isWebMap else { return nil }

        var bangumiID: Int?
        var pointID: String?
        var center: CLLocationCoordinate2D?
        var zoom: Double?
        var bids: [Int] = []

        for item in components.queryItems ?? [] {
            guard let value = item.value?.nilIfBlank else { continue }
            switch item.name {
            case "bangumiId":
                bangumiID = Int(value)
            case "pid":
                pointID = value
            case "c":
                // web と同じ並び：経度, 緯度。
                let parts = value.split(separator: ",")
                if parts.count == 2,
                   let lng = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                   let lat = Double(parts[1].trimmingCharacters(in: .whitespaces)),
                   (-180...180).contains(lng), (-90...90).contains(lat) {
                    center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            case "z":
                if let z = Double(value), z.isFinite {
                    zoom = z
                }
            case "bids":
                bids = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            default:
                break
            }
        }

        guard bangumiID != nil || pointID != nil || center != nil || !bids.isEmpty else { return nil }

        self.bangumiID = bangumiID
        self.pointID = pointID
        self.center = center
        self.zoom = zoom
        self.bids = bids
    }

    // MARK: - 発射（共有・Handoff・状態復元に共通）

    /// `AnitabiWebLink` と同じホスト方針で吐く web URL。
    var canonicalURL: URL {
        AnitabiWebLink.canonical(bangumiID: bangumiID, pointID: pointID, coordinate: center, zoom: zoom, bids: bids)
    }

    // MARK: - Codable（`CLLocationCoordinate2D` を緯度経度に分解）

    private enum CodingKeys: String, CodingKey {
        case bangumiID, pointID, lat, lng, zoom, bids
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bangumiID = try container.decodeIfPresent(Int.self, forKey: .bangumiID)
        pointID = try container.decodeIfPresent(String.self, forKey: .pointID)
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom)
        bids = try container.decodeIfPresent([Int].self, forKey: .bids) ?? []
        if let lat = try container.decodeIfPresent(Double.self, forKey: .lat),
           let lng = try container.decodeIfPresent(Double.self, forKey: .lng) {
            center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            center = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(bangumiID, forKey: .bangumiID)
        try container.encodeIfPresent(pointID, forKey: .pointID)
        try container.encodeIfPresent(zoom, forKey: .zoom)
        if !bids.isEmpty { try container.encode(bids, forKey: .bids) }
        if let center {
            try container.encode(center.latitude, forKey: .lat)
            try container.encode(center.longitude, forKey: .lng)
        }
    }

    // MARK: - 状態復元（バックグラウンド遷移時に保存 → コールドスタートで読む）

    // baseStyle 等は `@AppStorage` で別途永続化されるので、ここで持つのは
    // 「どこを見ていたか」（カメラ／選択／フィルタ）だけ。
    private static let persistKey = "map.restoredDeepLink"

    static func loadPersisted() -> MapDeepLink? {
        guard let data = UserDefaults.standard.data(forKey: Self.persistKey),
              let link = try? JSONDecoder().decode(MapDeepLink.self, from: data),
              !link.isEmpty
        else { return nil }
        return link
    }

    /// 空値では上書きしない —— 地図が描画される前に一瞬バックグラウンドへ落ちた場合など、
    /// 直前の正常な状態を空値で潰さないため。
    func persist() {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistKey)
    }
}
