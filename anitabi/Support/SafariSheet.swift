//
//  SafariSheet.swift
//  anitabi
//
//  SFSafariViewController の representable。端末の Safari と Cookie／ログイン状態を共有するため、
//  貢献フロー（补传截图・修正坐标）のログインが Web 側と自然に繋がる——これが `WKWebView` ではなく
//  こちらを選ぶ理由（阶段 6 で PointCardSheet の「补传截图/修正坐标」もここへ相乗りする）。
//
//  `SafariItem`（`Identifiable { let url: URL }`）は既に `App/AppRouter.swift` にある
//  （阶段 6 で router 経由の呈现に使う想定で先に用意されていた）。同名型をここで再宣言すると
//  重複定義エラーになるため、型はそちらを再利用する。作品カードは router を介さず、
//  カード自身の `@State` で `.sheet(item:)` を出す（他カードの呈现スタックに影響させないため）。
//

import SafariServices
import SwiftUI

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = .systemBlue
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // URL は呈现のたびに新しい `SafariItem`（＝新しい `.sheet(item:)`）で差し替わるので、
        // 同一インスタンスへの再ロードは発生しない。
    }
}
