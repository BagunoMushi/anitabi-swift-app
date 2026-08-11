//
//  WorkPointList.swift
//  anitabi
//
//  作品カードの分組点一覧（設計稿 2b）。分組ロジック自体は Store 側の持ち物。
//  選中行は系统の accent ではなく**作品の主題色の枠**で示す（設計稿 1c）——
//  作品ごとの色がこの App の識別子。
//
//  一覧は**組ごとに束ねず、行 1 つを 1 要素まで平らにして**呼び出し側の `LazyVStack` へ渡す。
//  懒容器が惰性化するのは直接の子だけなので、組（＝`SheetListCard` 1 枚）で渡すと 600 点の
//  作品では 600 行が丸ごと構築・布局される。白い薄膜の面は `sheetListSegment` が行ごとに分担する。
//

import SwiftUI

// MARK: - 平らにした一覧

/// 一覧の 1 要素。`LazyVStack` の直接の子になるのはこの粒度。
enum WorkListElement: Identifiable {
    case header(WorkListHeader)
    case row(WorkListRow)

    var id: String {
        switch self {
        case .header(let header): "h:\(header.id)"
        case .row(let row): "r:\(row.id)"
        }
    }
}

/// 組の見出し 1 つぶん。
struct WorkListHeader {
    /// `PointGroup.id`。折り畳みの記憶もこれで引く。
    let id: String
    let name: String
    let pointCount: Int
    let isCollapsed: Bool
    /// 先頭の組か（＝上に節間隔を空けない。控件行との間隔は呼び出し側が持つ）。
    let isFirst: Bool
    /// 下に行が続くか（畳んでいる組は続かないので、見出しの下余白も要らない）。
    let hasRows: Bool
}

/// 一覧の 1 行ぶん。
struct WorkListRow: Identifiable {
    let point: ScenePoint
    /// 同じ組の直前の行の id（先頭なら nil）。細線を引くかの判定に使う。
    /// **選択中の点は持たせない** —— 持たせると点を選ぶたびに全要素を組み直すことになる。
    let previousID: String?
    /// 組の中での位置（面のどこを描くか）。
    let segment: SheetListSegment

    var id: String { point.id }
}

extension WorkListElement {
    /// 組の配列を行単位まで平らにする。畳んでいる組は見出しだけを残す。
    static func flatten(
        _ groups: [PointGroup],
        showsHeaders: Bool,
        collapsedGroupIDs: Set<String>
    ) -> [WorkListElement] {
        var elements: [WorkListElement] = []
        elements.reserveCapacity(groups.reduce(groups.count) { $0 + $1.points.count })

        for (index, group) in groups.enumerated() {
            let isCollapsed = showsHeaders && collapsedGroupIDs.contains(group.id)
            let points = isCollapsed ? [] : group.points

            if showsHeaders {
                elements.append(.header(WorkListHeader(
                    id: group.id,
                    name: group.name,
                    pointCount: group.points.count,
                    isCollapsed: isCollapsed,
                    isFirst: index == 0,
                    hasRows: !points.isEmpty
                )))
            }

            for (offset, point) in points.enumerated() {
                elements.append(.row(WorkListRow(
                    point: point,
                    previousID: offset == 0 ? nil : points[offset - 1].id,
                    segment: .at(offset, count: points.count)
                )))
            }
        }
        return elements
    }
}

// MARK: - 組の見出し

/// 設計稿 2b：`组名 12.5/900` ＋ `N 个点位 11px` ＋ 右端に折り畳みの `⌄`。
struct WorkPointGroupHeader: View {
    let header: WorkListHeader
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SheetMetrics.scaled(6)) {
                Text(header.name)
                    .font(SheetFont.sectionTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(1)
                Text("\(header.pointCount) 个点位")
                    .font(SheetFont.meta)
                    .foregroundStyle(Color.anitabiInkTertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(SheetFont.meta.weight(.semibold))
                    .foregroundStyle(Color.anitabiInkFaint)
                    .rotationEffect(.degrees(header.isCollapsed ? -90 : 0))
            }
            .padding(.horizontal, SheetMetrics.headerInset)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // 組と組の間（設計稿の節間隔）。先頭の組の上は控件行が持つ。
        .padding(.top, header.isFirst ? 0 : SheetMetrics.sectionSpacing)
        .padding(.bottom, header.hasRows ? SheetMetrics.headerSpacing : 0)
    }
}

