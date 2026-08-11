//
//  ToastCenter.swift
//  anitabi
//
//  画面上部に浮かぶ一時通知。「操作が起きたことを一言で伝える」専用なので、エラーの詳細や
//  アクション付きの通知はここに乗せない（それは alert の役目）。router にぶら下げているのは、
//  既に router を持っているカードからそのまま呼べるようにするため。
//

import SwiftUI
import UIKit

// MARK: - Toast

/// 1 件のトースト。`id` を毎回作り直すのは、同じ文言を連続で出しても「同じ内容だから無視」に
/// ならず、タイマーが確実にリセットされるようにするため。
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String?
}

// MARK: - ToastCenter

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    /// 表示する。連続で呼ばれたら前のタイマーは捨てて 2 秒からやり直す。
    func show(_ text: String, symbol: String? = nil) {
        dismissTask?.cancel()
        let toast = Toast(text: text, symbol: symbol)
        current = toast
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            // 待っている間に次の `show` が来ていたら（＝ toast が差し替わっていたら）何もしない。
            guard let self, self.current?.id == toast.id else { return }
            self.current = nil
        }
    }
}

// MARK: - オーバーレイ

/// RootView の最上段に置く玻璃カプセル。位置決めは呼び出し側の責務で、ここは見た目だけ。
struct ToastOverlayView: View {
    var toast: Toast?

    var body: some View {
        Group {
            if let toast {
                HStack(spacing: 6) {
                    if let symbol = toast.symbol {
                        Image(systemName: symbol)
                    }
                    Text(toast.text)
                        .lineLimit(1)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .capsuleGlass()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast?.id)
        // タップを奪わない——地図やコントロールの上に浮いているだけの通知。
        .allowsHitTesting(false)
    }
}
