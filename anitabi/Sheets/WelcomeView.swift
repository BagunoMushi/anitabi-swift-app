//
//  WelcomeView.swift
//  anitabi
//
//  旧 `UIOnboarding`（`Views/OnboardingView.swift`、阶段 9 で削除）の原生置き換え。
//  文案は一言一句そのまま流用（xcstrings の既存キーを再利用——同じ zh-Hans 原文を書けば
//  Xcode の文字列カタログが既存キーへ束ねるので、翻訳を作り直さずに済む）。
//  見た目だけを Apple 純正の設定/オンボーディング画面の作法（大アイコン→タイトル→
//  特性 3 行→注記→全幅 CTA）に合わせて全面新規に書いた。
//
//  `RootView` が `hasCompletedOnboarding`（UserDefaults、旧キーをそのまま継承——
//  既存ユーザーに再表示させないため）を門にして `.fullScreenCover` で挂ける。
//

import SwiftUI

struct WelcomeView: View {

    /// 「開始使用」タップ時。`hasCompletedOnboarding` の書き込みはこのビュー自身が行う
    /// （旧 `UIOnboardingHelper` の `didFinishOnboarding` と同じ責務分担）。呼び出し側は
    /// `fullScreenCover` を閉じるだけでよい。
    var onFinish: () -> Void

    @State private var safariItem: SafariItem?

    /// 特性 3 行。アイコン・文案は旧 `UIOnboardingHelper.setUpFeatures()` の 3 件と一言一句同じ
    /// （xcstrings の既存キーをそのまま指す）。
    private static let features: [(icon: String, title: LocalizedStringKey, description: LocalizedStringKey)] = [
        ("map.fill", "探索动画巡礼圣地", "汇集大量动画、漫画、游戏等作品的实地取景地标与配套截图，为你的巡礼做好准备。"),
        ("square.and.pencil", "轻松贡献与共建", "在地图上点击即可投稿地标截图信息，参与完善地图数据，让更多巡礼人受益。"),
        ("location.fill", "随时随地发现周边", "身处巡礼地附近？快速查找你当前位置周围的动画取景地，开启一场说走就走的发现之旅。"),
    ]

    /// このビューだけで使う寸法。共有トークン（`SheetMetrics`）に無い値は、
    /// A4 spec が直接指定した数値（アイコン 88pt・特性アイコン槽位 40pt）をここへ名前を付けて置く
    /// ——「魔数を書かない」の趣旨は「出所不明な値を書かない」ことなので、根拠付きの固定値は
    /// 定数化した上でここに閉じ込める（他画面から参照されない一回性の値）。
    private enum Metrics {
        static let iconSide: CGFloat = 88
        static let iconCornerRadius: CGFloat = iconSide * 0.2237  // iOS の角丸比率（squircle 近似）
        static let featureIconSlot: CGFloat = 40
        static let topInset: CGFloat = 32
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SheetMetrics.sectionSpacing) {
                header
                VStack(spacing: SheetMetrics.sectionSpacing) {
                    ForEach(Array(Self.features.enumerated()), id: \.offset) { _, feature in
                        featureRow(feature)
                    }
                }
                notice
            }
            .padding(.horizontal, SheetMetrics.horizontalPadding)
            .padding(.top, Metrics.topInset)
            // 下は固定 CTA の分だけ余分に空けて、スクロール最下端でも本文が隠れないようにする。
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) { startButton }
        .background(Color(.systemBackground))
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    // MARK: - 見出し

    private var header: some View {
        VStack(spacing: 16) {
            appIcon
            VStack(spacing: 2) {
                Text("欢迎来到")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                Text(Bundle.main.displayName ?? "Anitabi")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = Bundle.main.appIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: Metrics.iconSide, height: Metrics.iconSide)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: Metrics.iconSide, height: Metrics.iconSide)
                .overlay {
                    Image(systemName: "app.fill")
                        .font(.system(size: Metrics.iconSide * 0.4))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - 特性 3 行

    private func featureRow(_ feature: (icon: String, title: LocalizedStringKey, description: LocalizedStringKey)) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: Metrics.featureIconSlot, height: Metrics.featureIconSlot)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CC 協議

    private var notice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("本工具基于社区共建，数据遵循 署名、非商业性使用、相同方式共享 的 CC BY-NC-SA 4.0 协议共享。")
            } icon: {
                Image(systemName: "book.closed")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                let localizedURL = String(localized: "https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh-hans")
                safariItem = SafariItem(url: URL(string: localizedURL) ?? AnitabiWebLink.etiquetteIssue)
            } label: {
                Text("了解协议细节")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - CTA

    /// prominent は画面に 1 個だけ（設計規律）。全幅・`controlSize(.large)`（50pt 実測）で
    /// 手書き `frame(height:)` は使わない。
    private var startButton: some View {
        Button {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            onFinish()
        } label: {
            Text("开始使用")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal, SheetMetrics.horizontalPadding)
        .padding(.vertical, 10)
    }
}