// MARK: - 行

/// 一覧の 1 行（細線 ＋ 押せる行 ＋ その行が受け持つ面）。
struct WorkPointCell: View {
    let store: AnitabiStore
    let row: WorkListRow
    let selectedPointID: String?
    let themeColor: Color
    var onSelect: (ScenePoint) -> Void

    /// 剧照 50 ＋ 間隔 10。分隔線はここまで寄せる。
    private static var textInset: CGFloat {
        SheetMetrics.pointThumbnailSize.width + SheetMetrics.thumbnailGap
    }

    private var isSelected: Bool { row.point.id == selectedPointID }

    /// 選中行は自前の枠を持つので、その上下には細線を引かない（設計稿 1c と同じ見え方）。
    private var showsHairline: Bool {
        guard let previousID = row.previousID else { return false }
        return !isSelected && previousID != selectedPointID
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHairline {
                SheetHairline(leadingInset: Self.textInset)
            }
            Button { onSelect(row.point) } label: {
                WorkPointRow(
                    store: store,
                    point: row.point,
                    isSelected: isSelected,
                    themeColor: themeColor
                )
            }
            .buttonStyle(.plain)
        }
        .sheetListSegment(row.segment)
    }
}

struct WorkPointRow: View {
    let store: AnitabiStore
    let point: ScenePoint
    let isSelected: Bool
    let themeColor: Color

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            SceneThumbnail(
                url: point.thumbnailURL,
                size: SheetMetrics.pointThumbnailSize,
                radius: SheetMetrics.pointThumbnailRadius,
                // 剧照が無いことを主題色で示す（このカードは既に 1 作品に絞られているので
                // 大面積の主題色にはならない）。
                placeholder: point.thumbnailURL == nil ? themeColor.anitabiThemeGradient : nil
            )

            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                Text(point.displayName.nilIfBlank ?? String(localized: "巡礼点"))
                    .font(SheetFont.rowTitleDense)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(1)
                metaRow
            }
            Spacer(minLength: 0)
            RowChevron()
        }
        .padding(.vertical, SheetMetrics.rowVerticalPadding)
        // 選中行だけ主題色の枠を被せる（設計稿 1c `padding:9px 8px; margin:4px -8px`）。
        .padding(.horizontal, isSelected ? SheetMetrics.scaled(8) : 0)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: SheetMetrics.tileRadius, style: .continuous)
                    .fill(themeColor.opacity(0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: SheetMetrics.tileRadius, style: .continuous)
                            .strokeBorder(themeColor, lineWidth: SheetMetrics.shape(1.5))
                    }
            }
        }
        .padding(.horizontal, isSelected ? -SheetMetrics.scaled(8) : 0)
        .padding(.vertical, isSelected ? SheetMetrics.scaled(4) : 0)
        .contentShape(.rect)
    }

    /// 設計稿 2b の 2 行目：`EP03 · 08:12 · 備考` ＋「注意礼仪」徽章。
    /// 2 行目までで打ち切る（収まらない情報は地標カードで読む）。
    @ViewBuilder
    private var metaRow: some View {
        let meta = [point.episodeBadge, point.timecodeText, point.note?.nilIfBlank ?? point.folderName?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !meta.isEmpty || point.needsEtiquetteWarning {
            HStack(spacing: SheetMetrics.scaled(5)) {
                if !meta.isEmpty {
                    Text(meta)
                        .font(SheetFont.meta)
                        .foregroundStyle(Color.anitabiInkSecondary)
                        .lineLimit(1)
                }
                if point.needsEtiquetteWarning {
                    EtiquetteBadge()
                }
            }
        }
    }
}
