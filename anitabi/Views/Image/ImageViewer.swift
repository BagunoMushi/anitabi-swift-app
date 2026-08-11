//
//  ImageViewer.swift
//  anitabi
//
//  剧照の全屏ビューア（ピンチ／ドラッグ／ダブルタップで原寸に戻す）。
//  保存は `PhotoLibrarySaver`（`.addOnly` 権限のみ）に任せる。
//

import SwiftUI
import UIKit

struct ImageViewer: View {
    // MARK: - Properties
    @Environment(\.dismiss) private var dismiss
    let imageURL: URL?
    /// タイトル（地標名）。無指定なら空のままインライン表示。
    var title: String? = nil

    // MARK: - States
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingSaveConfirmation = false
    @State private var showPermissionAlert = false
    @State private var saveError: String? = nil
    @State private var imageLoadingState: LoadingState = .loading

    enum LoadingState {
        case loading
        case success
        case failure
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    
                    imageContent
                }
            }
            .navigationTitle(title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                leadingToolbarItems
                trailingToolbarItems
            }
            .alert("已保存", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            }
            .alert("无法保存到相册", isPresented: $showPermissionAlert) {
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在「设置」中允许本 App 将照片添加到相册。")
            }
            .alert("出现错误", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                if let error = saveError {
                    Text(error)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - View Components
    @ViewBuilder
    private var imageContent: some View {
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    loadingView
                case .success(let image):
                    successView(image: image)
                case .failure:
                    failureView
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
    
    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .onAppear {
                imageLoadingState = .loading
            }
    }
    
    private func successView(image: Image) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(dragGesture)
            .gesture(pinchGesture)
            .onTapGesture(count: 2, perform: resetImage)
            .onAppear {
                imageLoadingState = .success
            }
    }
    
    private var failureView: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.white)
            Text("无法加载图片")
                .foregroundColor(.white)
                .padding(.top, 8)
        }
        .onAppear {
            imageLoadingState = .failure
        }
    }
    
    // MARK: - Toolbar Items
    private var leadingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
            }
        }
    }
    
    private var trailingToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 20) {
                if let url = imageURL, imageLoadingState == .success {
                    Button(action: {
                        saveImageToPhotoLibrary(from: url)
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.white)
                    }
                    
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
    
    // MARK: - Gestures
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                // スケール制限（0.5〜3.0）
                let newScale = scale * delta
                scale = min(max(newScale, 0.5), 3.0)
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }
    
    // MARK: - Actions
    private func resetImage() {
        withAnimation(.spring()) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    /// CDN から原寸を取り直して保存する（表示中の `AsyncImage` は `UIImage` を渡してくれない）。
    private func saveImageToPhotoLibrary(from url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    saveError = String(localized: "下载图片失败")
                    return
                }
                try await PhotoLibrarySaver.save(image)
                showingSaveConfirmation = true
            } catch let error as PhotoLibrarySaver.SaveError where error.isPermissionDenied {
                showPermissionAlert = true
            } catch {
                saveError = String(localized: "保存到相册失败: \(error.localizedDescription)")
            }
        }
    }
}

extension ImageViewer {
    /// `.fullScreenCover(item:)` から開く入口。閉じるのは `@Environment(\.dismiss)` 側。
    init(url: URL, title: String? = nil) {
        self.init(imageURL: url, title: title)
    }
}
