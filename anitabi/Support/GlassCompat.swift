//
//  GlassCompat.swift
//  anitabi
//
//  最低適配は **iOS 17.0**（SDK は 26）なので Liquid Glass には分岐が要る。撒くと「玻璃を足したのに
//  旧 OS の落とし先を書き忘れる」が起きるので、**玻璃を掛ける口はここに集約**する（新しく使うとき
//  もここに口を足す）。落とし先は「材质 ＋ 極薄い影」だけで、屈折・追従は真似しない。
//

import SwiftUI

extension View {
    /// カプセル形の玻璃背景。iOS 26 は Liquid Glass、それ未満は `.regularMaterial`。
    /// - Parameter interactive: 押下に追従する玻璃にするか（26 未満では単に効果が乗らない）。
    @ViewBuilder
    func capsuleGlass(interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: .capsule)
            } else {
                glassEffect(.regular, in: .capsule)
            }
        } else {
            background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
    }

    /// 画面に 1 個だけ置く主行動釦の意匠。iOS 26 は `.glassProminent`、それ未満は
    /// `.borderedProminent`（どちらも tint 色の塗り＋白字という同じ役どころ）。
    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// `GlassEffectContainer` の互換ラッパー。容器は玻璃同士の合流を扱う器なので、
/// 玻璃が無い OS では中身を素通しするだけでよい。
struct GlassContainerCompat<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
