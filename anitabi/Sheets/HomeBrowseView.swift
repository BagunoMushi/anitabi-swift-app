//
//  HomeBrowseView.swift
//  anitabi
//
//  HomeSheet の「通常ブラウズ」中身。**三档は同じ 1 列を裁切する高さの違いでしかない**ので
//  档で出し分けはせず、全セクションを同じ ScrollView に並べる。
//  列の順（設計稿 1a / 2a）：最近查看 → 附近的巡礼点 → 作品浏览 → 热门城市 → 版権脚注。
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// 附近の再計算をいつ回すかのキー。位置と読み込み段階の**両方**を見る —— GPS の初回 fix は
/// データ取得の完走より先に届くことがあり、その瞬間の `points` はまだ空。
private struct NearbyRecomputeTrigger: Equatable {
    var timestamp: Date?
    var phase: DataLoadPhase
}

struct HomeBrowseView: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
    var onSelectPoint: (ScenePoint) -> Void
    var onFocusCity: (CityTile) -> Void

    @AppStorage("home.browseTab") private var browseTab: WorkBrowseTab = .recentlyUpdated
    @Environment(\.sheetBottomInset) private var sheetBottomInset

    /// 「附近」= 5km 圏内。`store.nearby` は 50km まで候補を持つので、ここで絞る。
    private var nearbyWithinRange: [NearbyPoint] {
        Array(store.nearby.filter { $0.distance <= 5_000 }.prefix(3))
    }

    /// 初回起動〜データ完走までの空窗だけ骨架屏を出す。`geometryOnly` も骨架のまま ——
    /// 座標だけの段階では作品名・点名が全部空文字で、実物の行を出すと白紙の行が並ぶ。
    private var isLoadingSkeleton: Bool {
        switch store.phase {
        case .empty, .geometryOnly: true
        case .complete, .failed: false
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                // 検索行と作品 chips 行は `HomeSheet` が ScrollView の外に固定で持っている。
                if isLoadingSkeleton {
                    HomeBrowseSkeleton()
                        .transition(.opacity)
                } else {
                    Group {
                        continueWatchingRow
                        nearbySection
                        workBrowseSection
                        CityGridSection(cities: store.cities, onSelect: onFocusCity)
                        footer
                    }
                    .transition(.opacity)
                }
            }
            .scenePadding(.horizontal)
            // 上の余白は検索行が持っているので、ここでは足さない。
            .sheetScrollBottomPadding(sheetBottomInset)
            .animation(.anitabiSpring, value: isLoadingSkeleton)
        }
        .task(id: NearbyRecomputeTrigger(timestamp: locationProvider.location?.timestamp, phase: store.phase)) {
            guard let location = locationProvider.location, !store.isEmpty else { return }
            // 読み込み完走直後の 1 回だけは、移動していなくても間引かずに撮り直す
            // （それより前の「点が空だった」計算結果を上書きするため）。
            let justFinishedLoading = store.phase == .complete
            guard justFinishedLoading || locationProvider.shouldRecomputeNearby(for: location) else { return }
            await store.recomputeNearby(around: location)
            locationProvider.markNearbyRecomputed(at: location)
        }
    }

    // MARK: 1. 最近查看（条件行・設計稿 1a）

    /// 設計稿の 1 行カード：封面 ＋「最近查看」＋ 作品名 ＋ 深緑の「继续」。
    /// 一度も作品を開いていない間はこの行ごと消える。
    @ViewBuilder
    private var continueWatchingRow: some View {
        if let bangumi = store.lastVisitedBangumi {
            Button { router.focusWork(id: bangumi.id) } label: {
                HStack(spacing: SheetMetrics.thumbnailGap) {
                    CoverThumbnail(bangumi: bangumi, size: SheetMetrics.recentCoverSize)
                    VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                        Text("最近查看")
                            .font(SheetFont.meta)
                            .foregroundStyle(Color.anitabiInkTertiary)
                        Text("\(bangumi.displayName) · \(pointCount(for: bangumi)) 个点位")
                            .font(SheetFont.rowTitle)
                            .foregroundStyle(Color.anitabiInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("继续")
                        .fixedSize(horizontal: true, vertical: false)
                        .font(SheetFont.chipSmall)
                        .foregroundStyle(Color.anitabiOnAccent)
                        .padding(.horizontal, SheetMetrics.scaled(12))
                        .padding(.vertical, SheetMetrics.scaled(6))
                        .background(Color.anitabiAccentFill, in: .capsule)
                }
                .padding(.horizontal, SheetMetrics.listCardHorizontalPadding)
                .padding(.vertical, SheetMetrics.scaled(8))
                .anitabiPanel(radius: SheetMetrics.groupCardRadius)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func pointCount(for bangumi: BangumiLite) -> Int {
        store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
    }

    // MARK: 2. 附近的巡礼点（設計稿 1a）

    @ViewBuilder
    private var nearbySection: some View {
        if !locationProvider.isAuthorized {
            locationGuidanceCard
        } else if !nearbyWithinRange.isEmpty {
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SheetSectionHeader(title: "附近的巡礼点") {
                    Text("5km 内")
                        .font(SheetFont.meta)
                        .foregroundStyle(Color.anitabiInkTertiary)
                }
                SheetListCard {
                    ForEach(Array(nearbyWithinRange.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            SheetHairline(leadingInset: NearbyPointRow.textInset)
                        }
                        Button { onSelectPoint(item.point) } label: {
                            NearbyPointRow(store: store, item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if let nearest = store.nearestBeyondNeighborhood {
            // 設計稿 1a の状態変体「50km 内无点位时显示」。
            HStack(spacing: SheetMetrics.thumbnailGap) {
                Text("最近的巡礼点在 \(nearest.point.displayName) · 约 \(DistanceFormatter.string(meters: nearest.distance))")
                    .font(SheetFont.rowTitleDense)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("带我去") { onSelectPoint(nearest.point) }
                    .fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(AnitabiCapsuleStyle(kind: .primary, size: .chip))
            }
            .padding(.horizontal, SheetMetrics.listCardHorizontalPadding)
            .padding(.vertical, SheetMetrics.scaled(10))
            .anitabiPanel(radius: SheetMetrics.groupCardRadius)
        }
        // 定位済み・50km 圏内も 0 件のときは何も出さない（巡礼データが存在しない地域）。
    }

    /// 設計稿 1a の状態変体「未授权定位时显示」：丸い定位記号 ＋ 文言 ＋ 深緑の「去开启」。
    private var locationGuidanceCard: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            Image(systemName: "location.slash")
                .font(SheetFont.rowTitle)
                .foregroundStyle(Color.anitabiInk)
                .frame(width: SheetMetrics.guidanceIconDiameter, height: SheetMetrics.guidanceIconDiameter)
                .background(Color.anitabiRaised, in: .circle)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                Text("开启定位，看看身边的巡礼点")
                    .font(SheetFont.rowTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("去开启", action: requestLocationOrOpenSettings)
                .buttonStyle(AnitabiCapsuleStyle(kind: .primary, size: .chip))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, SheetMetrics.listCardHorizontalPadding)
        .padding(.vertical, SheetMetrics.scaled(10))
        .anitabiPanel(radius: SheetMetrics.groupCardRadius)
    }

    private func requestLocationOrOpenSettings() {
        if locationProvider.isDenied {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } else {
            locationProvider.requestAuthorization()
        }
    }

    // MARK: 3. 作品浏览（設計稿 1a）

    private var workBrowseSection: some View {
        WorkBrowseSection(store: store, selectedTab: $browseTab) { id in
            router.focusWork(id: id)
        }
    }

    // MARK: 4. 版権脚注

    private var footer: some View {
        Text("数据由 anitabi.cn 社区贡献 · CC BY-NC-SA 4.0")
            .font(SheetFont.meta)
            .foregroundStyle(Color.anitabiInkFaint)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, SheetMetrics.scaled(6))
    }
}

// MARK: - 热门城市（検索の空入力時にも使い回す）

/// 設計稿 1a：3 列のタイルに都市名と点数。剧照は敷かない（硬約束）——地は白い薄膜だけ。
/// 設計稿の「🎲 随机作品」は見出しには置かず、地図左下の浮控にした（`MapRandomWorkButton`）。
struct CityGridSection: View {
    let cities: [CityTile]
    var onSelect: (CityTile) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: SheetMetrics.itemSpacing), count: 3)

    var body: some View {
        if !cities.isEmpty {
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SheetSectionHeader("热门城市")
                LazyVGrid(columns: columns, alignment: .leading, spacing: SheetMetrics.itemSpacing) {
                    ForEach(cities.prefix(12)) { city in
                        Button { onSelect(city) } label: {
                            VStack(alignment: .leading, spacing: SheetMetrics.scaled(1)) {
                                Text(city.name)
                                    .font(SheetFont.rowTitle)
                                    .foregroundStyle(Color.anitabiInk)
                                    .lineLimit(1)
                                Text("\(city.pointCount) 点位")
                                    .font(SheetFont.meta)
                                    .foregroundStyle(Color.anitabiInkTertiary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, SheetMetrics.scaled(12))
                            .padding(.vertical, SheetMetrics.scaled(10))
                            .anitabiPanel(radius: SheetMetrics.tileRadius)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - 作品浏览（検索の空入力時にも使い回す）

struct WorkBrowseSection: View {
    let store: AnitabiStore
    @Binding var selectedTab: WorkBrowseTab
    var onSelectWork: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
            SheetSectionHeader("作品浏览")
            AnitabiSegmentedPicker(
                selection: $selectedTab,
                options: WorkBrowseTab.allCases.map { AnitabiSegment($0, $0.title) }
            )
            let works = Array(store.works(for: selectedTab).prefix(18))
            SheetListCard {
                ForEach(Array(works.enumerated()), id: \.element.id) { offset, bangumi in
                    if offset > 0 {
                        SheetHairline(leadingInset: SheetMetrics.coverSize.width + SheetMetrics.thumbnailGap)
                    }
                    Button { onSelectWork(bangumi.id) } label: {
                        WorkBrowseRow(store: store, bangumi: bangumi)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 作品行（作品浏览・検索結果の両方が使う）。設計稿は `38×52` 封面 ＋ 作品名 ＋ 副題 ＋ `›`。
struct WorkBrowseRow: View {
    let store: AnitabiStore
    let bangumi: BangumiLite
    var coverSize: CGSize = SheetMetrics.coverSize

    /// `{分類} · {地域} · {N 个点位}`。
    static func subtitle(_ bangumi: BangumiLite, store: AnitabiStore) -> String {
        let count = store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
        let parts: [String?] = [bangumi.cat?.nilIfBlank, bangumi.city?.nilIfBlank, String(localized: "\(count) 个点位")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            CoverThumbnail(bangumi: bangumi, size: coverSize)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                Text(bangumi.displayName)
                    .font(SheetFont.rowTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(2)
                Text(Self.subtitle(bangumi, store: store))
                    .font(SheetFont.meta)
                    .foregroundStyle(Color.anitabiInkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            RowChevron()
        }
        .padding(.vertical, SheetMetrics.rowVerticalPadding)
        .contentShape(.rect)
    }
}

// MARK: - 地標行（附近・落針の「最近的巡礼点」・検索結果が共有）

/// 設計稿 1a：`54×40` の剧照 ＋ 点名 ＋ 主題色点と作品名 ＋ 右端に距離（未測位なら省く）。
struct NearbyPointRow: View {
    let store: AnitabiStore
    let point: ScenePoint
    var distance: CLLocationDistance?

    init(store: AnitabiStore, point: ScenePoint, distance: CLLocationDistance? = nil) {
        self.store = store
        self.point = point
        self.distance = distance
    }

    init(store: AnitabiStore, item: NearbyPoint) {
        self.init(store: store, point: item.point, distance: item.distance)
    }

    /// 分隔線を文字列まで寄せる量。
    static var textInset: CGFloat { SheetMetrics.sceneThumbnailSize.width + SheetMetrics.thumbnailGap }

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            SceneThumbnail(url: point.thumbnailURL)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                Text(point.displayName.nilIfBlank ?? String(localized: "巡礼点"))
                    .font(SheetFont.rowTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(1)
                HStack(spacing: SheetMetrics.scaled(5)) {
                    ThemeDot(color: store.color(forBangumi: point.bangumiID), size: SheetMetrics.dotSize)
                    Text(store.name(forBangumi: point.bangumiID))
                        .lineLimit(1)
                }
                .font(SheetFont.meta)
                .foregroundStyle(Color.anitabiInkSecondary)
            }
            Spacer(minLength: 0)
            if let distance {
                Text(DistanceFormatter.string(meters: distance))
                    .font(SheetFont.distance)
                    .foregroundStyle(Color.anitabiInkSecondary)
            }
        }
        .padding(.vertical, SheetMetrics.rowVerticalPadding)
        .contentShape(.rect)
    }
}
