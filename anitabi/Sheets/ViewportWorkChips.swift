//
//  ViewportWorkChips.swift
//  anitabi
//
//  視口内複数作品フィルタ（Web 版 `bids` の等価機能）。検索行のすぐ下＝`HomeBrowseView` の
//  スクロール内容の先頭に挿す横滑り chips。Apple マップの絞り込み chips はカードの上端に
//  貼り付くのが常で、地図の上に浮かせない——ここでも同じ方針。
//
//  集計（デバウンス付き `store.worksInViewport` 呼び出し）は**ここでは持たない**——
//  `HomeBrowseView` の `LazyVStack` の先頭に挿すと、中身が空（＝高さ 0）の間
//  `.task` がレイジーコンテナに生かされ続ける保証が無い（実測で `.task(id:)` が
//  一度も発火しないことを確認済み）。そのため計算は `LazyVStack` の外側
//  （`HomeBrowseView` の `ScrollView` 直下）へ上げ、ここは渡された `candidates` を
//  描くだけの純粋な表示コンポーネントにしてある。
//

import SwiftUI

struct ViewportWorkChips: View {
    let store: AnitabiStore
    let router: AppRouter
    /// `HomeBrowseView` が集計済みの視口内作品（点数降順・上限適用済み）。空なら何も描かない。
    let candidates: [(id: Int, count: Int)]

    static let minZoom = 12.0
    static let minWorkCount = 2

    var body: some View {
        if candidates.count >= Self.minWorkCount {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(candidates, id: \.id) { entry in
                        chip(for: entry.id)
                    }
                    if !router.selectedWorkIDs.isEmpty {
                        clearChip
                    }
                }
            }
            .scrollClipDisabled()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - chip

    /// 選中態は `.borderedProminent`（tint 蓝）、非選中は `.bordered` 灰——寸法は同じ regular
    /// カプセルのまま、色（style）だけで主従を分ける（HIG・spec 通り）。
    @ViewBuilder
    private func chip(for id: Int) -> some View {
        if router.selectedWorkIDs.contains(id) {
            Button { toggle(id) } label: { chipLabel(id) }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .font(.subheadline)
        } else {
            Button { toggle(id) } label: { chipLabel(id) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .font(.subheadline)
                .tint(.secondary)
        }
    }

    private func toggle(_ id: Int) {
        withAnimation(.anitabiSpring) { router.toggleWorkFilter(id: id) }
    }

    private func chipLabel(_ id: Int) -> some View {
        HStack(spacing: 6) {
            chipCover(id)
            Text(shortName(id)).lineLimit(1)
        }
    }

    /// 18pt の丸いカバー。無い作品はテーマ色のまま（**文字は置かない**——硬約束）。
    private func chipCover(_ id: Int) -> some View {
        let bangumi = store.bangumi(id: id)
        return Circle()
            .fill(bangumi?.themeGradient
                  ?? LinearGradient(colors: [store.color(forBangumi: id)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if let url = bangumi?.coverURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipShape(.circle)
            .frame(width: 18, height: 18)
    }

    /// `abbr` があればそれを優先、無ければ表示名の先頭 6 字。
    private func shortName(_ id: Int) -> String {
        if let abbr = store.bangumi(id: id)?.abbr?.nilIfBlank { return abbr }
        let name = store.name(forBangumi: id)
        return name.count > 6 ? String(name.prefix(6)) : name
    }

    private var clearChip: some View {
        Button {
            withAnimation(.anitabiSpring) { router.clearWorkFilter() }
        } label: {
            Label("清除", systemImage: "xmark")
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(.secondary)
    }
}
