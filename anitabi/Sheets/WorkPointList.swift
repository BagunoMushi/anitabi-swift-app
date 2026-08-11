//
//  WorkPointList.swift
//  anitabi
//
//  作品カードの分組点一覧（設計稿 2b）。分組ロジック自体は Store 側の持ち物。
//  選中行は系统の accent ではなく**作品の主題色の枠**で示す（設計稿 1c）——
//  作品ごとの色がこの App の識別子。
//

import SwiftUI

struct WorkPointList: View {
    let store: AnitabiStore
    let groups: [PointGroup]
    /// 组头を出すか。「folder 组数>1 も ep も無い」場合は呼び出し側が false にして平铺表示にする。
    let showsHeaders: Bool
    @Binding var collapsedGroupIDs: Set<String>
    let selectedPointID: String?
    /// 選中行の描边に使う作品の主題色。
    let themeColor: Color
    var onSelectPoint: (ScenePoint) -> Void

    /// 剧照 50 ＋ 間隔 10。分隔線はここまで寄せる。
    private static var textInset: CGFloat { SheetMetrics.pointThumbnailSize.width + SheetMetrics.thumbnailGap }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeaders ? SheetMetrics.sectionSpacing : 0) {
            ForEach(groups) { group in
                if showsHeaders {
                    VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                        groupHeader(group)
                        if !collapsedGroupIDs.contains(group.id) {
                            SheetListCard { pointRows(group.points) }
                        }
                    }
                } else {
                    SheetListCard { pointRows(group.points) }
                }
            }
        }
    }

    /// 設計稿 2b：`组名 12.5/900` ＋ `N 个点位 11px` ＋ 右端に折り畳みの `⌄`。
    private func groupHeader(_ group: PointGroup) -> some View {
        let collapsed = collapsedGroupIDs.contains(group.id)
        return Button {
            withAnimation(.anitabiSpring) {
                if collapsed { collapsedGroupIDs.remove(group.id) } else { collapsedGroupIDs.insert(group.id) }
            }
        } label: {
            HStack(spacing: SheetMetrics.scaled(6)) {
                Text(group.name)
                    .font(SheetFont.sectionTitle)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(1)
                Text("\(group.points.count) 个点位")
                    .font(SheetFont.meta)
                    .foregroundStyle(Color.anitabiInkTertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(SheetFont.meta.weight(.semibold))
                    .foregroundStyle(Color.anitabiInkFaint)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .padding(.horizontal, SheetMetrics.headerInset)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pointRows(_ points: [ScenePoint]) -> some View {
        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
            let isSelected = point.id == selectedPointID
            // 選中行は自前の枠を持つので、その上下には細線を引かない（設計稿 1c と同じ見え方）。
            if index > 0, !isSelected, points[index - 1].id != selectedPointID {
                SheetHairline(leadingInset: Self.textInset)
            }
            Button { onSelectPoint(point) } label: {
                WorkPointRow(store: store, point: point, isSelected: isSelected, themeColor: themeColor)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 点行

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
