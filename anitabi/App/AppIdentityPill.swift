//
//  AppIdentityPill.swift
//  anitabi
//
//  スクリーンショット専用の透かし。`RootView` の根部に置く。
//

import SwiftUI
import UIKit

// MARK: - Dynamic Island 適配

/// Safe Area の上端インセットから Dynamic Island のフレームを推定する。Island 搭載全機種で
/// 「島の中心 y ≈ topInset − 29pt、サイズ ≈ 126×37.3pt」が成立する。
/// ノッチ機（inset ≤ 50）と横向き（inset ≈ 0）は nil ＝ 自動的に非表示。
func dynamicIslandFrame(topInset: CGFloat, containerWidth: CGFloat) -> CGRect? {
    guard topInset >= 51 else { return nil }
    let size = CGSize(width: 126.0, height: 37.33)
    return CGRect(
        x: (containerWidth - size.width) / 2,
        y: topInset - 29.0 - size.height / 2,
        width: size.width,
        height: size.height
    )
}

// MARK: - 应用标识胶囊视图

/// 島のフレームぴったりに描く黒いカプセル。実機では OS が島の領域を常時黒くマスクするので
/// 肉眼では見えず、スクリーンショットにだけアプリ名が写る。
/// **影は付けない** —— 影は島のマスクの外側に描かれるので実機でも見えてしまう。
struct AppIdentityPillView: View {
    var body: some View {
        HStack(spacing: 8) {
            if let uiImage = UIImage(named: "favicon") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
            Text(Bundle.main.displayName ?? "Anitabi")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(Capsule())
    }
}

// MARK: - RootView 根部に貼るオーバーレイ

/// Safe Area を `GeometryReader` で監視するので回転すると即座に再評価される（フレームは島より
/// 2pt 内側）。**`.ignoresSafeArea()` を付けてはいけない** —— `safeAreaInsets` が 0 になって
/// 判定できなくなる。Safe Area 内に置いたまま `y − topInset` に変換して上へ描き出す。
struct AppIdentityPillOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            if let island = dynamicIslandFrame(topInset: topInset, containerWidth: geo.size.width) {
                AppIdentityPillView()
                    .frame(width: island.width - 4, height: island.height - 4)
                    .position(x: island.midX, y: island.midY - topInset)
            }
        }
        .allowsHitTesting(false)
    }
}
