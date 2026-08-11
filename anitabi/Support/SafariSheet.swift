//
//  SafariSheet.swift
//  anitabi
//
//  SFSafariViewController の representable。端末の Safari と Cookie／ログイン状態を共有するので、
//  貢献フロー（补传截图・修正坐标）のログインが Web 側と自然に繋がる —— `WKWebView` ではなく
//  こちらを選ぶ理由がこれ。呈现に使う `SafariItem` は `App/AppRouter.swift` にある。
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
        // URL は呈现のたびに新しい `SafariItem` で差し替わるので、再ロードは発生しない。
    }
}
