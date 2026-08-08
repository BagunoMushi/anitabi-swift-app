//
//  HomeSheetView.swift
//  anitabi
//
//  首屏の底部 sheet。三档（12% 收起 / 42% 半开 / 92% 全开）は 1 本のスクロールで、
//  「どこまで見えるか」を档位が決める —— 半开で上下文卡＋附近 2 行＋快捷入口までが
//  ちょうど収まり、全开で探索ページ全体が出る。
//

import CoreLocation
import OSLog
import SwiftUI

private let sheetLog = Logger(subsystem: "cn.anitabi.app", category: "sheet")

struct HomeSheetView: View {
    @Bindable var store: AnitabiStore
    let location: CLLocation?
    let isLocationDenied: Bool
    let isLocationUndetermined: Bool

    @Binding var detent: PresentationDetent
    @Binding var searchText: String

    let onSelectPoint: (ScenePoint) -> Void
    let onSelectBangumi: (BangumiLite) -> Void
    let onSelectCity: (CityTile) -> Void
    let onRequestLocation: () -> Void
    let onRandomJump: () -> Void

    @State private var workTab: WorkBrowseTab = .recentlyUpdated

    /// フォーカスは sheet 側で持つ。`.sheet` は別のプレゼンテーション階層なので、
    /// 呼び出し元の `@FocusState` に状態が返ってこない（フォーカスは当たるが読み出せない）。
    @FocusState private var isFieldFocused: Bool

    private var isSearching: Bool {
        isFieldFocused || !searchText.isEmpty
    }

    private var isExpanded: Bool {
        detent == SheetDetent.expanded.fraction
    }

