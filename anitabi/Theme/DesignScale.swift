//
//  DesignScale.swift
//  anitabi
//
//  設計稿（claude.ai/design「圣地巡礼卡片组件」）の px を実機の pt へ等比換算する係数。
//
//  ============================================================================
//  なぜ「設計稿の px をそのまま」でも「幅の比」でも駄目なのか
//  ============================================================================
//
//  設計稿のモックは **390×720px の端末枠**で描かれている。実機（iPhone 17 Pro）は 402×874pt。
//
//  - **そのまま（1.0 倍）**：モックより広く高い実機で、字と部品が相対的に縮む。実測で却下。
//  - **幅の比（402/390 = 1.031）**：3% しか伸びないので、上と実質同じ。これも却下。
//  - **高さの比（874/720 = 1.214）**：モックの枠に対して画面がどれだけ大きいかを素直に表す。
//    設計稿を「その端末の画面いっぱいに置いたときの見え方」になる。**これを採る。**
//
//  高さの比だけが設計稿から導ける倍率だが、実機ではそれでもまだ大きいという判定だったので、
//  `upscale`（既定 0.92）で最後の微調整をする。**カード全体の大小はこの 1 つで決まる。**
//
//  端末ごとの値（`upscale = 0.92`）：
//
//      iPhone SE3   (667) → 1.00（下限。設計稿より小さくはしない）
//      iPhone 16    (852) → 1.09
//      iPhone 17 Pro(874) → 1.12
//      17 Pro Max   (956) → 1.22
//
//  1.12 のとき：行名 14px→15.6pt・節見出し 13→14.5・カード標題 18→20.1・
//  検索欄 40→44.7・作品封面 38×52→42×58・丸釦 34→38.0。
//
//  ============================================================================
//  横方向は必ず詰まる —— それを前提に組む
//  ============================================================================
//
//  幅は 3% しか増えないのに全部を 12% 拡大するので、横方向は約 9% 足りなくなる。
//  これは 390 幅の設計を 402 幅へ 1.12 倍で載せる以上、幾何的に避けられない。
//  いちばん厳しいのは地標カードの動作排（カプセル 3 枚 ＋ 幅 44 の「⋯」）で、
//  実測では `factor ≒ 1.42` が「縮小なしで収まる」上限。`upscale` を上げるときはここを見る。
//  だから**横に並ぶものは必ず伸縮できるように組む**のが規約：
//
//  - 行は［固定の図］［伸びる文字］［固定の右端］。文字が縮んで吸収する。
//  - カプセルは `lineLimit(1)` ＋ `minimumScaleFactor`（`AnitabiCapsuleStyle`）。
//  - 節見出し・行名は 1〜2 行で尾省略（`…`）。**溢れさせない**。
//
//  倍率を変えたいときはここ 1 か所（`upscale`）だけ触る。個別の数値は触らない。
//

import SwiftUI
import UIKit

enum DesignScale {

    /// 設計稿のモックの端末枠（`width: 390px; height: 720px`）。
    static let baseWidth: CGFloat = 390
    static let baseHeight: CGFloat = 720

    /// 高さ比（設計稿から導ける唯一の倍率）に対する微調整。**カード全体の大小はここだけで決まる。**
    ///
    /// 実機での判定履歴（iPhone 17 Pro）：
    ///
    ///     1.15 → factor 1.40 … 「部品が設計稿より大きい。搜索组件尤其明显」→ 却下
    ///     1.00 → factor 1.21 … 「还是有点大，再缩小一点」        → 却下
    ///     0.92 → factor 1.12 … 現在の値
    ///
    /// 上げるときの目安は動作排（カプセル 3 枚 ＋ 幅 44 の「⋯」）が縮み始める `factor ≒ 1.42`。
    static let upscale: CGFloat = 0.92

    /// 画面の実寸（安全区を含む全面）。
    ///
    /// **SwiftUI の geometry では取れない**：`.background { Color.clear.ignoresSafeArea() }` は
    /// 宿主の frame に閉じ込められるので、iPhone 17 Pro で 874 のところが 778 になる（実測）。
    /// それに気付かないまま倍率と档の比率をこの値から出していたため、両方 11% 縮んでいた。
    /// なので `UIWindowScene.screen.bounds` を直に読む —— これは端末の向きに依らない固定値。
    private static var cachedScreenSize: CGSize?

    static var screenSize: CGSize {
        if let cachedScreenSize { return cachedScreenSize }
        guard let size = windowSceneScreenSize() else {
            return CGSize(width: baseWidth, height: baseHeight)
        }
        cachedScreenSize = size
        return size
    }

    /// 画面の長辺（縦持ちの高さ）。档の比率はここから出す。
    static var screenHeight: CGFloat { max(screenSize.width, screenSize.height) }

    private static func windowSceneScreenSize() -> CGSize? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let size = scene?.screen.bounds.size, size.width > 1, size.height > 1 else { return nil }
        return size
    }

    /// 設計稿の 1px を実機で何 pt にするか ——「画面の長辺 ÷ 設計稿の枠の高さ」×`upscale`。
    /// 下限 1.0 ＝ 設計稿より小さくはしない。上限 1.6 ＝ 予想外に大きい画面で崩れないための保険。
    static var factor: CGFloat {
        min(max(screenHeight / baseHeight * upscale, 1.0), 1.6)
    }

    /// 設計稿の px → 実機の pt（**機種比だけ**）。角丸・画像の寸法など、
    /// 字が大きくなっても一緒に育つ必要が無い「形」の値に使う。
    static func value(_ designPixels: CGFloat) -> CGFloat {
        designPixels * factor
    }

    /// 設計稿の px → 実機の pt（機種比 ＋ **Dynamic Type**）。間隔・コントロールの寸法に使う。
    ///
    /// 仕組みは `@ScaledMetric` と同じ（`UIFontMetrics.scaledValue`）。あちらは View の
    /// property wrapper なので `SheetMetrics` のような static トークンには置けない ——
    /// 中身は同じ API なので、こちらを通せば同じ挙動になる。
    ///
    /// 既定の字級では**倍率 1.0**（＝設計稿どおり）。字を大きくしたときだけ余白も一緒に育つ
    /// ——育てないと、字だけ太って余白が相対的に潰れる。
    /// ただし伸びは 1.5 倍で頭打ちにする：アクセシビリティ字級（.body で 3 倍超）に素直に
    /// 追従させると、余白だけで画面が埋まってカードの中身が入らなくなる。
    static func dynamicValue(_ designPixels: CGFloat) -> CGFloat {
        let base = value(designPixels)
        return min(UIFontMetrics(forTextStyle: .body).scaledValue(for: base), base * 1.5)
    }

    /// 設計稿の px 指定のサイズ（サムネイルなど）をまとめて換算する。
    static func size(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: value(width), height: value(height))
    }
}
