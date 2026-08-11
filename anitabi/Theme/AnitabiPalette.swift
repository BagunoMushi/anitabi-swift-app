//
//  AnitabiPalette.swift
//  anitabi
//
//  設計稿「圣地巡礼卡片组件」（claude.ai/design）の配色を写した唯一の色源。設計稿は**浅色 1 枚
//  だけ**なので `dark:` は 2 つの原則で夜側へ写した派生値：(1) 墨と主色を入れ替える、
//  (2) 白の薄膜は白のまま率だけ落とす（そうすれば面 → 浮いた面 → 溝の階層が夜でも崩れない）。
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

    /// カードの地の**合成色**。モックは淡緑 `#D4FFD5` に白 55% を重ねているので `#ECFFEC`。
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

    // MARK: - 截图水印カプセル

    /// `AppIdentityPillView` の**夜側**の地。実機では Dynamic Island のマスクに隠れて見えないので、
    /// この色は**スクリーンショットにしか出ない**。浅色側はここを使わず、下の sheet と同じ
    /// `.regularMaterial` ＋ `anitabiCardGlass` を敷く（＝カプセルの地が sheet の地と一致する）。
    static let anitabiIdentityPill = Color(uiColor: Raw.ink)
    /// その上に載る字。浅色は sheet の上と同じ墨、夜側は設計稿の `#eaffec`。
    static let anitabiOnIdentityPill = dynamic(light: Raw.ink, dark: Raw.onInk)

    // MARK: - カードの地（ガラス）

    /// カード（sheet）の地。設計稿の白 55% を淡緑に重ねた**合成色**を置き、ぼかしは material に
    /// 任せる —— 設計稿はカードの下が平らな淡緑だが実機は地図のフルカラーで、白 55% のままだと
    /// 剧照標が透けて虹色のムラになる。もっと透かすなら透明度ではなく material を厚くする。
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

    /// 骨架屏（スケルトン）を掃く高光。`anitabiMediaPlaceholder` の上に重ねる前提の白。
    static let anitabiSkeletonHighlight = dynamic(light: .white.alpha(0.55), dark: .white.alpha(0.14))

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
