//
//  DesignScale.swift
//  anitabi
//
//  設計稿の px を実機の pt へ等比換算する係数。倍率を変えたいときは `upscale` だけを触る。
//  倍率は**高さ比**から出すので幅の伸びが追いつかず、**横方向は約 9% 足りなくなる** ——
//  避けられないので、横に並ぶものは必ず伸縮できるように組むのが規約（尾省略／縮小）。
//

import SwiftUI
import UIKit

enum DesignScale {

    /// 設計稿のモックの端末枠（`width: 390px; height: 720px`）。
    static let baseWidth: CGFloat = 390
    static let baseHeight: CGFloat = 720

    /// 高さ比に対する微調整。**カード全体の大小はここだけで決まる。** 出所を高さ比にしたのは、
    /// それだけが「設計稿をその端末の画面いっぱいに置いた見え方」を表すから（幅比は 3% しか
    /// 伸びない）。上げるときの目安は、地標カードの動作排が縮み始める `factor ≒ 1.42`。
    static let upscale: CGFloat = 0.92

    /// 画面の実寸（安全区を含む全面）。**SwiftUI の geometry では取れない** ——
    /// `.ignoresSafeArea()` を付けた背景も宿主の frame に閉じ込められ、874 のところが 778 になる。
    /// 端末の向きに依らない `UIWindowScene.screen.bounds` を直に読む。
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
    /// 中身は `@ScaledMetric` と同じ `UIFontMetrics`（あちらは property wrapper なので static
    /// トークンには置けない）。伸びは 1.5 倍で頭打ち —— 素直に追従すると余白だけで画面が埋まる。
    static func dynamicValue(_ designPixels: CGFloat) -> CGFloat {
        let base = value(designPixels)
        return min(UIFontMetrics(forTextStyle: .body).scaledValue(for: base), base * 1.5)
    }

    /// 設計稿の px 指定のサイズ（サムネイルなど）をまとめて換算する。
    static func size(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: value(width), height: value(height))
    }
}
