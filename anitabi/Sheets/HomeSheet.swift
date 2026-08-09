//
//  HomeSheet.swift
//  anitabi
//
//  常駐する根 sheet（Browse）。設計稿 1a/1b/2a の検索行を ScrollView の**上**に固定で置き、
//  中身は「通常のブラウズ」と「検索アクティブ」の 2 状態を切り替えるだけの薄い器。
//  各状態の実装は HomeBrowseView / SearchResultsView（同ディレクトリ）に譲る。
//

import SwiftUI

struct HomeSheet: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
    /// 視口作品 chips が読む最新のカメラ状態。`RootView.onCameraIdle` からそのまま渡ってくる。
    let cameraState: MapCameraState?
    /// RootView が持つ Home 档の実体。検索フォーカス・都市クイック釦から直接動かせるよう
    /// Binding で受け取る（`.presentationDetents` 自体は RootView 側のまま）。
    @Binding var homeDetent: PresentationDetent
    /// いま何段目か。一段式では検索行＋chips 行より下を**描かない**（設計稿 2a 一段式）。
    var stage: SheetStage = .medium
    /// 検索に入ったとき持ち上げる先（設計稿の三段式）。RootView が画面高から作って渡す。
    var expandedDetent: PresentationDetent = .large
    /// 検索を終えたとき戻る先（設計稿の两段式）。同じく RootView が作って渡す。
    var initialDetent: PresentationDetent = .medium

    /// 一覧から地標を選んだ経路。RootView 側で密度 flyTo を実行する「既存の onSelectPoint 通路」。
    var onSelectPoint: (ScenePoint) -> Void
    /// 都市タイル／検索の都市行から镜头を都市へ寄せる。
    var onFocusCity: (CityTile) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    /// 検索モードに入っているか。`isSearchFocused` と同一にしてしまうと、
    /// `scrollDismissesKeyboard(.interactively)` で結果を読みながらキーボードだけ下げた瞬間に
    /// 検索画面ごと消えてしまう。検索モードを終えるのは `endSearch()`（取消／行 tap 後）だけ。
    @State private var isSearchActive = false

    /// 「⋯」メニューの「在网页版打开」。他カードと同じく、他の呈现スタックへ影響させないよう
    /// カード自身の `@State` で持つ（`PointCardSheet` と同じ方針）。
    @State private var safariItem: SafariItem?
    @State private var isShowingAbout = false

    /// 視口内作品 chips の集計結果。デバウンス付きで `store.worksInViewport` を叩くタスクは
    /// **レイジーコンテナの外**に置く —— 中身が空（＝高さ 0）の間 `.task` が `LazyVStack` 内で
    /// 生かされ続ける保証が無く、実測で一度も発火しないことを確認したため。
    @State private var viewportWorkChips: [(id: Int, count: Int)] = []
    private static let viewportChipsDebounce = Duration.milliseconds(300)

    var body: some View {
        // 検索行は `safeAreaInset(edge: .top)` では**なく** ScrollView の上に積む。
        // safeAreaInset だと中身は行の“下をくぐって”流れ、この行には地（不透明背景）が無いので
        // 巻き上げた文字がそのまま透けて重なる。sheet の地はガラス（地図が透ける）なので、
        // 行に不透明背景を敷く逃げも使えない。
        // → 行を ScrollView の外に出して、中身が行の下へ入れる余地そのものを無くす。
        VStack(spacing: 0) {
            // 検索行＋（中/大档だけ）作品 chips 行。ScrollView の**外**に固定する。
            VStack(spacing: 0) {
                searchRow
                // 一段式では chips 行を出さない —— iOS 26 の迷你条（`SheetLayout.minHeight` 参照）に
                // 収まるのは検索行だけで、chips まで入れると中身が画面外へ切れる。
                // Apple マップの収起検索条と同じ「検索行だけの浮き玉」に揃える。
                if !isSearchActive && stage != .compact {
                    ViewportWorkChips(
                        store: store,
                        router: router,
                        candidates: viewportWorkChips,
                        suggestions: suggestedWorkIDs
                    )
                    .scenePadding(.horizontal)
                }
            }
            // 一段式の実高は**検索行だけ**の複製で測る（作品／地標カードの probe と同じ手法）。
            // 生の行を測ると chips の出入りで最小档が動き、収起が二段落ちになる。
            .overlay(alignment: .top) {
                searchRow
                    .fixedSize(horizontal: false, vertical: true)
                    .compactContentHeight(.home)
                    .hidden()
                    .frame(height: 0, alignment: .top)
            }
            // chips 行 → 列の間隔（設計稿 2a の `margin-top:10px`）。
            .padding(.bottom, SheetMetrics.sectionSpacing)

            // 一段式では列を描かない。sheet の中身は底部安全区の**下にも描かれる**ので、
            // 高さを身份条ぴったりにしても、そのままだと次の節がホームインジケータ帯に覗く。
            // 判定は RootView が生の sheet 高さから出すので、拖动の途中で即座に戻る。
            Group {
                if isSearchActive {
                    SearchResultsView(
                        store: store,
                        router: router,
                        locationProvider: locationProvider,
                        query: searchText,
                        onSelectPoint: onSelectPoint,
                        onFocusCity: onFocusCity,
                        onFinishSelection: endSearch
                    )
                } else {
                    HomeBrowseView(
                        store: store,
                        router: router,
                        locationProvider: locationProvider,
                        onSelectPoint: onSelectPoint,
                        onFocusCity: onFocusCity
                    )
                }
            }
            // 一段式では中身を**レイアウトからも外す**（高さ 0 に畳む）。opacity だけで
            // 隠していた版は、見えないまま場所を要求し続ける —— sheet の高さが足りないぶんを
            // SwiftUI が身份条の余白から削るので、カードごとに 3〜10pt 潰れて
            // 「首页の検索だけ上、他の 2 枚は下」という食い違いになっていた（実測）。
            .frame(height: stage == .compact ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(stage != .compact)
        }
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

    /// 設計稿 2a の積み上げ：上余白 27（＝カード 8 ＋ 抓手 4+5+10）＋ 検索欄 40 ＋ 下 10。
    /// 40pt は設計稿の検索欄（`padding:10px 14px` ＋ 14px 字）で、右隣の丸釦も同じ辺。
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
        // 検索欄がちょうどこの行高で、一段式の実高＝この行そのもの（probe が測る）。
        .compactBarRow()
        .scenePadding(.horizontal)
        .animation(.anitabiSpring, value: isSearchActive)
    }

    /// 設計稿 1a：白 65% の地 ＋ 白 90% の縁。1b（激活態）：白 85% の地 ＋ **墨 1.5pt の縁**。
    /// placeholder は設計稿の `rgba(19,46,26,.45)` に合わせるため系统の既定に任せず自前で敷く。
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
        // `minHeight` にして超大 Dynamic Type でも文字が潰れないようにする（既定は 40pt のまま）。
        .frame(minHeight: SheetMetrics.searchFieldHeight)
        .background(isSearchActive ? Color.anitabiRaised : Color.anitabiSurface, in: .capsule)
        .overlay {
            Capsule().strokeBorder(
                isSearchActive ? Color.anitabiInk : Color.anitabiRaisedStroke,
                lineWidth: isSearchActive ? 1.5 : 1
            )
        }
    }

    /// 行末の丸釦。他カードの頭部（共有 ⤴ ・✕）と**同じ `CardCircleLabel`**を使う。
    /// 設計稿 1a はここだけ検索欄と同じ 40×40 にしているが、その版は一段式の迷你条で
    /// 首页の ⋯ だけ一回り大きく見えた（他カードの ✕ は 34px）ので寸法は共通側へ寄せた。
    private var menuButton: some View {
        Menu {
            Button("重看欢迎页") { router.wantsWelcomeReplay = true }
            Button("在网页版打开") {
                // 現在の镜头（c/z）をそのまま web 版へ引き継ぐ。地標／作品を選んでいないときは
                // `AnitabiWebLink.canonical` が座標無しの `/map` を返す（未定=地図トップ）。
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
        // 激活態の「取消」は丸釦ではないので付けない。
        .alignedToVisualEdge(visualSize: SheetMetrics.circleButtonDiameter)
        .accessibilityLabel("更多")
    }

    private func endSearch() {
        searchText = ""
        isSearchFocused = false
        isSearchActive = false
        withAnimation(.anitabiSpring) { homeDetent = initialDetent }
    }
}
