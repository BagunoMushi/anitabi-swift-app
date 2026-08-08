//
//  MapFloatingControls.swift
//  anitabi
//
//  地図の上に浮く操作系。ここが Liquid Glass を使う唯一のレイヤー
//  （コンテンツ＝白カード・劇照・カバーは実体のまま）。
//
//  注意：首屏に対比カメラのボタンは置かない。カメラは「どの劇照と比べるか」が
//  決まって初めて意味を持つ機能なので、入口は地標詳細側に置く。
//

import SwiftUI

// MARK: - 右側の縦並び

struct MapFloatingControls: View {
    /// 地図が回転しているか。真北のときは指南針を出さない。
    let mapHeading: Double
    let isLocationDenied: Bool
    let isPhotoLayerVisible: Bool

    let onLocate: () -> Void
    let onTogglePhotoLayer: () -> Void
    let onResetNorth: () -> Void

    /// 同じ union に属するガラスは 1 枚のカプセルに融合する。
    @Namespace private var glass

    private var isRotated: Bool { abs(mapHeading) > 0.5 }

    var body: some View {
        // Apple マップと同じく、地図の操作系は**縦に連なった 1 枚のガラス**にする。
        // 個別の丸ボタンを並べるのは iOS 18 までの形。
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                GlassRailButton(
                    systemImage: isLocationDenied ? "location.slash" : "location",
                    accessibilityLabel: "定位到我的位置",
                    action: onLocate
                )
                .opacity(isLocationDenied ? 0.55 : 1)
                .glassEffectUnion(id: "map-controls", namespace: glass)

                GlassRailButton(
                    systemImage: isPhotoLayerVisible ? "square.stack.3d.up" : "square.stack.3d.up.slash",
                    accessibilityLabel: "切换剧照图层",
                    action: onTogglePhotoLayer
                )
                .glassEffectUnion(id: "map-controls", namespace: glass)

                if isRotated {
                    GlassRailButton(
                        systemImage: "location.north.line",
                        accessibilityLabel: "回到正北",
                        action: onResetNorth
                    )
                    .rotationEffect(.degrees(-mapHeading))
                    .glassEffectUnion(id: "map-controls", namespace: glass)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRotated)
    }
}

// MARK: - ガラスの縦連ボタン

struct GlassRailButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.title)
                .frame(width: Metrics.controlSize, height: Metrics.controlSize)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - 左上の状態カプセル

/// 「視野内 8 部作品 · 47 点」。地図を動かすたびに更新される、地図そのものの状態表示。
struct MapStatusCapsule: View {
    let workCount: Int
    let pointCount: Int

    var body: some View {
        Text("视野内 \(workCount) 部作品 · \(pointCount) 点")
            .font(.rounded(12, .heavy))
            .foregroundStyle(Palette.sectionHeader)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .glassEffect(.regular, in: .capsule)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: pointCount)
    }
}