    var body: some View {
        Group {
            if isSearching {
                searchResults
            } else {
                browseContent
            }
        }
        // 搜索場は常に最前面に固定。スクロールした中身が下を通り抜けるので、
        // 境目は iOS 26 の scroll edge effect（ぼかしフェード）で処理する。
        .safeAreaInset(edge: .top, spacing: 0) {
            searchBar
                .padding(.horizontal, Metrics.sheetHPadding)
                .padding(.top, Metrics.searchFieldTopInset)
                .padding(.bottom, 8)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: isSearching)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: isExpanded)
        #if DEBUG
        // 档位の高さを目測で詰めるのは当てにならない（ガラスのぼかしが縁を曖昧にする）。
        // 実測値はここから読む: log show --info --predicate 'category == "sheet"'
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            sheetLog.info("sheet height = \(height, format: .fixed(precision: 1)) pt")
        }
        #endif
    }

    // MARK: - 検索場

    private var searchBar: some View {
        GlassEffectContainer(spacing: 10) {
            searchBarContent
        }
        .onChange(of: isFieldFocused) { _, focused in
            // 設計稿どおり、搜索場をタップしたら sheet は全开まで持ち上がる。
            if focused { detent = SheetDetent.expanded.fraction }
        }
        .onChange(of: detent) { _, new in
            // 地図に触れて収起档まで落ちたら検索も畳む（Apple マップと同じ挙動）。
            if new == SheetDetent.collapsed.fraction { isFieldFocused = false }
        }
    }

    private var searchBarContent: some View {
        HStack(spacing: isSearching ? 12 : 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSearching ? Palette.sectionHeader : Palette.secondary)

                TextField("搜索作品、地点或城市", text: $searchText)
                    .font(.homeSearch)
                    .foregroundStyle(Palette.title)
                    .tint(Palette.brand)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFieldFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.quaternary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .frame(height: Metrics.searchFieldHeight)
            // ガラスの sheet の中なので、ここは塗り。ガラスの上にガラスは重ねられない。
            // 激活態はカーソル（tint）と「取消」で分かるので、自前の輪郭線も足さない。
            .background(Palette.searchField, in: .capsule)

            if isSearching {
                Button("取消") {
                    searchText = ""
                    isFieldFocused = false
                    detent = SheetDetent.half.fraction
                }
                .font(.rounded(15, .bold))
                .foregroundStyle(Palette.brand)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                AccountButton()
            }
        }
    }

    // MARK: - 検索結果
    //
    // 全量データがローカルにあるので同期で引ける＝ローディングもスケルトンも出さない。

    private var searchResults: some View {
        let results = store.search(searchText, near: location)

        return ScrollView {
            LazyVStack(spacing: 0) {
                if results.isEmpty, !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 24)
                } else {
                    HomeCard {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                searchRow(result)
                                if index < results.count - 1 {
                                    RowSeparator(leading: Metrics.compactThumb.width + Metrics.rowInset + 12)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.sheetHPadding)
                    .padding(.top, 12)

                    Text("本地全量数据 · 即输即出")
                        .font(.rounded(11, .semibold))
                        .foregroundStyle(Palette.quaternary)
                        .padding(.vertical, 12)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func searchRow(_ result: SearchResult) -> some View {
        switch result {
        case .bangumi(let bangumi):
            Button {
                onSelectBangumi(bangumi)
            } label: {
                HStack(spacing: 12) {
                    BangumiCover(bangumi: bangumi, size: CGSize(width: 36, height: 48))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(bangumi.displayName)
                            .font(.homeRowTitle)
                            .foregroundStyle(Palette.title)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(bangumi.themeColor).frame(width: 8, height: 8)
                            Text("\(bangumi.points.count) 个点位")
                                .font(.rounded(11.5, .medium))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("作品")
                        .font(.rounded(10.5, .heavy))
                        .foregroundStyle(Palette.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Palette.brand.opacity(0.1), in: .rect(cornerRadius: 6))
                }
                .padding(Metrics.rowInset)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

        case .point(let point, let distance):
            Button {
                onSelectPoint(point)
            } label: {
                NearbyRow(
                    item: NearbyPoint(point: point, distance: distance ?? 0),
                    color: store.color(forBangumi: point.bangumiID),
                    workName: store.name(forBangumi: point.bangumiID),
                    showsTrailingDistance: distance != nil,
                    thumbSize: Metrics.compactThumb
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 通常のブラウズ

    private var isCollapsed: Bool {
        detent == SheetDetent.collapsed.fraction
    }

    private var browseContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {

                // 上下文卡：直近に見た作品（無ければ出さない）
                if let last = store.lastVisitedBangumi, !isExpanded {
                    HomeCard {
                        ContinueCard(bangumi: last) { onSelectBangumi(last) }
                    }
                }

                nearbySection

                if !isExpanded {
                    QuickActionsRow(actions: quickActions)
                        .padding(.top, -2)
                }

                if isExpanded {
                    citiesSection
                    worksSection
                    footer
                }
            }
            .padding(.horizontal, Metrics.sheetHPadding)
            .padding(.top, 4)
            .padding(.bottom, 24)
            // 収起档は搜索场だけを見せる（Apple マップと同じ）。
            // 出しっぱなしにすると行が途中で切れて見える。
            .opacity(isCollapsed ? 0 : 1)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDisabled(isCollapsed)
    }

    // MARK: 附近

    @ViewBuilder
    private var nearbySection: some View {
        if isLocationDenied || isLocationUndetermined {
            HomeCard {
                LocationPromptCard(isDenied: isLocationDenied, action: onRequestLocation)
            }
            if isExpanded { citiesHeader }
        } else if store.nearby.isEmpty {
            if store.isEmpty {
                loadingHint
            } else {
                // 位置は取れているが判定待ち
                EmptyView()
            }
        } else if let nearest = store.nearby.first, nearest.distance > 5_000 {
            // 「附近」と呼べる距離に何も無い
            HomeCard {
                NoNearbyCard(
                    nearest: nearest,
                    placeName: store.name(forBangumi: nearest.point.bangumiID),
                    action: { onSelectPoint(nearest.point) }
                )
            }
        } else {
            SectionHeader(title: "附近的巡礼点")
            HomeCard {
                VStack(spacing: 0) {
                    let thumbWidth = (isExpanded ? Metrics.compactThumb : Metrics.nearbyThumb).width
                    let items = Array(store.nearby.prefix(isExpanded ? 12 : 2))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onSelectPoint(item.point)
                        } label: {
                            NearbyRow(
                                item: item,
                                color: store.color(forBangumi: item.point.bangumiID),
                                workName: store.name(forBangumi: item.point.bangumiID),
                                showsTrailingDistance: isExpanded,
                                thumbSize: isExpanded ? Metrics.compactThumb : Metrics.nearbyThumb
                            )
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            RowSeparator(leading: thumbWidth + Metrics.rowInset + 12)
                        }
                    }
                }
            }
        }
    }

    private var loadingHint: some View {
        HomeCard {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在载入巡礼数据…")
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    // MARK: 熱門都市

    private var citiesHeader: some View {
        SectionHeader(title: "热门城市")
    }

    @ViewBuilder
    private var citiesSection: some View {
        if !store.cities.isEmpty {
            citiesHeader
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(store.cities.prefix(8).enumerated()), id: \.element.id) { index, city in
                    CityTileView(city: city, index: index) { onSelectCity(city) }
                }
            }
        }
    }

    // MARK: 作品ブラウズ

    @ViewBuilder
    private var worksSection: some View {
        let works = store.works(for: workTab)
        if !works.isEmpty {
            HStack {
                Text("作品浏览")
                    .font(.homeSection)
                    .foregroundStyle(Palette.sectionHeader)
                Spacer()
                Picker("作品浏览", selection: $workTab) {
                    ForEach(WorkBrowseTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 4)

            HomeCard {
                VStack(spacing: 0) {
                    let items = Array(works.prefix(10))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, bangumi in
                        WorkRow(bangumi: bangumi) { onSelectBangumi(bangumi) }
                        if index < items.count - 1 {
                            RowSeparator(leading: Metrics.coverSize.width + Metrics.rowInset + 12)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text("数据由 anitabi.cn 社区贡献 · CC BY-NC-SA 4.0")
            .font(.rounded(10.5, .medium))
            .foregroundStyle(Palette.quaternary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: 快捷入口

    private var quickActions: [QuickAction] {
        [
            QuickAction(id: "cities", systemImage: "building.2", title: "热门城市") {
                detent = SheetDetent.expanded.fraction
            },
            QuickAction(id: "random", systemImage: "shuffle", title: "随机跳转", action: onRandomJump),
            QuickAction(id: "favorites", systemImage: "star", title: "我的收藏") {
                detent = SheetDetent.expanded.fraction
            },
        ]
    }
}

// MARK: - アカウント

/// 未ログインは既定のシルエット。ログイン導線は後続 brief。
struct AccountButton: View {
    var body: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 17))
            .foregroundStyle(Palette.quaternary)
            .frame(width: Metrics.searchFieldHeight, height: Metrics.searchFieldHeight)
            .background(Palette.searchField, in: .circle)
    }
}
