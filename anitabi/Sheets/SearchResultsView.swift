//
//  SearchResultsView.swift
//  anitabi
//
//  HomeSheet の「検索アクティブ」中身。空入力時は熱門城市＋作品ブラウズを転用（Apple マップの
//  検索欄タップ直後＝最近の検索/よく行く場所と同じ立ち位置）。非空はローカル全文検索の結果。
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
    @State private var debouncedQuery = ""

    private var trimmedQuery: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .task(id: query) {
            // 150ms 防抖 —— キー入力のたびに全件走査を回さない。
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            debouncedQuery = query
        }
    }

    /// 都市（`store.matchingCities`）＋作品／地標（`store.search`）を 1 本の行リストにまとめる。
    /// `SearchResult` 本体に都市 case を足さないのは、それだと（削除待ちの）`HomeSheetView` 側の
    /// 網羅 switch を壊してしまうため（`AnitabiStore.matchingCities` のコメント参照）。
    private enum HomeSearchRow: Identifiable {
        case city(CityTile)
        case bangumi(BangumiLite)
        case point(ScenePoint, distance: CLLocationDistance?)

        var id: String {
            switch self {
            case .city(let c): "c\(c.id)"
            case .bangumi(let b): "b\(b.id)"
            case .point(let p, _): "p\(p.id)"
            }
        }
    }

    private var combinedResults: [HomeSearchRow] {
        let cityRows = store.matchingCities(trimmedQuery).map { HomeSearchRow.city($0) }
        let restRows = store.search(trimmedQuery, near: locationProvider.location).map { result -> HomeSearchRow in
            switch result {
            case .bangumi(let bangumi): .bangumi(bangumi)
            case .point(let point, let distance): .point(point, distance: distance)
            }
        }
        return cityRows + restRows
    }

    @ViewBuilder
    private var resultsContent: some View {
        let results = combinedResults
        if results.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { offset, result in
                    resultRow(result)
                    if offset < results.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: ConcentricRectangle(corners: .concentric(minimum: 16)))
        }
    }

    @ViewBuilder
    private func resultRow(_ result: HomeSearchRow) -> some View {
        switch result {
        case .city(let city):
            Button {
                onFocusCity(city)
                onFinishSelection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name).font(.body)
                        Text("城市").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

        case .bangumi(let bangumi):
            Button {
                router.focusWork(id: bangumi.id)
                onFinishSelection()
            } label: {
                HStack(spacing: 12) {
                    CoverThumbnail(bangumi: bangumi).frame(width: 34, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bangumi.displayName).font(.body).lineLimit(2)
                        Text(workSubtitle(bangumi)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

        case .point(let point, let distance):
            Button {
                onSelectPoint(point)
                onFinishSelection()
            } label: {
                HStack(spacing: 12) {
                    ThumbnailView(url: point.thumbnailURL).frame(width: 64, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.displayName.nilIfBlank ?? "巡礼点").font(.body).lineLimit(1)
                        HStack(spacing: 4) {
                            ThemeDot(color: store.color(forBangumi: point.bangumiID))
                            Text(store.name(forBangumi: point.bangumiID)).lineLimit(1)
                            if let distance {
                                Text("·")
                                Text(DistanceFormatter.string(meters: distance))
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func workSubtitle(_ bangumi: BangumiLite) -> String {
        let count = store.pointsByBangumi[bangumi.id]?.count ?? bangumi.points.count
        let parts: [String?] = ["\(count) 个点位", bangumi.city?.nilIfBlank]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
