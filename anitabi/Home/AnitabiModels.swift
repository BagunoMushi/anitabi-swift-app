//
//  AnitabiModels.swift
//  anitabi
//
//  anitabi 静的データ（/d/g.json・/d/g0-g6.json）のモデル。
//  フィールドは位置ベースの配列で降ってくるため、レイアウトは docs/anitabi-map-api.md と
//  docs/anitabi-web-full-analysis.md §3.2 の解析結果に準拠する。
//

import CoreLocation
import SwiftUI
import UIKit

// MARK: - 作品

/// `/d/g.json` の 1 レコード（18 フィールドの配列）。
///
/// ```
/// [id, cn, en, title, city, color, cover, score, cat, lat, lng, zoom,
///  points(4 個ずつ: id, lat, lng, priority), abbr, tags[], priority, icon, tAbbr]
/// ```
///
/// フィールド位置は `docs/anitabi-web-full-analysis.md` §3.2 の JS 側変数名
/// （`kD()`）に準拠。ただし idx7 は同ドキュメントの変数名では `fade` だが、
/// `docs/anitabi-map-api.md` §3.2 の実データ（`7.8, // 評分`）と一致させ
/// `score`（Bangumi 評点）として扱う。
struct BangumiLite: Identifiable, Sendable {
    let id: Int
    /// 中文名
    let cn: String?
    /// 英語名（idx2）。多くの作品は未設定。
    /// `let` に既定値を付けると合成メンバーワイズ init からパラメータごと消えるため `var` にする
    /// （`hasIcon` と同じ理由）。
    var en: String? = nil
    /// 原題（多くは日本語）
    let title: String?
    /// 地域（「日本」「中国」など）
    let city: String?
    /// テーマカラー（`#rrggbb`）。色域は不可控 —— 白に近い値も来る。
    let colorHex: String?
    /// 封面パス（`/images/bangumi/{id}.jpg` など）
    let cover: String?
    /// Bangumi 側の評点（idx7）。
    var score: Double? = nil
    /// 分類（TV / 劇場版 / 漫画系列 / ゲーム …）
    let cat: String?
    let center: CLLocationCoordinate2D?
    let zoom: Double?
    /// この作品に属する地標の座標一覧（詳細は g0-g6 側にある）
    let points: [PointGeo]
    /// 略称（idx13）。検索・表示の補助。
    var abbr: String? = nil
    /// 表示優先度（idx15）。値が小さいほど優先。未設定は 999（Web 版と同じ既定値）。
    var priority: Int = 999
    /// `bangumi-icons.json` の `ids` に含まれるか（データ組み立て後に `AnitabiStore` が回填）。
    var hasIcon: Bool = false

    /// 表示名。UI 言語に合わせて中文名 / 原題を選ぶ。
    var displayName: String {
        let preferJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let primary = preferJapanese ? title : cn
        let fallback = preferJapanese ? cn : title
        return primary?.nilIfBlank ?? fallback?.nilIfBlank ?? "#\(id)"
    }

    /// 地図ピン・カバー代替に使うテーマカラー。取得できない作品はニュートラルな灰にする。
    var themeColor: Color {
        colorHex.flatMap(Color.init(cssHex:)) ?? Color(hex: 0x8A8A6F)
    }

