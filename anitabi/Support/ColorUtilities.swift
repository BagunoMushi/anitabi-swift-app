//
//  ColorUtilities.swift
//  anitabi
//
//  作品テーマカラー（`#rrggbb`・サーバ由来で色域は不可控）を地図標注で安全に使うための道具。
//
//  地図レイヤーは UIKit（CALayer / MKAnnotationView）なので、色判定の主実装は SwiftUI の
//  `Color` ではなく `UIColor` 側に置く。ただし `AnitabiModels.themeColor`（データ層、SwiftUI）
//  が `Color(cssHex:)`/`Color(hex:)` を必要とするため、`Home/DesignTokens.swift` 削除に伴い
//  その 2 つの initializer もここへ合流させた（阶段 9）。
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// `#rrggbb` / `rrggbb` 字符串（作品主题色来自服务端，格式不完全可控）。
    init?(cssHex: String) {
        var s = cssHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

extension UIColor {

    /// `#rrggbb` / `rrggbb` / `#rgb`。解釈できない値は nil（呼び出し側でニュートラル灰へ落とす）。
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

    /// テーマカラーが取れなかった作品に使うニュートラル色（DesignTokens の 0x8A8A6F と同値）。
    static let anitabiNeutralTheme = UIColor(red: 0x8A / 255, green: 0x8A / 255, blue: 0x6F / 255, alpha: 1)

    /// WCAG の相対輝度。sRGB のガンマを戻してから重み付けする。
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// 白描边と同化してしまう明るいテーマカラーか。
    /// 判定は DesignTokens と揃えてガンマ補正なしの単純加重（閾値 0.82）を使う ——
    /// 「白い縁取りに溶けるか」の見た目判断であって、可読性コントラストの話ではないため。
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

    static func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let l1 = lhs.relativeLuminance, l2 = rhs.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// 作品標のラベル色。テーマカラーを**黒へ寄せて**背景とのコントラストが `minimum` を満たす
    /// 最小の混合率を返す。混合は `maxMix` で打ち切る（それ以上混ぜると全部ほぼ黒になり、
    /// 作品ごとの色の差＝地図上の識別子が消えるため）。
    func labelColor(
        on background: UIColor = .white,
        minimum: CGFloat = 4.5,
        maxMix: CGFloat = 0.6
    ) -> UIColor {
        var candidate = self
        var mix: CGFloat = 0
        while mix < maxMix, UIColor.contrastRatio(candidate, background) < minimum {
            mix = min(mix + 0.05, maxMix)
            candidate = mixed(with: .black, amount: mix)
        }
        return candidate
    }
}
