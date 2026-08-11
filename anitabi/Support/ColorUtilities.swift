//
//  ColorUtilities.swift
//  anitabi
//
//  作品テーマカラー（`#rrggbb`・サーバ由来で色域は不可控）を地図標注で安全に使うための道具。
//  色判定の主実装は地図レイヤー（UIKit）に合わせて `UIColor` 側に置き、SwiftUI 側は委譲する。
//

import SwiftUI
import UIKit

extension UIColor {

    /// `#rrggbb` / `rrggbb` / `#rgb`。解釈できない値は nil（呼び出し側でニュートラル灰へ落とす）。
    /// **hex を解くのはここだけ** —— SwiftUI 側の `Color(cssHex:)` もこれに委譲する。
    convenience init?(cssHex: String) {
        var s = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    /// テーマカラーが取れなかった作品の代替色。**この 1 か所だけが値を持つ。**
    static let anitabiNeutralTheme = UIColor(red: 0x8A / 255, green: 0x8A / 255, blue: 0x6F / 255, alpha: 1)

    /// 白描边と同化してしまう明るいテーマカラーか。
    /// 「白い縁取りに溶けるか」の見た目判断なので、ガンマ補正なしの単純加重で足りる。
    var needsDarkInnerOutline: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) > 0.82
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1
        )
    }

    /// 作品標のラベル色。テーマカラーを**黒へ寄せて**背景とのコントラストが `minimum` を満たす
    /// 最小の混合率を返す。`maxMix` で打ち切るのは、混ぜ切ると作品ごとの色の差＝地図上の
    /// 識別子が消えてしまうため。
    func labelColor(
        on background: UIColor = .white,
        minimum: CGFloat = 4.5,
        maxMix: CGFloat = 0.6
    ) -> UIColor {
        var candidate = self
        var mix: CGFloat = 0
        while mix < maxMix, Self.contrastRatio(candidate, background) < minimum {
            mix = min(mix + 0.05, maxMix)
            candidate = mixed(with: .black, amount: mix)
        }
        return candidate
    }

    /// WCAG の相対輝度（sRGB のガンマを戻してから重み付ける）。
    private var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let l1 = lhs.relativeLuminance, l2 = rhs.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

extension Color {
    /// `#rrggbb` / `rrggbb` / `#rgb`。解釈は `UIColor(cssHex:)` に任せる。
    init?(cssHex: String) {
        guard let color = UIColor(cssHex: cssHex) else { return nil }
        self.init(uiColor: color)
    }

    /// `UIColor.anitabiNeutralTheme` の SwiftUI 版。
    static let anitabiNeutralTheme = Color(uiColor: .anitabiNeutralTheme)

    /// テーマカラーからグラデーションを作るための素朴なブレンド。
    func mix(with other: Color, by amount: Double) -> Color {
        Color(uiColor: UIColor(self).mixed(with: UIColor(other), amount: CGFloat(amount)))
    }

    /// 封面・剧照が無いときに敷くテーマ色グラデーション（設計稿のプレースホルダー相当）。
    var anitabiThemeGradient: LinearGradient {
        LinearGradient(
            colors: [self, mix(with: .black, by: 0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
