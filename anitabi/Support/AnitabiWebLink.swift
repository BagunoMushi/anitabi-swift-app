//
//  AnitabiWebLink.swift
//  anitabi
//
//  Web 版へ手渡す URL の組み立て。ドメインは `ww.anitabi.cn` —— `anitabi.cn` は名前解決できない
//  `www` へ 301 するので、そのまま渡すと「サーバが見つかりません」で終わる（復活したら
//  `pageHost` 1 行で戻る）。クエリは自前で組む：`urlQueryAllowed` は `&` を通してしまう。
//

import CoreLocation
import Foundation
import UIKit

enum AnitabiWebLink {

    /// ページを開くときのホスト（分享・貢献フロー・网页版すべて共通）。
    private static let pageHost = "https://ww.anitabi.cn"

    /// 何もかも失敗したときの落とし先（地図トップ）。非オプショナルを返す約束のために持つ。
    private static let fallback = URL(string: "\(pageHost)/map")!

    // MARK: - 地図（canonical）

    /// 共有・「在网页版打开」に使う正規 URL。`c` は **lng が先**（Web 版の並びを踏襲）で
    /// 小数 4 桁、`bids` はカンマ区切り。引数を省いたパラメータは URL に出さない。
    static func canonical(
        bangumiID: Int? = nil,
        pointID: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil,
        zoom: Double? = nil,
        bids: [Int] = []
    ) -> URL {
        var items: [(String, String)] = []
        if let bangumiID { items.append(("bangumiId", String(bangumiID))) }
        if let pointID = pointID?.nilIfBlank { items.append(("pid", pointID)) }
        if let coordinate {
            items.append(("c", String(format: "%.4f,%.4f", coordinate.longitude, coordinate.latitude)))
        }
        if let zoom { items.append(("z", trimmed(zoom))) }
        if !bids.isEmpty { items.append(("bids", bids.map(String.init).joined(separator: ","))) }
        guard !items.isEmpty else { return fallback }
        return url("\(pageHost)/map", items)
    }

    // MARK: - 貢献フロー

    /// 補传截图（既存地標の編集モード）。Web 版 `pn()` と同形の `?data={JSON}&bangumiId&type=edit`。
    static func createPoint(point: ScenePoint, bangumi: BangumiLite?) -> URL {
        var payload: [String: Any] = [
            "id": point.id,
            "geo": [point.lat, point.lng]
        ]
        if let name = point.name?.nilIfBlank { payload["name"] = name }
        if let cn = point.nameCN?.nilIfBlank { payload["cn"] = cn }
        if let ep = point.ep?.nilIfBlank { payload["ep"] = ep }
        if let s = point.timecodeS { payload["s"] = s }
        if let image = point.image?.nilIfBlank { payload["image"] = image }

        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return url("\(pageHost)/create-point", [
            ("data", json),
            ("bangumiId", bangumi.map { String($0.id) } ?? String(point.bangumiID)),
            ("type", "edit")
        ])
    }

    /// 长按落针の「在此添加地标」。まだどの作品にも属さない**新規**地標なので
    /// `id`/`bangumiId`/`type=edit` は付けず、最小合法負荷 `{"geo":[lat,lng]}` だけ渡す。
    static func createPoint(at coordinate: CLLocationCoordinate2D) -> URL {
        let payload: [String: Any] = ["geo": [coordinate.latitude, coordinate.longitude]]
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return url("\(pageHost)/create-point", [("data", json)])
    }

    /// 修正坐标。Web 版 `ms()` の 15 パラメータをそのまま並べる（欠けている値も**空文字で送る**
    /// —— Web 側のフォームは「キーが無い」ことを想定していない）。
    static func fixPointGPS(point: ScenePoint, bangumi: BangumiLite?) -> URL {
        url("\(pageHost)/fix-point-gps", [
            ("pid", point.id),
            ("pointName", point.nameCN?.nilIfBlank ?? point.name?.nilIfBlank ?? ""),
            ("geo0", String(point.lat)),
            ("geo1", String(point.lng)),
            ("ep", point.ep?.nilIfBlank ?? ""),
            ("s", point.timecodeS.map(String.init) ?? ""),
            ("pointImage", point.image?.nilIfBlank ?? ""),
            ("pointOrigin", point.origin?.nilIfBlank ?? ""),
            ("bangumiId", bangumi.map { String($0.id) } ?? String(point.bangumiID)),
            ("bangumiName", bangumi?.cn?.nilIfBlank ?? bangumi?.title?.nilIfBlank ?? ""),
            ("bangumiCity", bangumi?.city?.nilIfBlank ?? ""),
            ("bangumiCat", bangumi?.cat?.nilIfBlank ?? ""),
            ("bangumiCp", bangumi?.title?.nilIfBlank ?? ""),
            ("bangumiCover", bangumi?.cover?.nilIfBlank ?? ""),
            ("bangumiColor", bangumi?.colorHex?.nilIfBlank ?? "")
        ])
    }

    // MARK: - 外部地図

    /// Google マップ。Google Maps アプリが入っていれば universal link で自動的にそちらが開く。
    static func googleMaps(lat: Double, lng: Double) -> URL {
        url("https://www.google.com/maps", [("q", String(format: "%.6f,%.6f", lat, lng))])
    }

    /// ストリートビュー。`layer=c` + `cbll` はアプリ側も解釈する古典的な形式 ——
    /// `?api=1&map_action=pano` は Google Maps アプリに渡らないことがある。
    static func streetView(lat: Double, lng: Double) -> URL {
        URL(string: "http://maps.google.com/maps?q=&layer=c&cbll=\(String(format: "%.6f,%.6f", lat, lng))&cbp=11,0,0,0,0")
            ?? fallback
    }

    /// Google マイマップのビューア。`mid` を持つ（＝地図インポート由来の）地標の出典リンク。
    /// `ll` の区切りは Web 版と同じくエンコード済みのカンマで送る。
    static func myMapsViewer(mid: String, lat: Double, lng: Double, zoom: Int = 12) -> URL {
        URL(string: "https://www.google.com/maps/d/viewer?mid=\(mid.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? mid)&ll=\(lat)%2C\(lng)&z=\(zoom)")
            ?? fallback
    }

    /// 外部アプリへ渡す。Google マップ／街景は `SFSafariViewController` の中からでは
    /// 絶対にアプリへ遷移しないので、地図系のリンクは必ずこちらを通す。
    @MainActor
    static func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// 巡礼マナーの共同ドキュメント（Web 版の ⚠️ アイコンと同じ飛び先）。
    static let etiquetteIssue = URL(string: "https://github.com/anitabi/anitabi.cn-document/issues/29")!

    /// 「关于」シートの「巡礼数据反馈」。特定 issue ではなく一覧（新規 issue もここから起票できる）。
    static let feedbackIssues = URL(string: "https://github.com/anitabi/anitabi.cn-document/issues")!

    // MARK: - 組み立て

    /// `&` `+` `=` `?` `#` `/` を通さないクエリ値用の集合。カンマは Web 版の見た目に合わせて残す。
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#/")
        return set
    }()

    private static func url(_ base: String, _ items: [(String, String)]) -> URL {
        let query = items
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? "")" }
            .joined(separator: "&")
        return URL(string: query.isEmpty ? base : "\(base)?\(query)") ?? fallback
    }

    /// `z=14.0` ではなく `z=14` にする（整数ズームのときだけ小数点を落とす）。
    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
