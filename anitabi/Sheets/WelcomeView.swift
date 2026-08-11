//
//  WelcomeView.swift
//  anitabi
//
//  初回起動の欢迎页。設計稿「圣地巡礼卡片组件」4a（claude.ai/design）の 1:1 実装 ——
//  背景は縮小した本物の地図（`MapCanvas.japanOverview` と同じ画角で日本列島を一望）、
//  上に載る大カードは常駐 sheet（`RootView.residentSheet`）と**同じ呈现方式**（系统の
//  `.sheet` ＋ `.regularMaterial` ＋ `anitabiCardGlass`）で出す —— 角丸・全幅の面取りを
//  系统に任せることで、本編のカードと寸分違わない縁になる（自前で角丸・縁取りを描かない）。
//  `RootView` が `hasCompletedOnboarding`（UserDefaults）を門にして `.fullScreenCover` で挂ける。
//

import MapKit
import SwiftUI

struct WelcomeView: View {

    /// 「開始使用」タップ時。`hasCompletedOnboarding` の書き込みはこのビュー自身が行うので、
    /// 呼び出し側は `fullScreenCover` を閉じるだけでよい。
    var onFinish: () -> Void

    @State private var safariItem: SafariItem?
    /// カードは常に出ている（本編の常駐 sheet と同じ「閉じない sheet」）。`isPresented` は
    /// 系统の呈现口を借りるための形だけの状態で、ユーザー操作では倒さない
    /// （`interactiveDismissDisabled` を掛けているので下スワイプでも閉じない）。
    @State private var isCardPresented = true

    private static let features: [(icon: String, title: LocalizedStringKey, description: LocalizedStringKey)] = [
        ("magnifyingglass", "探索动画巡礼圣地", "汇集大量动画、漫画、游戏等作品的实地取景地标与配套截图，为你的巡礼做好准备。"),
        ("plus.circle", "轻松贡献与共建", "在地图上点击即可投稿地标截图信息，参与完善地图数据，让更多巡礼人受益。"),
        ("location.north.circle", "随时随地发现周边", "身处巡礼地附近？快速查找你当前位置周围的动画取景地，开启一场说走就走的发现之旅。"),
    ]

    /// このビューだけで使う寸法（設計稿 4a の px、`390×720` の枠を機種比で換算）。カードの
    /// 外枠（角丸・幅）は系统の sheet に任せるので、ここに持つのはカード**内側**の寸法だけ。
    private enum Metrics {
        static var logoSide: CGFloat { SheetMetrics.shape(54) }
        static var logoRadius: CGFloat { SheetMetrics.shape(16) }
        static var iconSlotSide: CGFloat { SheetMetrics.shape(40) }
        static var iconSlotRadius: CGFloat { SheetMetrics.shape(12) }
    }

    var body: some View {
        japanMap
            .ignoresSafeArea()
            .sheet(isPresented: $isCardPresented) { card }
            .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    // MARK: - 背景（本物の地図）

    /// 日本列島を一望する縮小地図。`MapCanvas.japanOverview` と同じ画角にして、初回起動後に
    /// 出る本物の地図と印象を揃える。装飾に徹するので操作は一切受け付けない。
    private var japanMap: some View {
        Map(initialPosition: .region(MapCanvas.japanOverview), interactionModes: [])
            .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
            .allowsHitTesting(false)
    }

    // MARK: - 玻璃大カード（本編の常駐 sheet と同じ呈现方式）

    private var card: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    SheetHairline()
                        .padding(.top, SheetMetrics.scaled(20))
                        .padding(.bottom, SheetMetrics.scaled(4))
                    featureList
                }
                .padding(.horizontal, SheetMetrics.scaled(24))
                .padding(.top, SheetMetrics.scaled(26))
            }
            notice
                .padding(.horizontal, SheetMetrics.scaled(24))
                .padding(.top, SheetMetrics.scaled(18))
            startButton
                .padding(.horizontal, SheetMetrics.scaled(24))
                .padding(.vertical, SheetMetrics.scaled(14))
        }
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        // 本編の常駐 sheet（`RootView.residentSheet`）と同じ地：系统の material の上に
        // 設計稿の合成色を敷く。角丸・全幅はここでは触らない＝系统の sheet 呈现そのまま。
        .presentationBackground {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.anitabiCardGlass)
                .ignoresSafeArea()
        }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(alignment: .center, spacing: SheetMetrics.scaled(14)) {
            VStack(alignment: .leading, spacing: 3) {
                Text("欢迎来到")
                    .font(SheetFont.welcomeEyebrow)
                    .foregroundStyle(Color.anitabiInkSecondary)
                Text(Bundle.main.displayName ?? "Anitabi")
                    .font(SheetFont.welcomeTitle)
                    .foregroundStyle(Color.anitabiInk)
            }
            Spacer(minLength: 0)
            appIcon
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = Bundle.main.appIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFill()
                .frame(width: Metrics.logoSide, height: Metrics.logoSide)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.logoRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Metrics.logoRadius, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: Metrics.logoSide, height: Metrics.logoSide)
                .overlay {
                    Image(systemName: "app.fill")
                        .font(.system(size: Metrics.logoSide * 0.4))
                        .foregroundStyle(Color.anitabiOnAccent)
                }
        }
    }

    // MARK: - 特性 3 行

    private var featureList: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.scaled(18)) {
            ForEach(Array(Self.features.enumerated()), id: \.offset) { _, feature in
                featureRow(feature)
            }
        }
        .padding(.top, SheetMetrics.scaled(14))
    }

    private func featureRow(_ feature: (icon: String, title: LocalizedStringKey, description: LocalizedStringKey)) -> some View {
        HStack(alignment: .top, spacing: SheetMetrics.scaled(12)) {
            RoundedRectangle(cornerRadius: Metrics.iconSlotRadius, style: .continuous)
                .fill(Color.anitabiSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.iconSlotRadius, style: .continuous)
                        .strokeBorder(Color.anitabiSurfaceStroke, lineWidth: 1)
                }
                .frame(width: Metrics.iconSlotSide, height: Metrics.iconSlotSide)
                .overlay {
                    Image(systemName: feature.icon)
                        .font(.system(size: SheetMetrics.scaled(17), weight: .semibold))
                        .foregroundStyle(Color.anitabiInk)
                }
                .shadow(color: .anitabiInk.opacity(0.08), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(SheetFont.featureTitle)
                    .foregroundStyle(Color.anitabiInk)
                Text(feature.description)
                    .font(SheetFont.rowMeta)
                    .foregroundStyle(Color.anitabiInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CC 協議

    private var notice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本工具基于社区共建，数据遵循 署名、非商业性使用、相同方式共享 的 CC BY-NC-SA 4.0 协议共享。")
                .font(SheetFont.micro)
                .foregroundStyle(Color.anitabiInkTertiary)

            Button {
                let localizedURL = String(localized: "https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh-hans")
                safariItem = SafariItem(url: URL(string: localizedURL) ?? AnitabiWebLink.etiquetteIssue)
            } label: {
                Text("了解协议细节")
                    .font(SheetFont.micro.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - CTA

    /// prominent は画面に 1 個だけ（設計規律）。高さは `controlSize` に任せ、手書きの
    /// `frame(height:)` は使わない。
    private var startButton: some View {
        Button {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            onFinish()
        } label: {
            Text("开始使用")
                .frame(maxWidth: .infinity)
        }
        .prominentActionButtonStyle()
        .controlSize(.large)
    }
}
