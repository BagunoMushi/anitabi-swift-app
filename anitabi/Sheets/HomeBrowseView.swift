//
//  HomeBrowseView.swift
//  anitabi
//
//  HomeSheet の「通常ブラウズ」中身。設計稿 2a の原則そのまま —— **三档は同じ 1 列を
//  裁切する高さの違いでしかない**（拖动は「多露」だけで内容を入れ替えない）。なので档で
//  出し分けはせず、全セクションを同じ ScrollView に並べる。
//
//  列の順（設計稿 1a / 2a）：
//    作品筛选 chips → 最近查看（条件行）→ 附近的巡礼点 → 作品浏览 → 热门城市 → 版権脚注
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
    var onSelectPoint: (ScenePoint) -> Void
    var onFocusCity: (CityTile) -> Void

    @AppStorage("home.browseTab") private var browseTab: WorkBrowseTab = .recentlyUpdated
    /// sheet の中身は底部安全区を無効にしてあるので、列の末尾だけ自分で足し戻す。
    @Environment(\.sheetBottomInset) private var sheetBottomInset

    /// 「附近」= 5km 圏内。`store.nearby` は 50km まで候補を持つので、ここで絞る。
    private var nearbyWithinRange: [NearbyPoint] {
        Array(store.nearby.filter { $0.distance <= 5_000 }.prefix(3))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                // 検索行と作品 chips 行は `HomeSheet` が ScrollView の外に固定で持っている
                // （設計稿 2a 一段式＝その 2 行ぶんの高さ）。ここは列の 3 行目から始まる。
                continueWatchingRow
                nearbySection
                workBrowseSection
                CityGridSection(cities: store.cities, onSelect: onFocusCity)
                footer
            }
            .scenePadding(.horizontal)
            // 上の余白は検索行が持っているので、ここでは足さない。
            .padding(.bottom, SheetMetrics.scrollBottomPadding + sheetBottomInset)
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

    // MARK: 1. 最近查看（条件行・設計稿 1a）

    /// 設計稿の 1 行カード：`30×40` 封面 ＋ 小見出し「最近查看」＋ 作品名 ＋ 深緑の「继续」。
    /// 一度も作品を開いていない間はこの行ごと消える（設計稿 2a の首次使用変体）。
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

    /// 設計稿 1a の状態変体「未授权定位时显示」：34pt の丸い定位記号 ＋ 2 行 ＋ 深緑の「去开启」。
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

/// 設計稿 1a：3 列のタイル（角丸 14・`padding:10px 12px`）に都市名 14/700 と点数 11。
/// 剧照は敷かない（硬約束）——地は白い薄膜だけ。
///
/// 見出しの右端には何も置かない —— 設計稿 1a の「🎲 随机作品」は地図の左下（Apple 署名の上）へ
/// 独立した浮控として出した（`MapRandomWorkButton`）。
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
            CoverThumbnail(bangumi: bangumi)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                Text(bangumi.displayName)
                    .font(SheetFont.rowTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(2)
                Text(subtitle)
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

    private var subtitle: String {
        let count = store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
        let parts: [String?] = [bangumi.cat?.nilIfBlank, bangumi.city?.nilIfBlank, String(localized: "\(count) 个点位")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - 附近行（落針カードの「最近的巡礼点」とも共有）

/// 設計稿 1a：`54×40` の剧照 ＋ 点名 14/700 ＋ 主題色点と作品名 11.5 ＋ 右端に距離 12/700。
struct NearbyPointRow: View {
    let store: AnitabiStore
    let item: NearbyPoint

    /// 分隔線を文字列まで寄せる量。
    static var textInset: CGFloat { SheetMetrics.sceneThumbnailSize.width + SheetMetrics.thumbnailGap }

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            SceneThumbnail(url: item.point.thumbnailURL)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                Text(item.point.displayName.nilIfBlank ?? String(localized: "巡礼点"))
                    .font(SheetFont.rowTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(1)
                HStack(spacing: SheetMetrics.scaled(5)) {
                    ThemeDot(color: store.color(forBangumi: item.point.bangumiID), size: SheetMetrics.dotSize)
                    Text(store.name(forBangumi: item.point.bangumiID))
                        .lineLimit(1)
                }
                .font(SheetFont.meta)
                .foregroundStyle(Color.anitabiInkSecondary)
            }
            Spacer(minLength: 0)
            Text(DistanceFormatter.string(meters: item.distance))
                .font(SheetFont.distance)
                .foregroundStyle(Color.anitabiInkSecondary)
        }
        .padding(.vertical, SheetMetrics.rowVerticalPadding)
        .contentShape(.rect)
    }
}
