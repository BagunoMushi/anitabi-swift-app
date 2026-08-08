//
//  DesignTokens.swift
//  anitabi
//
//  首屏视觉稿（Claude Design: Anitabi Map Home）对应的设计变量。
//  设计稿的取值全部集中在这里，视图层不再出现裸色值 / 裸尺寸。
//

import SwiftUI
import UIKit

// MARK: - 颜色

enum Palette {
    /// 品牌绿（看板娘朝日礼的毛衣色）。只做点缀：选中态、主按钮、激活态。
    /// 站点原本的淡蓝 #9ddbf1 在白底与玻璃上对比不足，无法承担可交互语义。
    static let brand = Color(hex: 0x3D7A4A)

    /// 卡片实体底色。玻璃只用于控件层，内容卡一律不透明。
    static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x2C2C2E)

    static let title = Color(lightHex: 0x3A362E, darkHex: 0xF2F2F4)
    static let secondary = Color(lightHex: 0x8B8577, darkHex: 0x98989F)
    static let sectionHeader = Color(lightHex: 0x6B6558, darkHex: 0x98989F)
    static let quaternary = Color(lightHex: 0xA49D8F, darkHex: 0x7A7A82)

    /// sheet 内の搜索场・账号钮の塗り。ガラスの上なので材質ではなく半透明の塗りにする。
    static let searchField = Color(lightWhite: 0.47, lightAlpha: 0.14, darkWhite: 0.47, darkAlpha: 0.24)

    /// 列表分隔线。
    static let separator = Color(lightHex: 0x3C3C43, lightAlpha: 0.12, darkHex: 0x545458, darkAlpha: 0.65)

    /// 地标圆点的描边：亮色白、暗色近白，保证任意作品主题色都能从底图里跳出来。
    static let pinStroke = Color(lightHex: 0xFFFFFF, darkHex: 0xF2F2F4)
}

// MARK: - 尺寸

enum Metrics {
    // sheet
    //
    // 角丸はここに定数として持たない。iOS 26 では sheet の角半径は画面の角と同心になるよう
    // システムが決め、内側のカード・搜索場は `ConcentricRectangle` でそこから導出する。
    // 数値を打ち込むと同心性が壊れる（設計稿の 24pt を採用しなかったのはこのため）。
    static let sheetHPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12

    /// カード内の行インセット。上下左右を同じ値にすること —— 画像の角を容器と同心に
    /// するには、画像が容器の縁から**等距離**にある必要がある（12/7 のような非対称だと崩れる）。
    static let rowInset: CGFloat = 10

    // 搜索场
    /// Apple マップ実測 50.5pt。44pt だと収起档で下に余白が余って間延びして見える。
    static let searchFieldHeight: CGFloat = 50
    /// sheet 上端から搜索场上端までの距離。上拉线（4pt 位置・5pt 高）を挟むので、
    /// 上拉线下端 → 搜索场上端 が Apple 実測の約 14pt になる値にしてある。
    static let searchFieldTopInset: CGFloat = 21
    /// 搜索场の下の余白。収起档ではこれが sheet の下端までの距離になる。
    static let searchFieldBottomInset: CGFloat = 12

    // 浮动控件
    static let controlSize: CGFloat = 44
    static let controlSpacing: CGFloat = 10
    static let controlInset: CGFloat = 16

    // 列表内缩略图
    static let nearbyThumb = CGSize(width: 64, height: 36)
    static let compactThumb = CGSize(width: 58, height: 33)
    static let coverSize = CGSize(width: 34, height: 46)
    static let cityTileHeight: CGFloat = 56
    static let quickActionSize: CGFloat = 42

    // 地图标注
    static let dotSize: CGFloat = 13
    static let dotStroke: CGFloat = 2.5
    static let selectedDotSize: CGFloat = 20
    static let clusterSize: CGFloat = 28
    static let bangumiPinSize: CGFloat = 26
    static let photoPin = CGSize(width: 56, height: 42)
}

/// sheet 三档。收起 / 半开 / 全开。数値は iOS 26 の Apple マップを実測して合わせた。
enum SheetDetent: CGFloat, CaseIterable {
    /// 収起档は割合でも固定値でもなく、**中身から逆算**する（`collapsedHeight(bottomSafeArea:)`）。
    /// 搜索场 1 本ぶんの器なので、数字を決め打ちすると端末や文字サイズが変わった途端に
    /// 下へ空きガラスが余る。rawValue は識別用のダミー。
    case collapsed = -1
    /// 「上下文卡 + 附近 2 行 + 快捷入口」がちょうど収まる高さ。実測 44.0%。
    case half = 0.44
    /// 実測 93.4%。
    case expanded = 0.93

    /// 収起档の高さ = 上余白 + 搜索场 + 下余白 だけ。
    /// home indicator ぶんを足してはいけない —— iOS 26 の sheet は画面下端から浮いており、
    /// その余白は OS 側が既に確保している。足すと搜索场の下に空きガラスが二重に出る。
    @MainActor static var collapsedHeight: CGFloat {
        Metrics.searchFieldTopInset
            + Metrics.searchFieldHeight
            + Metrics.searchFieldBottomInset
    }

    @MainActor var fraction: PresentationDetent {
        self == .collapsed ? .height(Self.collapsedHeight) : .fraction(rawValue)
    }

    @MainActor static var presentationSet: Set<PresentationDetent> {
        Set(allCases.map(\.fraction))
    }

    /// この档で sheet が実際に占める高さ。浮動控件を sheet の上端に貼り付けるのに使う。
    @MainActor func height(inScreen screenHeight: CGFloat) -> CGFloat {
        self == .collapsed ? Self.collapsedHeight : screenHeight * rawValue
    }

    @MainActor static func matching(_ detent: PresentationDetent) -> SheetDetent? {
        allCases.first { $0.fraction == detent }
    }
}

// MARK: - 字体
//
// 设计稿用 M PLUS Rounded 1c（圆体）。iOS 上不打包第三方字体，
// 改用 SF 的 rounded design —— 同样的圆润气质，且中日文自动回落到系统字体。

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 段标题「附近的巡礼点」等
    static let homeSection = Font.rounded(13, .heavy)
    /// 列表行主标题
    static let homeRowTitle = Font.rounded(14.5, .heavy)
    /// 列表行副标题
    static let homeRowSubtitle = Font.rounded(12, .medium)
    /// 搜索场占位符
    static let homeSearch = Font.rounded(15, .medium)
}

// MARK: - Color 便利构造

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

    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(lightHex: lightHex, lightAlpha: 1, darkHex: darkHex, darkAlpha: 1)
    }

    init(lightHex: UInt32, lightAlpha: Double, darkHex: UInt32, darkAlpha: Double) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? darkHex : lightHex
            let alpha = trait.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        })
    }

    init(lightWhite: Double, lightAlpha: Double, darkWhite: Double, darkAlpha: Double) {
        self.init(uiColor: UIColor { trait in
            let dark = trait.userInterfaceStyle == .dark
            return UIColor(
                white: dark ? darkWhite : lightWhite,
                alpha: dark ? darkAlpha : lightAlpha
            )
        })
    }

    /// 作品主题色可能接近白色 —— 这种点在白描边下会糊掉，需要额外补一圈灰 outline。
    var needsOutlineOnLightPin: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        // 相対輝度が高い＝白描画と同化する
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) > 0.82
    }
}
