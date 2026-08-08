//
//  WorkPointList.swift
//  anitabi
//
//  作品カードの分組点一覧。`AnitabiStore.groupedPoints(for:mode:)` が組んだ `[PointGroup]` を
//  そのまま描くだけ——分組ロジック自体は Store 側（阶段 1）の持ち物。
//

import SwiftUI

struct WorkPointList: View {
    let store: AnitabiStore
    let groups: [PointGroup]
    /// 组头を出すか。「folder 组数>1 も ep も無い」場合は呼び出し側が false にして平铺表示にする。
    let showsHeaders: Bool
    @Binding var collapsedGroupIDs: Set<String>
    let selectedPointID: String?
    var onSelectPoint: (ScenePoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider().padding(.leading, showsHeaders ? 0 : 76)
                }
                if showsHeaders {
                    groupHeader(group)
                }
                if !showsHeaders || !collapsedGroupIDs.contains(group.id) {
                    pointRows(group.points)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: ConcentricRectangle(corners: .concentric(minimum: 16)))
    }

    private func groupHeader(_ group: PointGroup) -> some View {
        let collapsed = collapsedGroupIDs.contains(group.id)
        return Button {
            withAnimation(.anitabiSpring) {
                if collapsed { collapsedGroupIDs.remove(group.id) } else { collapsedGroupIDs.insert(group.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(group.name).font(.headline).lineLimit(1)
                Text("\(group.points.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pointRows(_ points: [ScenePoint]) -> some View {
        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
            if index > 0 {
                Divider().padding(.leading, 76)
            }
            Button { onSelectPoint(point) } label: {
                WorkPointRow(store: store, point: point, isSelected: point.id == selectedPointID)
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PointThumbnail(url: point.thumbnailURL, gradient: themeGradient)
                .frame(width: 64, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(point.displayName.nilIfBlank ?? "巡礼点")
                    .font(.body)
                    .lineLimit(1)
                badgeRow
                if let subtitle = point.note?.nilIfBlank ?? point.folderName?.nilIfBlank {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .padding(.horizontal, -8)
            }
        }
        .contentShape(.rect)
    }

    private var themeGradient: LinearGradient {
        let color = store.color(forBangumi: point.bangumiID)
        return LinearGradient(
            colors: [color, color.mix(with: .black, by: 0.28)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var badgeRow: some View {
        let ep = point.episodeBadge
        let timecode = point.timecodeText
        let warns = point.needsEtiquetteWarning
        if ep != nil || timecode != nil || warns {
            HStack(spacing: 4) {
                if let ep { MetaBadge(text: ep) }
                if let timecode { MetaBadge(text: timecode) }
                if warns {
                    MetaBadge(text: "注意礼仪", systemImage: "exclamationmark.triangle.fill", tint: .orange, prominent: true)
                }
            }
        }
    }
}

/// 点行の徽章（EP・タイムコード・礼仪注意）に共通の小さなカプセル。
private struct MetaBadge: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary
    var prominent = false

    var body: some View {
        HStack(spacing: 2) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(prominent ? tint : Color.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(prominent ? tint.opacity(0.15) : Color(.tertiarySystemFill), in: .capsule)
    }
}

/// 64×36 の点行サムネイル。無ければ主題色グラデーション＋灰色の photo 符号
/// （HomeBrowseView の `ThumbnailView` と違い、こちらは「剧照が無い」ことを主題色で示す——
/// 作品カードは既に 1 作品に絞られているので大面积主题色にはならない）。
private struct PointThumbnail: View {
    let url: URL?
    let gradient: LinearGradient

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(gradient)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
