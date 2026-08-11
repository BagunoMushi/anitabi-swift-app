//
//  AppIdentityPill.swift
//  anitabi
//
//  スクリーンショット専用の透かし。`RootView` の根部に置く。
//

import SwiftUI
import UIKit

// MARK: - Dynamic Island 適配

/// Dynamic Island 搭載機か。島機は縦向きで上端インセット 55〜63pt、ノッチ機は ≤50、
/// 横向きは ≈0 —— 後者 2 つは nil ＝自動的に非表示（横では島が横の縁へ回るので隠せない）。
func hasDynamicIsland(topInset: CGFloat) -> Bool { topInset >= 55 }

/// 島の内側へ確実に納まるカプセルの寸法（bangumi の `ScreenshotWatermarkPill` と同じ値）。
///
/// 島の実測は世代でずれる：14/15 世代は天端 ≈11pt、16/17 Pro と iPhone Air は ≈15pt、
/// 寸法は 126〜133 × 37pt。**上端インセットから島枠を逆算して枠いっぱいに描くと**
/// （旧実装の `topInset − 29` 中心・126×37.3）天端の低い Air 世代で数 pt はみ出し、
/// 実機でも島の外に細い縁が見えてしまう。だから逆算をやめ、全機種の共通部分に収まる
/// 小さめのカプセルを**物理上端から固定 17pt**に置く。
enum IdentityPillMetrics {
    /// 島の高さ 37pt に対し 17〜45pt に収まる高さ。
    static let height: CGFloat = 28
    /// 島の幅 126pt に対する上限。
    static let maxWidth: CGFloat = 119
    /// 物理上端からカプセル天端までの距離。
    static let topFromScreenEdge: CGFloat = 17
}

// MARK: - 应用标识胶囊视图

/// 島に隠れるカプセル。実機では OS が島の領域を常時マスクするので肉眼では見えず、
/// スクリーンショットにだけアプリ名が写る。
/// **影は付けない** —— 影は島のマスクの外側に描かれるので実機でも見えてしまう。
struct AppIdentityPillView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            if let uiImage = UIImage(named: "favicon") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
            Text(Bundle.main.displayName ?? "Anitabi")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.anitabiOnIdentityPill)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .frame(height: IdentityPillMetrics.height)
        .frame(maxWidth: IdentityPillMetrics.maxWidth)
        // 浅色は下の sheet と**同じ地**（`RootView` の `presentationBackground` と同構成：
        // `.regularMaterial` に設計稿の合成色を重ねる）。夜側は設計稿の墨の実心。
        .background {
            if colorScheme == .dark {
                Capsule().fill(Color.anitabiIdentityPill)
            } else {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Color.anitabiCardGlass)
                    .clipShape(Capsule())
            }
        }
        // 浅色の地は半透明なので、明るい地図の上では縁が無いと輪郭が溶ける。
        .overlay(Capsule().strokeBorder(Color.anitabiHairline, lineWidth: 0.5))
        .clipShape(Capsule())
    }
}

// MARK: - RootView 根部に貼るオーバーレイ

/// Safe Area を `GeometryReader` で監視するので回転すると即座に再評価される。
/// **`.ignoresSafeArea()` を付けてはいけない** —— `safeAreaInsets` が 0 になって判定できなく
/// なる。Safe Area 内に置いたまま `topFromScreenEdge − topInset` へずらして上へ描き出す。
struct AppIdentityPillOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            if hasDynamicIsland(topInset: topInset) {
                AppIdentityPillView()
                    .frame(maxWidth: .infinity)  // 横方向は中央
                    .offset(y: IdentityPillMetrics.topFromScreenEdge - topInset)
            }
        }
        .allowsHitTesting(false)
    }
}
