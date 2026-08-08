//
//  HomeSheet.swift
//  anitabi
//
//  常駐する根 sheet（Browse）。検索カプセル行を safeAreaInset で常設し、
//  中身は「通常のブラウズ」と「検索アクティブ」の 2 状態を切り替えるだけの薄い器。
//  各状態の実装は HomeBrowseView / SearchResultsView（同ディレクトリ）に譲る。
//

import SwiftUI

struct HomeSheet: View {

    let store: AnitabiStore
    let router: AppRouter
    let locationProvider: LocationProvider
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

    var body: some View {
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
                    homeDetent: $homeDetent,
                    onSelectPoint: onSelectPoint,
                    onFocusCity: onFocusCity
                )
            }
        }
        // ドラッグでキーボードを下げる（検索結果を読みながら閉じたいときの標準挙動）。
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { searchRow }
        .onChange(of: isSearchFocused) { _, focused in
            guard focused else { return }  // 外れた側は無視 —— キーボードだけ下げた場合がこれ。
            isSearchActive = true
            withAnimation(.anitabiSpring) { homeDetent = .large }
        }
    }

    // MARK: 検索行

    /// 高さの内訳（20 + 48 + 8）が最小档 76pt の実体。片方だけ変えると下にガラスが余る。
    private var searchRow: some View {
        HStack(spacing: 8) {
            capsule
            if isSearchActive {
                Button("取消") { endSearch() }
                    .font(.body)
                    .foregroundStyle(.blue)
            } else {
                menuButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
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
        .padding(.horizontal, 12)
        // `minHeight` にして超大 Dynamic Type でも文字が潰れないようにする（既定は 48pt のまま）。
        .frame(minHeight: 48)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }

    private var menuButton: some View {
        Menu {
            // 阶段 8 で実処理を接ぐ。今は項目の存在だけを確定させる占位。
            Button("重看欢迎页") {}
            Button("在网页版打开") {}
            Button("关于") {}
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
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
