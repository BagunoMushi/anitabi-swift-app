//
//  RemoteImage.swift
//  anitabi
//
//  下拉カードの剧照／封面を「滚动で可視域に入った時だけ」読む遅延画像。`AsyncImage` は**視図が
//  作られた瞬間**に取りに行くので、点数の多い作品を開くと画面外の数百枚が一斉に飛ぶ。
//  復号済みの `UIImage` は `RemoteImageCache` が持つので、戻って来た行はちらつかない。
//

import SwiftUI
import UIKit

// MARK: - 共有キャッシュ

/// URL ごとの復号済み画像を持つメモリキャッシュ ＋ 同一 URL の多重取得の合流。
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    /// `NSCache` 自体はスレッドセーフなので、同期読みだけ開けておく（視図の `init` から引いて
    /// 初回描画の placeholder を飛ばすため）。`Sendable` ではないので `unsafe` を明示する。
    private nonisolated(unsafe) let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    private init() {}

    nonisolated func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// 同じ URL を複数の行が同時に欲しがっても、走る取得は 1 本だけ。
    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        if let running = inflight[url] { return await running.value }

        // 呼び出し側の視図が消えても走り切らせる —— 剧照は小さいので、途中で捨てて
        // 次に取り直すより貯めた方が安い。
        let task = Task { [self] in
            let image = await Self.download(url)
            if let image {
                memory.setObject(image, forKey: url as NSURL, cost: image.approximateByteCount)
            }
            inflight[url] = nil
            return image
        }
        inflight[url] = task
        return await task.value
    }

    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let image = UIImage(data: data) else { return nil }
        // 復号はここで済ませる。行に貼ってから復号すると滚动中にコマが落ちる。
        return await image.byPreparingForDisplay() ?? image
    }
}

private extension UIImage {
    var approximateByteCount: Int {
        Int(size.width * scale * size.height * scale * 4)
    }
}

// MARK: - 視図

enum RemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

/// 読み込みを始める合図。
enum RemoteImageTrigger {
    /// ScrollView の可視域に入ってから読む（下拉カードの一覧の既定）。
    case scrollVisibility
    /// 出た時点で読む。ScrollView の外に置く画像だけこちら。
    case appearance
}

/// `AsyncImage` と同じ書き味のまま、読み始めを可視域まで遅らせた版。
struct RemoteImage<Content: View>: View {
    let url: URL?
    var trigger: RemoteImageTrigger = .scrollVisibility
    @ViewBuilder var content: (RemoteImagePhase) -> Content

    /// 素通りした行では取りに行かないための待ち。速い滚动で画面を通過するだけの行を弾く。
    private static var settleDelay: Duration { .milliseconds(60) }

    @State private var loaded: UIImage?
    @State private var loadedURL: URL?
    @State private var didFail = false
    @State private var isVisible = false

    init(
        url: URL?,
        trigger: RemoteImageTrigger = .scrollVisibility,
        @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
    ) {
        self.url = url
        self.trigger = trigger
        self.content = content
        // 既に持っている画像は初回描画から出す（戻って来た行がちらつかない）。
        let hit = url.flatMap { RemoteImageCache.shared.cached($0) }
        _loaded = State(initialValue: hit)
        _loadedURL = State(initialValue: hit == nil ? nil : url)
    }

    var body: some View {
        // 下地を `Color.clear` にして常に器いっぱいの矩形を持たせる —— 面積 0 の視図は
        // 「可視」と判定されず、永遠に読み始めない。
        Color.clear
            .overlay { content(phase) }
            .modifier(ScrollVisibilityReporter { isVisible = $0 })
            .task(id: LoadKey(url: url, active: isActive)) { await load() }
    }

    private var phase: RemoteImagePhase {
        if let loaded { return .success(Image(uiImage: loaded)) }
        return didFail ? .failure : .empty
    }

    private var isActive: Bool {
        trigger == .appearance || isVisible
    }

    /// `.task(id:)` の識別子。可視状態が変わると走り直す（＝画面外へ出た取得は中断される）。
    private struct LoadKey: Hashable {
        let url: URL?
        let active: Bool
    }

    private func load() async {
        guard let url else {
            loaded = nil
            loadedURL = nil
            didFail = false
            return
        }
        // 同じ視図が別の点位に使い回された時だけ、前の画像を捨てる。
        if loadedURL != url {
            loaded = RemoteImageCache.shared.cached(url)
            loadedURL = loaded == nil ? nil : url
            didFail = false
        }
        guard loaded == nil, isActive else { return }

        if trigger == .scrollVisibility {
            try? await Task.sleep(for: Self.settleDelay)
            if Task.isCancelled { return }
        }
        let image = await RemoteImageCache.shared.image(for: url)
        if Task.isCancelled { return }
        guard let image else {
            didFail = true
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            loaded = image
            loadedURL = url
            didFail = false
        }
    }
}

/// 可視状態の報告。`onScrollVisibilityChange` は iOS 18 からなので、それ以前は判定手段が無く
/// 「出た時点で読む」に落とす。
private struct ScrollVisibilityReporter: ViewModifier {
    let action: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.01, action)
        } else {
            content.onAppear { action(true) }
        }
    }
}
