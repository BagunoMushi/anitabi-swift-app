//
//  Deeplink.swift
//  anitabi
//
//  外部からの着地点を 1 つの値型に集約する。受け口は 2 つ ——
//
//      anitabi://map?bangumiId=…&pid=…&c=lng,lat&z=…&bids=…
//      https://(www|ww).anitabi.cn/map?…（同じクエリ）
//
//  `https://anitabi.cn/map` も宛先として受ける（301 で www へ飛ぶ死んだドメインだが、
//  Universal Link の AASA は `anitabi.cn` 側に置かれる想定なので着地だけは拾う。
//  実際にページを開くときの `pageHost` は `AnitabiWebLink` が別途 `ww.anitabi.cn` に決め打つ）。
//
//  Associated Domains（AASA）は外部依存につき本段では設定しない —— `anitabi://` scheme が
//  常に効く保底線（計画書 A6 の記載どおり）。
//
//  同じ値は「状態復元」（バックグラウンド遷移時に UserDefaults へ Codable で保存）にも使うため、
//  `Codable` にしてある。`CLLocationCoordinate2D` はそのまま `Codable` ではないので、
//  緯度・経度をバラして自前でエンコードする。
//

import CoreLocation
import Foundation

// `CLLocationCoordinate2D` は `Equatable` に適合しないため、`Equatable` は付けない
// （どこからも `==` で比較していないので、無理に用意する理由も無い）。
struct MapDeepLink: Codable {

    /// 作品モードへ入る Bangumi ID（web `bangumiId`）。
    var bangumiID: Int?
    /// 選択する地標 ID（web `pid`）。
    var pointID: String?
    /// カメラ中心。**web と同じく経度が先**（`c=lng,lat`）——ここだけ緯度経度が逆順なので、
    /// 呼び出し側で並びを間違えないよう `CLLocationCoordinate2D` に変換済みの形で持つ。
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

    /// 何も持たない（＝着地先が無い）かどうか。恢复/Handoff の両方でこれを見て
    /// 「保存する価値が無い」「適用する意味が無い」を判定する。
    var isEmpty: Bool {
        bangumiID == nil && pointID == nil && center == nil && bids.isEmpty
    }

    // MARK: - URL 解析

    private static let customScheme = "anitabi"
    private static let webHosts: Set<String> = ["anitabi.cn", "www.anitabi.cn", "ww.anitabi.cn"]

    /// 受け入れる URL 形式に合わなければ `nil`。パラメータが 1 つも読めなくても `nil`
    /// （＝「map 宛てだが何も指定していない」は「着地点なし」と同じ扱いにする）。
    /// 個々のパラメータは壊れていても黙って捨てる（crash させない）——実測 URL は
    /// 手で組み立てたり共有アプリを経由したりで壊れることが普通にある。
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

    // MARK: - 発射（共有・Handoff・状態復元の書き出しに共通）

    /// `AnitabiWebLink` と同じホスト方針（`ww.anitabi.cn`）で吐く web URL。`c` は小数 4 桁。
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

    /// baseStyle/isPhotoLayerVisible は既に `@AppStorage` で別途永続化されているので、
    /// ここで持つのは「どこを見ていたか」（カメラ／選択／フィルタ）だけ。
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
