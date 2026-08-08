//
//  HomeBrowseView.swift
//  anitabi
//
//  HomeSheet の「通常ブラウズ」中身。半开/全开の档は RootView が持つ 1 つの
//  `PresentationDetent` でしかないので、ここでは档で内容を出し分けない —— 全セクションを
//  同じ ScrollView に並べ、档が small なら単に下が見えていないだけにする
//  （SwiftUI の既定挙動で、档未満での上スクロールはまず档を広げてから中身が動く）。
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// 附近の再計算をいつ回すかのキー。`Date?` と `DataLoadPhase` の両方が揃って初めて
/// 「意味のある」再計算ができる（前者だけでは `points` が空のままのことがある）。
private struct NearbyRecomputeTrigger: Equatable {
    var timestamp: Date?
    var phase: DataLoadPhase
}

struct HomeBrowseView: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
    let cameraState: MapCameraState?
    @Binding var homeDetent: PresentationDetent
    var onSelectPoint: (ScenePoint) -> Void
    var onFocusCity: (CityTile) -> Void

    @AppStorage("home.browseTab") private var browseTab: WorkBrowseTab = .recentlyUpdated
    @State private var isRandomCoolingDown = false
    /// 視口内作品 chips（阶段 7）の集計結果。デバウンス付きで `store.worksInViewport` を叩く
    /// タスクは**ここ**（`LazyVStack` の外）に置く —— 中身が空（＝高さ 0）の間 `.task` が
    /// レイジーコンテナ内で生かされ続ける保証が無く、実測で一度も発火しないことを確認したため。
    @State private var viewportWorkChips: [(id: Int, count: Int)] = []
    private static let viewportChipsDebounce = Duration.milliseconds(300)

    private enum Anchor: Hashable { case cities }

    /// 「附近」= 5km 圏内。`store.nearby` は 50km まで候補を持つので、ここで絞る。
    private var nearbyWithinRange: [NearbyPoint] {
        Array(store.nearby.filter { $0.distance <= 5_000 }.prefix(3))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                    // 検索行のすぐ下＝横滑り chips 行。`viewportWorkChips` が空の間は高さ 0 に畳まれる。
                    ViewportWorkChips(store: store, router: router, candidates: viewportWorkChips)
                    nearbySection
                    continueWatchingCard
                    quickActionsRow(proxy: proxy)
                    CityGridSection(cities: store.cities, onSelect: onFocusCity)
                        .id(Anchor.cities)
                    WorkBrowseSection(store: store, selectedTab: $browseTab) { id in
                        router.focusWork(id: id)
                    }
                    recentVisitsRow
                    footer
                }
                .padding(.horizontal, SheetMetrics.horizontalPadding)
                // 上の余白は検索行が持っているので、ここでは足さない。
                .padding(.bottom, 32)
            }
        }
        // 位置と読み込み段階の両方をキーにする —— GPS の初回 fix は `store.bootstrap()` の
        // ネットワーク完走より先に届くことがあり、その瞬間の `points` はまだ空。位置だけをキーに
        // すると、シミュレータの静止 fix では二度と再計算が起きず「附近」が永遠に 0 件のまま固まる
        // （実機でも、屋内で動かない間は同じ理屈で起こり得る）。
        .task(id: NearbyRecomputeTrigger(timestamp: locationProvider.location?.timestamp, phase: store.phase)) {
            guard let location = locationProvider.location, !store.isEmpty else { return }
            // データが読み終わった直後の 1 回だけは、移動していなくても間引かずに撮り直す
            // （それより前の「点が空だった」計算結果を上書きするため）。
            let justFinishedLoading = store.phase == .complete
            guard justFinishedLoading || locationProvider.shouldRecomputeNearby(for: location) else { return }
            await store.recomputeNearby(around: location)
            locationProvider.markNearbyRecomputed(at: location)
        }
        .task(id: cameraState) { await refreshViewportWorkChips() }
    }

    // MARK: - 視口作品 chips の集計

    private func refreshViewportWorkChips() async {
        guard let cameraState, cameraState.zoom >= ViewportWorkChips.minZoom else {
            if !viewportWorkChips.isEmpty {
                withAnimation(.anitabiSpring) { viewportWorkChips = [] }
            }
            return
        }
        try? await Task.sleep(for: Self.viewportChipsDebounce)
        guard !Task.isCancelled else { return }
        let result = store.worksInViewport(region: cameraState.region)
        guard !Task.isCancelled else { return }
        let next = result.count >= ViewportWorkChips.minWorkCount ? Array(result.prefix(12)) : []
        withAnimation(.anitabiSpring) { viewportWorkChips = next }
    }

    // MARK: 1. 附近的巡礼点

    @ViewBuilder
    private var nearbySection: some View {
        if !locationProvider.isAuthorized {
            locationGuidanceCard
        } else if !nearbyWithinRange.isEmpty {
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SheetSectionHeader(title: "附近的巡礼点") {
                    Button("更多") {
                        withAnimation(.anitabiSpring) { homeDetent = .large }
                    }
                    .font(.subheadline)
                }
                SheetListCard {
                    ForEach(Array(nearbyWithinRange.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            // 分隔線は文字列まで寄せる（サムネイル 64 ＋ 間隔 12）。
                            Divider().padding(.leading, 64 + SheetMetrics.thumbnailGap)
                        }
                        Button { onSelectPoint(item.point) } label: {
                            NearbyPointRow(store: store, item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if let nearest = store.nearestBeyondNeighborhood {
            SheetGroupCard {
                Text("最近的巡礼点在 \(nearest.point.displayName) · 约 \(DistanceFormatter.string(meters: nearest.distance))")
                    .font(.body)
                Button("带我去") { onSelectPoint(nearest.point) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        // 定位済み・50km 圏内も 0 件のときは何も出さない（巡礼データが存在しない地域）。
    }

    private var locationGuidanceCard: some View {
        SheetGroupCard {
            Label {
                Text("开启定位，看看身边的巡礼点").font(.body)
            } icon: {
                Image(systemName: "location.slash")
                    .foregroundStyle(.secondary)
            }
            Button("去开启", action: requestLocationOrOpenSettings)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
    }

    private func requestLocationOrOpenSettings() {
        if locationProvider.isDenied {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } else {
            locationProvider.requestAuthorization()
        }
    }

    // MARK: 2. 继续查看

    @ViewBuilder
    private var continueWatchingCard: some View {
        if let bangumi = store.lastVisitedBangumi {
            Button { router.focusWork(id: bangumi.id) } label: {
                SheetGroupCard {
                    HStack(spacing: SheetMetrics.thumbnailGap) {
                        CoverThumbnail(bangumi: bangumi).frame(width: 34, height: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("继续查看《\(bangumi.displayName)》").font(.body).lineLimit(1)
                            Text("\(pointCount(for: bangumi)) 个点位")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func pointCount(for bangumi: BangumiLite) -> Int {
        store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
    }

    // MARK: 3. 快捷排

    /// Apple マップのフィルタ chips と同じ「`.bordered` regular カプセル（実測 32pt）」。
    /// 高さは `controlSize` と字級だけで決める —— frame は書かない。
    private func quickActionsRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            Button(action: rollRandomWork) {
                Label("随机作品", systemImage: "dice")
            }
            .disabled(isRandomCoolingDown)

            Button {
                revealCities(proxy: proxy)
            } label: {
                Label("热门城市", systemImage: "building.2")
            }

            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
    }

    /// 「热门城市」釦。档を上げるのと `scrollTo` を**同じ** `withAnimation` に入れると、
    /// sheet の高さが変わっている最中の（＝まだ半开档の）寸法で目標位置が決まってしまい、
    /// 全开档になった後の実際の位置とズレる。档の動き（`anitabiSpring` は response 0.35s）が
    /// 落ち着いてから改めて巻き上げる。既に全开档なら待つ理由が無いのでそのまま巻き上げる。
    private func revealCities(proxy: ScrollViewProxy) {
        guard homeDetent != .large else {
            withAnimation(.anitabiSpring) { proxy.scrollTo(Anchor.cities, anchor: .top) }
            return
        }
        withAnimation(.anitabiSpring) { homeDetent = .large }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.anitabiSpring) { proxy.scrollTo(Anchor.cities, anchor: .top) }
        }
    }

    private func rollRandomWork() {
        guard !isRandomCoolingDown, let work = store.randomWork() else { return }
        router.focusWork(id: work.id)
        router.toast.show(String(localized: "已跳转到《\(work.displayName)》"), symbol: "dice.fill")
        isRandomCoolingDown = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            isRandomCoolingDown = false
        }
    }

    // MARK: 6. 最近查看

    @ViewBuilder
    private var recentVisitsRow: some View {
        let recents = store.recentVisits.compactMap { store.bangumi(id: $0) }
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SheetSectionHeader("最近查看")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(recents) { bangumi in
                            Button { router.focusWork(id: bangumi.id) } label: {
                                VStack(spacing: 6) {
                                    CoverThumbnail(bangumi: bangumi).frame(width: 60, height: 80)
                                    Text(bangumi.displayName)
                                        .font(.footnote)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 60)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: 7. Footer

    private var footer: some View {
        Text("数据由 anitabi.cn 社区贡献 · CC BY-NC-SA 4.0")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}

// MARK: - 4. 热门城市（検索の空入力時にも使い回す）

/// Apple マップの「周辺を検索」グリッドと同じ形（実測 83×83 のタイル＋その下に `.footnote` 2 行）。
/// 4 列にすると 1 辺がちょうど 83pt 前後になる（内容幅 363 − 間隔 8×3 を 4 等分）。
/// 剧照は敷かない（硬約束）——地は `.tertiarySystemFill` ＋ 記号だけ。
struct CityGridSection: View {
    let cities: [CityTile]
    var onSelect: (CityTile) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        if !cities.isEmpty {
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SheetSectionHeader("热门城市")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(cities.prefix(12)) { city in
                        Button { onSelect(city) } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Image(systemName: "building.2")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                                VStack(spacing: 1) {
                                    Text(city.name)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text("\(city.pointCount)")
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - 5. 作品浏览（検索の空入力時にも使い回す）

struct WorkBrowseSection: View {
    let store: AnitabiStore
    @Binding var selectedTab: WorkBrowseTab
    var onSelectWork: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
            SheetSectionHeader("作品浏览")
            Picker("浏览分类", selection: $selectedTab) {
                ForEach(WorkBrowseTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let works = Array(store.works(for: selectedTab).prefix(18))
            SheetListCard {
                ForEach(Array(works.enumerated()), id: \.element.id) { offset, bangumi in
                    if offset > 0 {
                        Divider().padding(.leading, 34 + SheetMetrics.thumbnailGap)
                    }
                    Button { onSelectWork(bangumi.id) } label: {
                        BrowseWorkRow(store: store, bangumi: bangumi)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BrowseWorkRow: View {
    let store: AnitabiStore
    let bangumi: BangumiLite

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            CoverThumbnail(bangumi: bangumi).frame(width: 34, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(bangumi.displayName).font(.body).lineLimit(2)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        // 46pt のカバーが行高を決めるので、上下 12 で 70pt ＝ 実測 69pt 規格とほぼ同値。
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var subtitle: String {
        let count = store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
        let parts: [String?] = [bangumi.cat?.nilIfBlank, bangumi.city?.nilIfBlank, String(localized: "\(count) 个点位")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 附近行

/// `DroppedPinSheet`（阶段 7）の「最近の巡礼点」行とも共有する——内部専用にしていた理由は
/// 「まだ他所から使われていない」だけだったので `private` を外すだけで済む。
struct NearbyPointRow: View {
    let store: AnitabiStore
    let item: NearbyPoint

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            ZStack(alignment: .bottomTrailing) {
                ThumbnailView(url: item.point.thumbnailURL).frame(width: 64, height: 36)
                if let badge = item.point.episodeBadge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.point.displayName.nilIfBlank ?? String(localized: "巡礼点"))
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ThemeDot(color: store.color(forBangumi: item.point.bangumiID))
                    Text(store.name(forBangumi: item.point.bangumiID)).lineLimit(1)
                    Text("·")
                    Text(DistanceFormatter.string(meters: item.distance))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        // 17pt + 3 + 15pt ＝ 41.3 に上下 14 で行高 69pt（実測規格）。
        .padding(.vertical, SheetMetrics.rowVerticalPadding)
        .contentShape(.rect)
    }
}

// MARK: - 共通部品

/// sheet の中身をまとめる器。ガラスにはしない —— Liquid Glass はナビゲーション層専用で、
/// カードなどの内容には使わない（ガラスの上にガラスは破綻する）。
struct SheetGroupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(SheetMetrics.cardPadding)
        .background(Color(.secondarySystemGroupedBackground), in: ConcentricRectangle(corners: .concentric(minimum: 16)))
    }
}

/// 64×36 などの剧照サムネイル。画像が無い／読み込み中は `.tertiarySystemFill` に photo 符号。
struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 作品カバー。無ければテーマ色グラデーションのまま（**文字は置かない**——硬約束）。
struct CoverThumbnail: View {
    let bangumi: BangumiLite

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(bangumi.themeGradient)
            .overlay {
                if let url = bangumi.coverURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// 主題色の小さな色点。硬約束（近白は内側に濃い描边）を list の点にも適用する。
struct ThemeDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if UIColor(color).needsDarkInnerOutline {
                    Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
                }
            }
    }
}