    /// カバー画像が無いときに敷くグラデーション（設計稿のプレースホルダーと同じ表現）。
    var themeGradient: LinearGradient {
        LinearGradient(
            colors: [themeColor, themeColor.mix(with: .black, by: 0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 標注ラベル用の 1 文字略称。
    var badgeLetter: String {
        String(displayName.prefix(1))
    }

    var coverURL: URL? { AnitabiImage.url(path: cover, plan: "h160") }
}

/// g.json が持つ地標のジオメトリ。
struct PointGeo: Sendable {
    let id: String
    let lat: Double
    let lng: Double
    /// 最近傍点までの距離ベースの優先度。ズーム別の間引きに使う。
    let priority: Int
}

// MARK: - 地標

/// 地図に落ちる 1 点。g.json の座標に g0-g6 の詳細をマージしたもの。
///
/// g0-g6 側の 1 地標は 15 要素の配列（`docs/anitabi-web-full-analysis.md` §3.2）：
/// ```
/// [id, name, cn, isFolder, folder, mid, uid, image, fid, ep, s, mark, origin, originLink, density]
/// ```
/// 本アプリが使うのは `0:id 1:name 2:cn 3:isFolder 4:folderName 5:mid 6:uid 7:image
/// 8:fid 9:ep 10:timecodeS 11:note(mark) 12:origin 13:originLink`。`14:density` は未使用。
struct ScenePoint: Identifiable, Sendable {
    let id: String
    let bangumiID: Int
    let lat: Double
    let lng: Double
    let priority: Int

    /// 以下は g0-g6 をロードしたあとに埋まる。
    var name: String?
    var nameCN: String?
    /// スクリーンショットのパス
    var image: String?
    /// 話数 / タイムコード
    var ep: String?

    /// この点自身がフォルダ（グループの見出し）かどうか（idx3）。
    var isFolder: Bool = false
    /// フォルダ名の文字列指定（idx4）。`isFolder` の点への参照（`fid`）が無い旧データ向け。
    var folderName: String?
    /// Google マイマップの地図 ID（idx5）。地図インポート由来かどうかの判定に使う。
    var mid: String?
    /// 投稿者の User ID（idx6）。`AnitabiStore.usersByID` で表示名に解決する。
    var uid: Int?
    /// 所属フォルダ（`isFolder` の点）の ID（idx8）。
    var fid: String?
    /// タイムコード（秒、idx10）。数値でも文字列でも来るため寛容にパースする。
    var timecodeS: Int?
    /// 備考（idx11、原 `mark`）。
    var note: String?
    /// 出典（idx12）。「ユーザー投稿」「地図インポート」などの文言。
    var origin: String?
    /// 出典リンク（idx13）。
    var originLink: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var displayName: String {
        let preferJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let primary = preferJapanese ? name : nameCN
        let fallback = preferJapanese ? nameCN : name
        return primary?.nilIfBlank ?? fallback?.nilIfBlank ?? ""
    }

    /// 一覧のサムネイル用（設計稿の 64×36 / 58×33 に合わせて h160 で十分）。
    var thumbnailURL: URL? { AnitabiImage.url(path: image, plan: "h160") }

    /// 「EP 3」形式のバッジ。集数が無ければ nil。
    var episodeBadge: String? {
        guard let ep = ep?.nilIfBlank else { return nil }
        if ep.lowercased().hasPrefix("ep") { return ep.uppercased() }
        if Int(ep) != nil { return "EP \(ep)" }
        return ep
    }

    /// タイムコードを人が読める形式にする。`m:ss`、60 分以上は `h:mm:ss`。
    var timecodeText: String? {
        guard let seconds = timecodeS, seconds >= 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - 作品内グルーピング

/// 作品詳細パネルでの地標の束ね方。Web 版の「フォルダ」「話数」タブに対応。
enum WorkGroupingMode: String {
    case folder
    case episode
}

/// `AnitabiStore.groupedPoints(for:mode:)` の 1 グループ。
struct PointGroup: Identifiable {
    let id: String
    let name: String
    let points: [ScenePoint]
}

// MARK: - 画像 URL

/// 画像パス → CDN URL 変換。Web 版 `XS`/`Zr`（docs/anitabi-web-full-analysis.md §3.4）の最小移植。
enum AnitabiImage {
    static func url(path: String?, plan: String?) -> URL? {
        guard let raw = path?.nilIfBlank else { return nil }

        var absolute: String
        if raw.hasPrefix("http://") {
            absolute = raw.replacingOccurrences(of: "http://", with: "https://")
        } else if raw.hasPrefix("https://") {
            absolute = raw
        } else if raw.hasPrefix("/images/") {
            // `/images` セグメントを剥がして img-tc に載せ替える（image.anitabi.cn/images/... は 404）。
            absolute = "https://img-tc.anitabi.cn" + raw.dropFirst("/images".count)
        } else if raw.hasPrefix("/") {
            absolute = "https://img-tc.anitabi.cn" + raw
        } else {
            absolute = "https://img-tc.anitabi.cn/" + raw
        }

        // lain.bgm.tv は本家と同じくプロキシ経由にする。
        absolute = absolute.replacingOccurrences(
            of: "https://lain.bgm.tv/",
            with: "https://bgm-api.anitabi.cn/img/"
        )

        guard var components = URLComponents(string: absolute) else { return nil }
        if let plan, components.queryItems?.contains(where: { $0.name == "plan" }) != true {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "plan", value: plan)]
        }
        return components.url
    }
}

// MARK: - 小道具

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Color {
    /// テーマカラーからグラデーションを作るための素朴なブレンド。
    func mix(with other: Color, by amount: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(max(0, min(1, amount)))
        return Color(
            .sRGB,
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1)
        )
    }
}

// MARK: - 距離表示

enum DistanceFormatter {
    /// 「350 m」「1.2 km」。巡礼中は m 単位の精度が要るので 1km 未満は m のまま出す。
    static func string(meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        let km = meters / 1000
        return km < 10
            ? String(format: "%.1f km", km)
            : "\(Int(km.rounded())) km"
    }
}
