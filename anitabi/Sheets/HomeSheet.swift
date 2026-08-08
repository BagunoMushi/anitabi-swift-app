//
//  HomeSheet.swift
//  anitabi
//
//  常駐する根 sheet（Browse）。検索カプセル行を ScrollView の**上**に固定で置き、
//  中身は「通常のブラウズ」と「検索アクティブ」の 2 状態を切り替えるだけの薄い器。
//  各状態の実装は HomeBrowseView / SearchResultsView（同ディレクトリ）に譲る。
//

import SwiftUI

struct HomeSheet: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
    /// 視口作品 chips（阶段 7）が読む最新のカメラ状態。`RootView.onCameraIdle` からそのまま渡ってくる。
    let cameraState: MapCameraState?
    /// RootView が持つ Home 档の実体。検索フォーカス・「更多」・都市クイック釦から
    /// 直接動かせるよう Binding で受け取る（`.presentationDetents` 自体は RootView 側のまま）。
    @Binding var homeDetent: PresentationDetent

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

    var body: some View {
        // 検索行は `safeAreaInset(edge: .top)` では**なく** ScrollView の上に積む。
        // safeAreaInset だと中身は行の“下をくぐって”流れ、この行には地（不透明背景）が無いので
        // 巻き上げた文字がそのまま透けて重なる（终审 P1）。iOS 26 の `safeAreaBar` ＋
        // `scrollEdgeEffectStyle(.hard, for: .top)` も実測ではぼかしが掛かるだけで透けは残った。
        // sheet の地はガラス（地図が透ける）なので、行に不透明背景を敷く逃げも使えない。
        // → 行を ScrollView の外に出して、中身が行の下へ入れる余地そのものを無くす。
        VStack(spacing: 0) {
            searchRow
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
                    cameraState: cameraState,
                    homeDetent: $homeDetent,
                    onSelectPoint: onSelectPoint,
                    onFocusCity: onFocusCity
                )
            }
        }
        // ドラッグでキーボードを下げる（検索結果を読みながら閉じたいときの標準挙動）。
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: isSearchFocused) { _, focused in
            guard focused else { return }  // 外れた側は無視 —— キーボードだけ下げた場合がこれ。
            isSearchActive = true
            withAnimation(.anitabiSpring) { homeDetent = .large }
        }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
        .sheet(isPresented: $isShowingAbout) { AboutSheet() }
    }

    // MARK: 検索行

    /// 高さの内訳（15 + 42 + 15）が最小档 72pt の実体（`SheetLayout.homeMinHeight`）。
    /// 42pt は Apple マップの検索欄の実測値で、中の文字は 17pt `.body`。
    /// どれか 1 つだけ変えると最小档の下にガラスが余る／中身が切れる。
    private var searchRow: some View {
        HStack(spacing: 8) {
            capsule
            if isSearchActive {
                Button("取消") { endSearch() }
                    .font(.body)
            } else {
                menuButton
            }
        }
        .padding(.horizontal, SheetMetrics.horizontalPadding)
        .padding(.top, SheetMetrics.topInset)
        .padding(.bottom, SheetMetrics.horizontalPadding)
        .animation(.anitabiSpring, value: isSearchActive)
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索作品、地点或城市", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(.horizontal, 10)
        // `minHeight` にして超大 Dynamic Type でも文字が潰れないようにする（既定は 42pt のまま）。
        .frame(minHeight: SheetMetrics.searchFieldHeight)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }

    /// 検索欄と同じ辺（42pt）の丸釦。Apple マップの検索行右端も 42×42 の実測なので、
    /// ここは `controlSize` ではなく検索欄と揃える寸法を優先する（44pt との差 2pt は Apple 実物と同じ）。
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
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: SheetMetrics.searchFieldHeight, height: SheetMetrics.searchFieldHeight)
                .background(Color(.tertiarySystemFill), in: .circle)
                .contentShape(.circle)
        }
        // Menu は既定で中身を tint 色に塗るので、灰の記号に戻す。
        .tint(Color.secondary)
        .accessibilityLabel("更多")
    }

    private func endSearch() {
        searchText = ""
        isSearchFocused = false
        isSearchActive = false
        withAnimation(.anitabiSpring) { homeDetent = SheetLayout.homeInitial }
    }
}

// MARK: - 共通バネ

extension Animation {
    /// spec 全体で使う唯一のバネ設定。sheet 档・検索行の切り替えなど全アニメがこれに揃う。
    static let anitabiSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
}
