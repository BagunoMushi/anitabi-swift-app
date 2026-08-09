//
//  AnitabiPalette.swift
//  anitabi
//
//  設計稿「圣地巡礼卡片组件」（claude.ai/design · 2026-08-09）の配色を写した唯一の色源。
//
//  設計稿は**浅色 1 枚だけ**が描かれている（浅緑の地図地 ＋ 白ガラスのカード）。
//  そこに書かれている値をそのまま `light:` へ入れ、`dark:` は同じ役割を夜側へ写した派生値。
//  派生の原則は 2 つだけ：
//
//  1. **墨と主色は入れ替える**。昼は「深緑の実心 ＋ 浅緑の字」、夜は地がもう暗いので
//     逆に「浅緑の実心 ＋ 深緑の字」にする（暗いガラスの上の深緑実心は消える）。
//  2. **白の薄膜は白の薄膜のまま、率だけ落とす**。昼 50–90% の白面は夜 5–20% にする。
//     色を作り替えず率だけ変えるので、階層（面 → 浮いた面 → 溝）の順序が夜でも崩れない。
//
//  カードの地（sheet の背景）は設計稿の合成色 `#ECFFEC`（淡緑 ＋ 白 55%）＋ 系统のぼかし。
//  詳しい理由は `anitabiCardGlass` のコメント参照。
//

import SwiftUI
import UIKit

// MARK: - 設計稿の生値

/// 設計稿に literal で出てくる 16 進値。ここ以外に hex を書かない。
private enum Raw {
    /// `#132e1a` —— 設計稿の墨（文字・主色実心）。
    static let ink = UIColor(cssHex: "132e1a")!
    /// `#eaffec` —— 深緑実心の上に載る字。
    static let onInk = UIColor(cssHex: "eaffec")!
    /// `#D4FFD5` —— 地図地／画像の上の徽章の字。
    static let mint = UIColor(cssHex: "d4ffd5")!

    /// 夜側の墨（浅緑へ反転）。
    static let inkDark = UIColor(cssHex: "d7f3da")!
    /// 夜側の主色実心（浅緑）と、その上に載る字。
    static let accentDark = UIColor(cssHex: "a7e9b4")!
    static let onAccentDark = UIColor(cssHex: "0c2113")!

    /// 礼儀警示（`rgba(255,214,120,.4)` / `rgba(217,164,65,.6)` / `#d9a441` / `#5a3d00`）。
    static let warnFill = UIColor(cssHex: "ffd678")!
    static let warnLine = UIColor(cssHex: "d9a441")!
    static let warnInk = UIColor(cssHex: "5a3d00")!
    /// 夜側は同じ琥珀の明度を上げて字に回す。
    static let warnInkDark = UIColor(cssHex: "f3dfad")!

    /// 点行の「注意礼仪」徽章（`rgba(217,164,65,.3)` 地 ＋ `#6b4a00` 字）。
    static let badgeWarnInk = UIColor(cssHex: "6b4a00")!

    /// 設計稿のカードの地の**合成色**。モックは淡緑 `#D4FFD5` の上に `rgba(255,255,255,.55)` を
    /// 重ねているので、出ている色は 0.55×白 + 0.45×淡緑 ＝ `#ECFFEC`。
    static let cardGlass = UIColor(cssHex: "ecffec")!
    /// 夜側は同じ関係を反転させた深緑。
    static let cardGlassDark = UIColor(cssHex: "10281a")!
}

