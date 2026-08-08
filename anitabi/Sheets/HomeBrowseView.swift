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
    @Binding var homeDetent: PresentationDetent
    var onSelectPoint: (ScenePoint) -> Void
    var onFocusCity: (CityTile) -> Void

    @AppStorage("home.browseTab") private var browseTab: WorkBrowseTab = .recentlyUpdated
    @State private var isRandomCoolingDown = false

    private enum Anchor: Hashable { case cities }

    /// 「附近」= 5km 圏内。`store.nearby` は 50km まで候補を持つので、ここで絞る。
    private var nearbyWithinRange: [NearbyPoint] {
        Array(store.nearby.filter { $0.distance <= 5_000 }.prefix(3))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    // 阶段 7: ViewportWorkChips（視口内複数作品フィルタの横滑り chips）は
                    // 検索行のすぐ下＝ここに入る。
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
                .padding(.horizontal, 16)
                .padding(.top, 8)
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
    }

    // MARK: 1. 附近的巡礼点

    @ViewBuilder
    private var nearbySection: some View {
        if !locationProvider.isAuthorized {
            locationGuidanceCard
        } else if !nearbyWithinRange.isEmpty {
            SheetGroupCard {
                HStack {
                    Text("附近的巡礼点").font(.headline)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.anitabiSpring) { homeDetent = .large }
                    } label: {
                        Text("更多").font(.subheadline).foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 12) {
                    ForEach(nearbyWithinRange) { item in
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
                    HStack(spacing: 12) {
                        CoverThumbnail(bangumi: bangumi).frame(width: 34, height: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("继续查看《\(bangumi.displayName)》").font(.body).lineLimit(1)
                            Text("\(pointCount(for: bangumi)) 个点位")
                                .font(.footnote)
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

    private func quickActionsRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Button(action: rollRandomWork) {
                Label("随机作品", systemImage: "dice")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(isRandomCoolingDown)

            Button {
                withAnimation(.anitabiSpring) {
                    homeDetent = .large
                    proxy.scrollTo(Anchor.cities, anchor: .top)
                }
            } label: {
                Label("热门城市", systemImage: "building.2")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)

            Spacer(minLength: 0)
        }
    }

    private func rollRandomWork() {
        guard !isRandomCoolingDown, let work = store.randomWork() else { return }
        router.focusWork(id: work.id)
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
            VStack(alignment: .leading, spacing: 12) {
                Text("最近查看").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(recents) { bangumi in
                            Button { router.focusWork(id: bangumi.id) } label: {
                                VStack(spacing: 4) {
                                    CoverThumbnail(bangumi: bangumi).frame(width: 60, height: 80)
                                    Text(bangumi.displayName)
                                        .font(.caption)
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

struct CityGridSection: View {
    let cities: [CityTile]
    var onSelect: (CityTile) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        if !cities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("热门城市").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cities.prefix(11)) { city in
                        Button { onSelect(city) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(city.name).font(.body.weight(.semibold)).lineLimit(1)
                                Text("\(city.pointCount) 个点位")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .frame(minHeight: 56, alignment: .topLeading)
                            .background(Color(.tertiarySystemFill), in: ConcentricRectangle(corners: .concentric(minimum: 12)))
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
        VStack(alignment: .leading, spacing: 12) {
            Text("作品浏览").font(.headline)
            Picker("浏览分类", selection: $selectedTab) {
                ForEach(WorkBrowseTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let works = Array(store.works(for: selectedTab).prefix(18))
            VStack(spacing: 0) {
                ForEach(Array(works.enumerated()), id: \.element.id) { offset, bangumi in
                    Button { onSelectWork(bangumi.id) } label: {
                        BrowseWorkRow(store: store, bangumi: bangumi)
                    }
                    .buttonStyle(.plain)
                    if offset < works.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: ConcentricRectangle(corners: .concentric(minimum: 16)))
        }
    }
}

private struct BrowseWorkRow: View {
    let store: AnitabiStore
    let bangumi: BangumiLite

    var body: some View {
        HStack(spacing: 12) {
            CoverThumbnail(bangumi: bangumi).frame(width: 34, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(bangumi.displayName).font(.body).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private var subtitle: String {
        let count = store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
        let parts: [String?] = [bangumi.cat?.nilIfBlank, bangumi.city?.nilIfBlank, "\(count) 个点位"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 附近行

private struct NearbyPointRow: View {
    let store: AnitabiStore
    let item: NearbyPoint

    var body: some View {
        HStack(spacing: 12) {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(item.point.displayName.nilIfBlank ?? "巡礼点")
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ThemeDot(color: store.color(forBangumi: item.point.bangumiID))
                    Text(store.name(forBangumi: item.point.bangumiID)).lineLimit(1)
                    Text("·")
                    Text(DistanceFormatter.string(meters: item.distance))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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
        .padding(12)
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
