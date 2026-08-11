//
//  ToastCenter.swift
//  anitabi
//
//  画面上部に浮かぶ一時通知。「操作が起きたことを一言で伝える」専用の軽い仕組みで、
//  エラーの詳細やアクション付きの通知はここに乗せない（それは alert / SafariSheet の役目）。
//
//  router（`AppRouter.toast`）にぶら下げているのは、`@Bindable var router` を既に持っている
//  カード（PointCardSheet 等）からそのまま `router.toast.show(...)` できるようにするため——
//  新しい環境値／追加のバケツリレー配線を増やさずに済む。
//

import SwiftUI
import UIKit

// MARK: - Toast

/// 1 件のトースト。`id` を毎回作り直すことで、同じ文言を連続で出しても
/// `ToastCenter` 側の 2 秒タイマーが確実にリセットされる（`==` 比較で「同じ内容だから無視」
/// にならないようにするため、あえて `UUID` を equality に含めている）。
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

    /// 表示する。連続で呼ばれたら前のタイマーは捨てて 2 秒からやり直す
    /// （「已拷贝坐标」を連打しても毎回ちゃんと 2 秒残る、という体感を優先）。
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

/// RootView の最上段に置く玻璃カプセル本体。位置決め（安全区からの距离・水平中央寄せ）は
/// 呼び出し側（RootView）の責務——ここは「見た目」だけを持つ。
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
