//
//  HomeSheet.swift
//  anitabi
//
//  常駐する根 sheet（Browse）。検索行を ScrollView の**上**に固定で置き、中身は
//  「通常のブラウズ」と「検索アクティブ」を切り替えるだけの薄い器
//  （実装は HomeBrowseView / SearchResultsView）。
//

import SwiftUI

struct HomeSheet: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
    /// 視口作品 chips が読む最新のカメラ状態。`RootView.onCameraIdle` からそのまま渡ってくる。
    let cameraState: MapCameraState?
    /// RootView が持つ Home 档の実体。検索フォーカスから直接動かすので Binding で受け取る。
    @Binding var homeDetent: PresentationDetent
    /// いま何段目か。一段式では検索行より下を描かない。
    var stage: SheetStage = .medium
    /// 検索に入ったとき持ち上げる先／終えたとき戻る先。RootView が画面高から作って渡す。
    var expandedDetent: PresentationDetent = .large
    var initialDetent: PresentationDetent = .medium

    /// 一覧から地標を選んだ経路（RootView 側が镜头を寄せる）。
    var onSelectPoint: (ScenePoint) -> Void
    /// 都市タイル／検索の都市行から镜头を都市へ寄せる。第 2 引数は「sheet を半开へ落とすか」——
    /// ブラウズからは true（地図を見せる）、検索からは false（検索態のまま一覧を読ませる）。
    var onFocusCity: (CityTile, _ collapsesSheet: Bool) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    /// 検索モードに入っているか。フォーカスと同一にはしない —— 結果を読みながらキーボードだけ
    /// 下げた瞬間に検索画面ごと消えてしまう。抜けるのは `endSearch()` だけ。
    @State private var isSearchActive = false

    /// 外链の呈现は router を介さずカード自身が持つ（他カードの呈现スタックへ影響させない）。
    @State private var safariItem: SafariItem?
    @State private var isShowingAbout = false

    /// 視口内作品 chips の集計結果。集計タスクは**レイジーコンテナの外**に置く ——
    /// 中身が空（＝高さ 0）の間、`LazyVStack` 内の `.task` は発火しない（実測）。
    @State private var viewportWorkChips: [(id: Int, count: Int)] = []
    private static let viewportChipsDebounce = Duration.milliseconds(300)

    var body: some View {
        // 検索行は `safeAreaInset(edge: .top)` では**なく** ScrollView の外に積む。
        // safeAreaInset だと中身が行の下をくぐって流れ、この行には地が無いので文字が透けて重なる
        // （sheet の地はガラスなので、行に不透明背景を敷く逃げも使えない）。
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                searchRow
                // 一段式では chips を出さない —— iOS 26 の迷你条に収まるのは検索行だけで、
                // chips まで入れると中身が画面外へ切れる（`SheetLayout.minHeight` 参照）。
                if !isSearchActive && stage != .compact {
                    ViewportWorkChips(
                        store: store,
                        router: router,
                        candidates: viewportWorkChips,
                        suggestions: suggestedWorkIDs
                    )
                    .scenePadding(.horizontal)
                    // 出入りは淡入淡出だけ。既定の透明度过渡でも、下の `animatesSheetStage` /
                    // 検索の anitabiSpring に乗って迷你条への収起と同じ呼吸で消える。
                    .transition(.opacity)
                }
            }
            // 一段式の実高は**検索行だけ**で測る。生の行を測ると chips の出入りで最小档が動き、
            // 収起が二段落ちになる。
            .overlay(alignment: .top) { searchRow.compactHeightProbe(.home) }
            // chips 行 → 列の間隔（設計稿 2a の `margin-top:10px`）。
            .padding(.bottom, SheetMetrics.sectionSpacing)

            Group {
                if isSearchActive {
                    SearchResultsView(
                        store: store,
                        router: router,
                        locationProvider: locationProvider,
                        query: searchText,
                        onSelectPoint: onSelectPoint,
                        onPickCity: pickCity,
                        onFinishSelection: endSearch
                    )
                    // ブラウズ ↔ 検索は**淡入淡出だけ**にする —— どちらも画面の大半を占める
                    // 一覧なので、blurReplace を掛けると全行のスナップショットに霞を掛ける
                    // ぶんだけ入りの 1 フレームが重い。
                    .transition(.opacity)
                } else {
                    HomeBrowseView(
                        store: store,
                        router: router,
                        locationProvider: locationProvider,
                        onSelectPoint: onSelectPoint,
                        onFocusCity: { onFocusCity($0, true) }
                    )
                    .transition(.opacity)
                }
            }
            .collapsedInCompactStage(stage)
        }
        // 档の翻りと検索の出入りは同じバネに乗せる（`stage` は生の高さから毎フレーム派生する
        // 離散値なので、これが無いと chips・一覧の畳みが翻った 1 フレームで跳ぶ）。
        .animatesSheetStage(stage)
        .animation(.anitabiSpring, value: isSearchActive)
        // ドラッグでキーボードを下げる（検索結果を読みながら閉じたいときの標準挙動）。
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: isSearchFocused) { _, focused in
            guard focused else { return }  // 外れた側は無視 —— キーボードだけ下げた場合がこれ。
            isSearchActive = true
            withAnimation(.anitabiSpring) { homeDetent = expandedDetent }
        }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
        .sheet(isPresented: $isShowingAbout) { AboutSheet() }
        .task(id: cameraState) { await refreshViewportWorkChips() }
    }

    // MARK: 視口作品 chips の集計

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

    /// 視口に絞り込む相手が居ないときに「试试:」で薦める作品（設計稿 2a の首次使用変体）。
    private var suggestedWorkIDs: [Int] {
        store.works(for: .popular).prefix(6).map(\.id)
    }

    // MARK: 検索行（設計稿 1a / 1b）

    /// 設計稿 1a/1b の検索行：検索欄 ＋（激活時は「取消」／通常は「⋯」丸釦）。
    private var searchRow: some View {
        HStack(spacing: SheetMetrics.itemSpacing) {
            searchCapsule
            if isSearchActive {
                Button("取消") { endSearch() }
                    .font(SheetFont.searchCancel)
                    .foregroundStyle(Color.anitabiInk)
                    .buttonStyle(.plain)
            } else {
                menuButton
            }
        }
        // 迷你条の枠は 4 枚のカードで共通（`compactBarRow`：行高＋上下の余白）。
        .compactBarRow()
        .scenePadding(.horizontal)
        .animation(.anitabiSpring, value: isSearchActive)
    }

    /// 設計稿 1a：白い薄膜 ＋ 白の縁。激活態（1b）は地を上げて**墨 1.5pt の縁**に変える。
    /// placeholder は設計稿の色に合わせるため系统の既定に任せず自前で敷く。
    private var searchCapsule: some View {
        HStack(spacing: SheetMetrics.itemSpacing) {
            Image(systemName: "magnifyingglass")
                .font(SheetFont.searchField)
                .foregroundStyle(isSearchActive ? Color.anitabiInk : Color.anitabiInkTertiary)

            ZStack(alignment: .leading) {
                if searchText.isEmpty {
                    Text("搜作品 / 地点 / 城市")
                        .foregroundStyle(Color.anitabiInkFaint)
                        .allowsHitTesting(false)
                }
                TextField("", text: $searchText)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .foregroundStyle(Color.anitabiInk)
                    .tint(Color.anitabiInk)
            }
            // 激活態だけ太字（設計稿 1b の `font-weight:700`）。
            .font(isSearchActive ? SheetFont.searchCancel : SheetFont.searchField)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: SheetMetrics.scaled(9), weight: .bold))
                        .foregroundStyle(Color.anitabiInk)
                        .frame(width: SheetMetrics.searchClearDiameter, height: SheetMetrics.searchClearDiameter)
                        .background(Color.anitabiSoftFill, in: .circle)
                        .expandedHitTarget(visualSize: SheetMetrics.searchClearDiameter)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -SheetMetrics.scaled(13))
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, SheetMetrics.searchFieldHorizontalPadding)
        // `minHeight` にして超大 Dynamic Type でも文字が潰れないようにする。
        .frame(minHeight: SheetMetrics.controlHeight)
        .background(isSearchActive ? Color.anitabiRaised : Color.anitabiSurface, in: .capsule)
        .overlay {
            Capsule().strokeBorder(
                isSearchActive ? Color.anitabiInk : Color.anitabiRaisedStroke,
                lineWidth: isSearchActive ? 1.5 : 1
            )
        }
    }

    /// 行末の丸釦。寸法は他カードの ✕・共有と共通（`CardCircleLabel`）——
    /// 首页だけ大きいと一段式の迷你条で不揃いに見える。
    private var menuButton: some View {
        Menu {
            Button("重看欢迎页") { router.wantsWelcomeReplay = true }
            Button("在网页版打开") {
                // 現在の镜头（c/z）をそのまま web 版へ引き継ぐ。
                safariItem = SafariItem(url: AnitabiWebLink.canonical(
                    coordinate: cameraState?.region.center,
                    zoom: cameraState?.zoom
                ))
            }
            Button("关于") { isShowingAbout = true }
        } label: {
            CardCircleLabel(systemName: "ellipsis")
        }
        // 行末に置く丸釦なので、見た目の縁を余白に揃える（`CardCloseButton` と同じ扱い）。
        .alignedToVisualEdge(visualSize: SheetMetrics.circleButtonDiameter)
        .accessibilityLabel("更多")
    }

    private func endSearch() {
        searchText = ""
        isSearchFocused = false
        isSearchActive = false
        withAnimation(.anitabiSpring) { homeDetent = initialDetent }
    }

    /// 検索から都市を選んだ（web 版と同じ導線）：都市名を検索欄に**残し**、検索態のまま
    /// 下に「この都市の作品」を出す。キーボードだけ下げて一覧を読めるようにし、
    /// 镜头は裏で都市へ飛ばす（sheet は落とさない —— 落とすと一覧が見えない）。
    private func pickCity(_ city: CityTile) {
        searchText = city.name
        isSearchFocused = false
        onFocusCity(city, false)
    }
}
