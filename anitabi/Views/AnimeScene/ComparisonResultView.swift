//
//  ComparisonResultView.swift
//  anitabi
//
//  対比撮影の成果物（上下対比カード／合体成片のどちらも同じこの 1 画面で受ける）。
//  保存は `PhotoLibrarySaver`（`.addOnly` 権限のみ）、共有は `ShareLink`。
//

import SwiftUI

// MARK: - 比较结果视图
struct ComparisonResultView: View {
    // 属性
    let comparisonImage: UIImage
    let sceneName: String
    let dismiss: () -> Void

    @State private var isSaving = false
    @State private var showSavedAlert = false
    @State private var saveError: String?
    @State private var showPermissionAlert = false

    // 常量
    private enum Constants {
        static let buttonSize: CGFloat = 60
        static let buttonSpacing: CGFloat = 40  // 调整为与SceneComparisonView一致
        static let iconSize: CGFloat = 24  // 调整为与SceneComparisonView一致
    }

    /// `ShareLink` に渡す共有アイテム（`Transferable` なのは `UIImage` ではなく `Image` の側）。
    private var shareImage: Image { Image(uiImage: comparisonImage) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    imageSection
                    buttonSection
                }
            }
            .navigationTitle("\(sceneName) 对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: dismiss)
                }
            }
            .alert("已保存到相册", isPresented: $showSavedAlert) {
                Button("确定", role: .cancel) {}
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
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("确定", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        // 画面は常に黒地なので、明るい配色のままだとタイトルが黒地に黒で読めない。
        .preferredColorScheme(.dark)
    }

    // 图像部分
    private var imageSection: some View {
        Image(uiImage: comparisonImage)
            .resizable()
            .scaledToFit()
            .padding()
    }

    // 按钮部分
    private var buttonSection: some View {
        HStack(spacing: Constants.buttonSpacing) {
            saveButton
            shareButton
        }
        .padding(.bottom, 30)
    }

    // 保存按钮
    private var saveButton: some View {
        Button(action: saveImageToGallery) {
            circleLabel(
                systemImage: isSaving ? "hourglass" : "square.and.arrow.down",
                title: String(localized: "保存")
            )
        }
        .disabled(isSaving)
    }

    // 分享按钮
    private var shareButton: some View {
        ShareLink(item: shareImage, preview: SharePreview(sceneName, image: shareImage)) {
            circleLabel(systemImage: "square.and.arrow.up", title: String(localized: "分享"))
        }
    }

    private func circleLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: 6) {  // 添加了spacing参数
            Image(systemName: systemImage)
                .font(.system(size: Constants.iconSize))
                .foregroundColor(.white)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(Circle().fill(Color.black.opacity(0.6)))  // 更新背景色和透明度

            Text(title)
                .font(.caption)
                .foregroundColor(.white)
        }
    }

    // 保存图像功能
    private func saveImageToGallery() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await PhotoLibrarySaver.save(comparisonImage)
                showSavedAlert = true
            } catch let error as PhotoLibrarySaver.SaveError where error.isPermissionDenied {
                showPermissionAlert = true
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