private func dynamic(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

private extension UIColor {
    func alpha(_ value: CGFloat) -> UIColor { withAlphaComponent(value) }
}

// MARK: - 墨（文字）

extension Color {

    /// 設計稿の `#132e1a`。標題・行名・主要な字。
    static let anitabiInk = dynamic(light: Raw.ink, dark: Raw.inkDark)

    /// `rgba(19,46,26,.6)`。副題・meta 行。
    static let anitabiInkSecondary = dynamic(light: Raw.ink.alpha(0.60), dark: Raw.inkDark.alpha(0.66))

    /// `rgba(19,46,26,.5)` 〜 `.55`。節見出しの補助数値・出典行。
    static let anitabiInkTertiary = dynamic(light: Raw.ink.alpha(0.50), dark: Raw.inkDark.alpha(0.52))

    /// `rgba(19,46,26,.4)` 〜 `.45`。`›` 記号・placeholder・版権脚注。
    static let anitabiInkFaint = dynamic(light: Raw.ink.alpha(0.42), dark: Raw.inkDark.alpha(0.40))

    // MARK: - 主色（実心の釦）

    /// 主動作の実心。設計稿では `#132e1a`（墨と同色）、夜側は浅緑へ反転。
    static let anitabiAccentFill = dynamic(light: Raw.ink, dark: Raw.accentDark)

    /// 主動作の実心に載る字。設計稿 `#eaffec`、夜側は深緑。
    static let anitabiOnAccent = dynamic(light: Raw.onInk, dark: Raw.onAccentDark)

    // MARK: - カードの地（ガラス）

    /// カード（sheet）の地。設計稿の
    /// `backdrop-filter: blur(24px) saturate(1.6)` ＋ `rgba(255,255,255,.55)` を
    /// モックの淡緑 `#D4FFD5` に重ねた合成色 `#ECFFEC` をそのまま置く。
    ///
    /// **なぜ合成色を置くのか**：設計稿はカードの下が平らな淡緑（モックの「地図」）なので
    /// 白 55% のままでも淡緑に見える。実機の下は Apple マップのフルカラーなので、
    /// 同じ 55% だと剧照標の写真が透けて虹色のムラになる（設計稿にはあり得ない見え方）。
    /// 合成色を置けば設計稿と同じ淡緑の地になり、ぼかしは下の material が受け持つ。
    ///
    /// 不透明度の履歴（実機判定）：0.88 → 0.74 → **0.50**（現在）。
    /// 設計稿の `rgba(255,255,255,.55)` に近い値まで下りたので、地図はかなり透ける。
    /// 剧照標（フルカラー写真）が乗った上でも面が均一に見えるかは下の material が支える。
    /// これ以上透かすなら、透明度を下げるのではなく `.regularMaterial` → `.thickMaterial` で
    /// ぼかしを足す側で調整する（色ムラは不透明度では消せない）。
    static let anitabiCardGlass = dynamic(light: Raw.cardGlass.alpha(0.50), dark: Raw.cardGlassDark.alpha(0.56))

    // MARK: - 面（ガラスの上に載る白い薄膜）

    /// 一覧カード・情報カードの地。設計稿 `rgba(255,255,255,.5)`。
    static let anitabiSurface = dynamic(light: .white.alpha(0.50), dark: .white.alpha(0.07))
    /// その縁。設計稿 `rgba(255,255,255,.85)`。
    static let anitabiSurfaceStroke = dynamic(light: .white.alpha(0.85), dark: .white.alpha(0.13))

    /// 次動作のカプセル・丸釦。設計稿 `rgba(255,255,255,.6)`。
    static let anitabiRaised = dynamic(light: .white.alpha(0.60), dark: .white.alpha(0.13))
    /// その縁。設計稿 `rgba(255,255,255,.9)`。
    static let anitabiRaisedStroke = dynamic(light: .white.alpha(0.90), dark: .white.alpha(0.20))

    /// 備考本文の地。設計稿 `rgba(255,255,255,.4)`。
    static let anitabiSubtle = dynamic(light: .white.alpha(0.40), dark: .white.alpha(0.05))

    /// ✕ 丸釦・「清除」chip の地。設計稿 `rgba(19,46,26,.08)`〜`.1`。
    static let anitabiSoftFill = dynamic(light: Raw.ink.alpha(0.10), dark: .white.alpha(0.14))

    /// 分段控件の溝。設計稿 `rgba(19,46,26,.07)`。
    static let anitabiTrack = dynamic(light: Raw.ink.alpha(0.07), dark: .white.alpha(0.10))
    /// 分段控件の滑块。設計稿 `#fff`。
    static let anitabiThumb = dynamic(light: .white, dark: .white.alpha(0.26))

    /// 行間の細線。設計稿 `rgba(19,46,26,.08)`。
    static let anitabiHairline = dynamic(light: Raw.ink.alpha(0.08), dark: .white.alpha(0.12))

    // MARK: - 画像まわり

    /// 剧照が無い／読み込み中の器。設計稿の斜線プレースホルダに相当する地。
    static let anitabiMediaPlaceholder = dynamic(light: Raw.ink.alpha(0.09), dark: .white.alpha(0.10))

    /// 画像の上に重ねる EP／タイムコード徽章。設計稿 `rgba(19,46,26,.85)` ＋ `#D4FFD5`。
    static let anitabiMediaBadge = dynamic(light: Raw.ink.alpha(0.85), dark: .black.alpha(0.62))
    static let anitabiMediaBadgeText = dynamic(light: Raw.mint, dark: Raw.mint)

    // MARK: - 礼儀警示（琥珀）

    /// 設計稿 `rgba(255,214,120,.4)`。
    static let anitabiWarnFill = dynamic(light: Raw.warnFill.alpha(0.40), dark: Raw.warnLine.alpha(0.22))
    /// 設計稿 `rgba(217,164,65,.6)`。
    static let anitabiWarnStroke = dynamic(light: Raw.warnLine.alpha(0.60), dark: Raw.warnLine.alpha(0.50))
    /// 設計稿 `#d9a441`（丸い `!` の地）。
    static let anitabiWarnIcon = dynamic(light: Raw.warnLine, dark: Raw.warnLine)
    /// 設計稿 `#5a3d00`。
    static let anitabiWarnInk = dynamic(light: Raw.warnInk, dark: Raw.warnInkDark)

    /// 点行の「注意礼仪」徽章（設計稿 `rgba(217,164,65,.3)` ＋ `#6b4a00`）。
    static let anitabiBadgeWarnFill = dynamic(light: Raw.warnLine.alpha(0.30), dark: Raw.warnLine.alpha(0.26))
    static let anitabiBadgeWarnInk = dynamic(light: Raw.badgeWarnInk, dark: Raw.warnInkDark)
}
