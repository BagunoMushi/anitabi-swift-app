//
//  SearchResultsView.swift
//  anitabi
//
//  HomeSheet の「検索アクティブ」中身。設計稿 1b のとおり、結果は**種類ごとの節**
//  （城市 / 作品 / 地标）に分けて別々の一覧カードへ入れる（1 本の混排リストにはしない）。
//  空入力時は熱門城市＋作品ブラウズを転用（検索欄タップ直後＝まだ何も打っていない状態）。
//

import CoreLocation
import SwiftUI

struct SearchResultsView: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
    /// キー入力ごとの生値。防抖は本 View 内で完結させる。
    var query: String
    var onSelectPoint: (ScenePoint) -> Void
    var onFocusCity: (CityTile) -> Void
    /// tap 後に検索状態を畳む（テキストクリア＋フォーカス解除）。HomeSheet 側の関数を渡してもらう。
    var onFinishSelection: () -> Void

    /// 空入力時の「作品浏览」は Home 側と同じ AppStorage キーを共有するので、
    /// タブ選択は行き来しても保持される。
    @AppStorage("home.browseTab") private var browseTab: WorkBrowseTab = .recentlyUpdated
    /// sheet の中身は底部安全区を無効にしてあるので、列の末尾だけ自分で足し戻す。
    @Environment(\.sheetBottomInset) private var sheetBottomInset

    @State private var debouncedQuery = ""

    private var trimmedQuery: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                if trimmedQuery.isEmpty {
                    CityGridSection(cities: store.cities) { city in
                        onFocusCity(city)
                        onFinishSelection()
                    }
                    WorkBrowseSection(store: store, selectedTab: $browseTab) { id in
                        router.focusWork(id: id)
                        onFinishSelection()
                    }
                } else {
                    resultsContent
                }
            }
            .scenePadding(.horizontal)
            // 上の余白は検索行が持っているので、ここでは足さない。
            .padding(.bottom, SheetMetrics.scrollBottomPadding + sheetBottomInset)
        }
        .task(id: query) {
            // 150ms 防抖 —— キー入力のたびに全件走査を回さない。
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
    }

    // MARK: - 結果

    /// `store.search` は全件走査なので**1 回だけ**呼んで種類ごとに振り分ける
    /// （節ごとに呼ぶと同じ走査を 2 度回すことになる）。
    private var results: (
        cities: [CityTile],
        works: [BangumiLite],
        points: [(point: ScenePoint, distance: CLLocationDistance?)]
    ) {
        var works: [BangumiLite] = []
        var points: [(point: ScenePoint, distance: CLLocationDistance?)] = []
        for result in store.search(trimmedQuery, near: locationProvider.location) {
            switch result {
            case .bangumi(let bangumi): works.append(bangumi)
            case .point(let point, let distance): points.append((point: point, distance: distance))
            }
        }
        return (store.matchingCities(trimmedQuery), works, points)
    }

    @ViewBuilder
    private var resultsContent: some View {
        let (cities, works, points) = results

        if cities.isEmpty, works.isEmpty, points.isEmpty {
            emptyState
        } else {
            if !cities.isEmpty {
                resultSection("城市") {
                    ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                        if index > 0 {
                            SheetHairline(leadingInset: SheetMetrics.guidanceIconDiameter + SheetMetrics.thumbnailGap)
                        }
                        cityRow(city)
                    }
                }
            }
            if !works.isEmpty {
                resultSection("作品") {
                    ForEach(Array(works.enumerated()), id: \.element.id) { index, bangumi in
                        if index > 0 {
                            SheetHairline(leadingInset: SheetMetrics.searchCoverSize.width + SheetMetrics.thumbnailGap)
                        }
                        workRow(bangumi)
                    }
                }
            }
            if !points.isEmpty {
                resultSection("地标") {
                    ForEach(Array(points.enumerated()), id: \.element.point.id) { index, entry in
                        if index > 0 {
                            SheetHairline(leadingInset: NearbyPointRow.textInset)
                        }
                        pointRow(entry.point, distance: entry.distance)
                    }
                }
            }
        }
    }

    /// 設計稿 1b の節見出し：`11px / weight 900 / rgba(19,46,26,.5)` —— 首页の節見出し（13px 墨）より
    /// 一段弱い「仕分けラベル」。その下に自前の一覧カード（角丸 16）を置く。
    private func resultSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
            Text(title)
                .font(SheetFont.resultsLabel)
                .foregroundStyle(Color.anitabiInkTertiary)
                .padding(.horizontal, SheetMetrics.headerInset)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, SheetMetrics.listCardHorizontalPadding)
            .padding(.vertical, SheetMetrics.listCardVerticalPadding)
            .anitabiPanel(radius: SheetMetrics.groupCardRadius)
        }
    }

    // MARK: 行

    private func cityRow(_ city: CityTile) -> some View {
        Button {
            onFocusCity(city)
            onFinishSelection()
        } label: {
            HStack(spacing: SheetMetrics.thumbnailGap) {
                Image(systemName: "building.2")
                    .font(SheetFont.rowTitle)
                    .foregroundStyle(Color.anitabiInkSecondary)
                    .frame(width: SheetMetrics.guidanceIconDiameter, height: SheetMetrics.guidanceIconDiameter)
                    .background(Color.anitabiSoftFill, in: .rect(cornerRadius: SheetMetrics.smallRadius, style: .continuous))
                VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                    Text(city.name)
                        .font(SheetFont.rowTitle)
                        .foregroundStyle(Color.anitabiInk)
                    Text("\(city.pointCount) 个点位")
                        .font(SheetFont.meta)
                        .foregroundStyle(Color.anitabiInkSecondary)
                }
                Spacer(minLength: 0)
                RowChevron()
            }
            .padding(.vertical, SheetMetrics.rowVerticalPadding)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func workRow(_ bangumi: BangumiLite) -> some View {
        Button {
            router.focusWork(id: bangumi.id)
            onFinishSelection()
        } label: {
            HStack(spacing: SheetMetrics.thumbnailGap) {
                CoverThumbnail(bangumi: bangumi, size: SheetMetrics.searchCoverSize)
                VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                    Text(bangumi.displayName)
                        .font(SheetFont.rowTitle)
                        .foregroundStyle(Color.anitabiInk)
                        .lineLimit(2)
                    Text(workSubtitle(bangumi))
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
        .buttonStyle(.plain)
    }

    private func pointRow(_ point: ScenePoint, distance: CLLocationDistance?) -> some View {
        Button {
            onSelectPoint(point)
            onFinishSelection()
        } label: {
            HStack(spacing: SheetMetrics.thumbnailGap) {
                SceneThumbnail(url: point.thumbnailURL)
                VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                    Text(point.displayName.nilIfBlank ?? String(localized: "巡礼点"))
                        .font(SheetFont.rowTitle)
                        .foregroundStyle(Color.anitabiInk)
                        .lineLimit(1)
                    HStack(spacing: SheetMetrics.scaled(5)) {
                        ThemeDot(color: store.color(forBangumi: point.bangumiID), size: SheetMetrics.dotSize)
                        Text(store.name(forBangumi: point.bangumiID)).lineLimit(1)
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
        .buttonStyle(.plain)
    }

    private func workSubtitle(_ bangumi: BangumiLite) -> String {
        let count = store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
        let parts: [String?] = [bangumi.cat?.nilIfBlank, bangumi.city?.nilIfBlank, String(localized: "\(count) 个点位")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: 空状態（設計稿 1b の状態変体）

    private var emptyState: some View {
        VStack(spacing: SheetMetrics.scaled(4)) {
            Image(systemName: "magnifyingglass")
                .font(SheetFont.titleLarge)
                .foregroundStyle(Color.anitabiInk)
                .frame(width: SheetMetrics.emptyStateIconDiameter, height: SheetMetrics.emptyStateIconDiameter)
                .background(Color.anitabiRaised, in: .circle)
                .padding(.bottom, SheetMetrics.scaled(6))
            Text("没有找到「\(trimmedQuery)」")
                .font(SheetFont.rowTitle)
                .foregroundStyle(Color.anitabiInk)
            Text("换个关键词试试，或浏览热门城市")
                .font(SheetFont.meta)
                .foregroundStyle(Color.anitabiInkSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SheetMetrics.scaled(24))
        .anitabiPanel(radius: SheetMetrics.tileRadius)
        .padding(.top, SheetMetrics.scaled(8))
    }
}
