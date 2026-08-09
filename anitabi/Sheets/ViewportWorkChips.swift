//
//  ViewportWorkChips.swift
//  anitabi
//
//  視口内複数作品フィルタ（Web 版 `bids` の等価機能）。設計稿 2a の一段式 2 行目 ——
//  検索行のすぐ下に貼り付く横滑り chips で、地図の上に浮かせない。
//
//  設計稿の 2 態：
//  - 視口に作品が 2 つ以上 → 作品 chips（選中は深緑実心 ＋ 点数、末尾に「清除」）
//  - 視口に絞る相手が居ない（初回起動など）→ 「试试:」＋ 推荐作品 chips
//
//  どちらの態でも**行は空にならない**。最小档の高さは「検索行 ＋ この行」の実測値なので、
//  空にするとカードの下にガラスが余ってしまう。
//
//  集計（デバウンス付き `store.worksInViewport` 呼び出し）は**ここでは持たない**——
//  `HomeBrowseView` の `LazyVStack` の先頭に挿すと、中身が空（＝高さ 0）の間
//  `.task` がレイジーコンテナに生かされ続ける保証が無い（実測で `.task(id:)` が
//  一度も発火しないことを確認済み）。そのため計算は `LazyVStack` の外側へ上げ、
//  ここは渡された配列を描くだけの純粋な表示コンポーネントにしてある。
//

import SwiftUI

struct ViewportWorkChips: View {
    let store: AnitabiStore
    let router: AppRouter
    /// `HomeBrowseView` が集計済みの視口内作品（点数降順・上限適用済み）。
    let candidates: [(id: Int, count: Int)]
    /// 視口に絞る相手が居ないときに「试试:」で薦める作品。
    var suggestions: [Int] = []

    static let minZoom = 12.0
    static let minWorkCount = 2

    private var isShowingSuggestions: Bool { candidates.count < Self.minWorkCount }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SheetMetrics.scaled(6)) {
                if isShowingSuggestions {
                    Text("试试:")
                        .font(SheetFont.meta)
                        .foregroundStyle(Color.anitabiInkTertiary)
                    ForEach(suggestions, id: \.self) { id in
                        chip(for: id, count: nil)
                    }
                } else {
                    ForEach(candidates, id: \.id) { entry in
                        chip(for: entry.id, count: entry.count)
                    }
                    if !router.selectedWorkIDs.isEmpty {
                        clearChip
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - chip

    /// 選中態は設計稿 `background:#132e1a; color:#eaffec`（点数付き）、非選中は白い薄膜。
    /// 寸法は同じ chip のまま、色だけで主従を分ける。
    private func chip(for id: Int, count: Int?) -> some View {
        Button { toggle(id) } label: {
            HStack(spacing: SheetMetrics.scaled(6)) {
                WorkChipCover(bangumi: store.bangumi(id: id), fallback: store.color(forBangumi: id))
                Text(chipTitle(id, count: count))
                    .lineLimit(1)
            }
        }
        .buttonStyle(AnitabiCapsuleStyle(
            kind: router.selectedWorkIDs.contains(id) ? .primary : .secondary,
            size: .chip
        ))
    }

    /// 選中した作品だけ設計稿どおり `作品名 · 12` と点数を添える。
    private func chipTitle(_ id: Int, count: Int?) -> String {
        guard let count, router.selectedWorkIDs.contains(id) else { return shortName(id) }
        return "\(shortName(id)) · \(count)"
    }

    private func toggle(_ id: Int) {
        withAnimation(.anitabiSpring) { router.toggleWorkFilter(id: id) }
    }

    /// `abbr` があればそれを優先、無ければ表示名の先頭 6 字。
    private func shortName(_ id: Int) -> String {
        if let abbr = store.bangumi(id: id)?.abbr?.nilIfBlank { return abbr }
        let name = store.name(forBangumi: id)
        return name.count > 6 ? String(name.prefix(6)) : name
    }

    /// 設計稿 `background:rgba(19,46,26,.08)` の軟 chip。
    private var clearChip: some View {
        Button("清除") {
            withAnimation(.anitabiSpring) { router.clearWorkFilter() }
        }
        .buttonStyle(AnitabiCapsuleStyle(kind: .soft, size: .chip))
    }
}
