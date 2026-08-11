//
//  GlassCompat.swift
//  anitabi
//
//  最低適配は **iOS 17.0**（2026-08-10 に 26.0 から引き下げ。SDK は 26 のまま）。
//  Liquid Glass（`glassEffect` / `GlassEffectContainer` / `.glassProminent`）は
//  iOS 26 で入った API なので、26 未満でも走らせるには分岐が要る。
//
//  分岐を各ビューに撒くと「玻璃を足したのに旧 OS の落とし先を書き忘れる」が起きるので、
//  **玻璃を掛ける口はここに集約**する。新しく玻璃を使うときもこのファイルに口を足すこと。
//
//  落とし先の方針：iOS 18 の Apple マップの浮控と同じ「材质 ＋ 極薄い影」。
//  玻璃の屈折・追従は再現しない（似せようとすると旧 OS で不自然になる）。
//  なお SDK 26 で組んでいる以上、iOS 26 実機では系统 chrome も含めて従来どおり玻璃になる。
//

import SwiftUI

extension View {
    /// カプセル形の玻璃背景。iOS 26 は Liquid Glass、それ未満は `.regularMaterial`。
    ///
    /// - Parameter interactive: 押下に追従する玻璃（`.regular.interactive()`）にするか。
    ///   26 未満では無効——材质は押下に反応しないので、単に効果が乗らないだけ。
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

/// `GlassEffectContainer` の互換ラッパー。26 未満では中身を素通しする——容器は
/// 玻璃同士の合流を扱う器なので、玻璃が無い OS では存在しなくていい。
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
