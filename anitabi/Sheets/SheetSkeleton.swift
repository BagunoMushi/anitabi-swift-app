//
//  SheetSkeleton.swift
//  anitabi
//
//  下拉カードの骨架屏（スケルトン）。初回起動〜データ完走までの空窗（`DataLoadPhase.empty` /
//  `.geometryOnly`）にだけ出す —— 完走後の検索・附近はメモリ上で同期に返るので骨架は不要。
//  積木（bar / box / row）は実物と**同じ寸法トークン**で組む：骨架 → 実物の差し替えで
//  行の高さが跳ねないようにするため。掃過アニメは器 1 つにつき 1 回だけ掛ける。
//

import SwiftUI

// MARK: - 掃過アニメ

extension View {
    /// 骨架屏の掃過高光。**骨架の器（節や列の根）につき 1 回**だけ掛ける —— 部品ごとに掛けると
    /// 掃過の位相がばらけて見える上、アニメの本数ぶん描画も増える。
    /// 「視差を減らす」設定では掃過を止め、静止した地だけ残す。
    func anitabiSkeletonShimmer() -> some View {
        modifier(SkeletonShimmer())
    }
}

private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let band = max(proxy.size.width * 0.45, 1)
                        LinearGradient(
                            colors: [.clear, .anitabiSkeletonHighlight, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: sweep ? proxy.size.width : -band)
                    }
                    // 高光は骨架の形の中だけに見せる（角丸の外へはみ出させない）。
                    .mask { content }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
    }
}

// MARK: - 積木

/// 文字 1 行ぶんの骨架。`width`/`height` は**設計稿の px**（`scaled` はこの中で掛ける）。
/// `width: nil` は行幅いっぱい（分段控件・剧照など幅が器で決まる部品）。
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat

    var body: some View {
        Capsule()
            .fill(Color.anitabiMediaPlaceholder)
            .frame(width: width.map { SheetMetrics.scaled($0) }, height: SheetMetrics.scaled(height))
    }
}

/// 図（サムネイル・剧照）の骨架。寸法は実物と同じ `SheetMetrics` のトークンを**そのまま**渡す。
struct SkeletonBox: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat

    init(size: CGSize, radius: CGFloat) {
        self.width = size.width
        self.height = size.height
        self.radius = radius
    }

    /// 行幅いっぱいの版（地標カードの剧照）。
    init(height: CGFloat, radius: CGFloat) {
        self.width = nil
        self.height = height
        self.radius = radius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.anitabiMediaPlaceholder)
            .frame(width: width, height: height)
    }
}

/// 一覧行の骨架（附近行・作品行・点行が共有）。サムネイル寸法だけ実物のトークンを渡し、
/// 文字は 2 行ぶんの bar で置き換える。`titleWidth` は設計稿の px。
struct SkeletonRow: View {
    var thumbnail: CGSize
    var radius: CGFloat
    var titleWidth: CGFloat
    /// 行末の距離（附近行）を持つ行だけ true。
    var showsTrailing = false

    var body: some View {
        HStack(spacing: SheetMetrics.thumbnailGap) {
            SkeletonBox(size: thumbnail, radius: radius)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                SkeletonBar(width: titleWidth, height: 12)
                SkeletonBar(width: titleWidth * 0.62, height: 9)
            }
            Spacer(minLength: 0)
            if showsTrailing {
                SkeletonBar(width: 34, height: 10)
            }
        }
        .padding(.vertical, SheetMetrics.rowVerticalPadding)
    }
}

/// 節見出しの骨架（13px の見出し 1 行ぶん）。
private struct SkeletonSectionHeader: View {
    var body: some View {
        SkeletonBar(width: 76, height: 11)
            .padding(.horizontal, SheetMetrics.headerInset)
    }
}

// MARK: - カード頭部の骨架

/// 作品・地標カードの頭部（標題＋副題＋✕）の骨架。✕ は実物 —— 読み込み中でもカードは
/// 閉じられなければならない。枠は実物と同じ `stageHeaderFrame` を通す。
struct CardHeaderSkeleton: View {
    var isCompact = false
    var onClose: () -> Void

    var body: some View {
        HStack(
            alignment: isCompact ? .center : .top,
            spacing: SheetMetrics.circleButtonGap
        ) {
            VStack(
                alignment: .leading,
                spacing: isCompact ? SheetMetrics.rowTitleGap : SheetMetrics.titleSubtitleGap
            ) {
                SkeletonBar(width: 160, height: 14)
                SkeletonBar(width: 110, height: 9)
            }
            .anitabiSkeletonShimmer()
            .frame(maxWidth: .infinity, alignment: .leading)

            CardCloseButton(action: onClose)
        }
        .stageHeaderFrame(isCompact: isCompact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("加载中")
    }
}

// MARK: - 首页（HomeBrowseView の中身）

/// 首页ブラウズの骨架：附近 3 行 ＋ 作品浏览 5 行 ＋ 热门城市 6 タイル。
/// 列の順・節間の余白は実物（`HomeBrowseView`）と同じ。
struct HomeBrowseSkeleton: View {
    /// 行ごとに標題 bar の幅を揺らして「文字が入る」気配を出す（設計稿の px）。
    private static let nearbyTitleWidths: [CGFloat] = [128, 96, 148]
    private static let workTitleWidths: [CGFloat] = [150, 104, 168, 128, 92]

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: SheetMetrics.itemSpacing), count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
            // 附近的巡礼点
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SkeletonSectionHeader()
                SheetListCard {
                    ForEach(Array(Self.nearbyTitleWidths.enumerated()), id: \.offset) { index, width in
                        if index > 0 {
                            SheetHairline(leadingInset: NearbyPointRow.textInset)
                        }
                        SkeletonRow(
                            thumbnail: SheetMetrics.sceneThumbnailSize,
                            radius: SheetMetrics.sceneThumbnailRadius,
                            titleWidth: width,
                            showsTrailing: true
                        )
                    }
                }
            }

            // 作品浏览（見出し ＋ 分段控件 ＋ 一覧）
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SkeletonSectionHeader()
                SkeletonBar(width: nil, height: 26)
                SheetListCard {
                    ForEach(Array(Self.workTitleWidths.enumerated()), id: \.offset) { index, width in
                        if index > 0 {
                            SheetHairline(leadingInset: SheetMetrics.coverSize.width + SheetMetrics.thumbnailGap)
                        }
                        SkeletonRow(
                            thumbnail: SheetMetrics.coverSize,
                            radius: SheetMetrics.coverRadius,
                            titleWidth: width
                        )
                    }
                }
            }

            // 热门城市（3 列 × 2 行）
            VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
                SkeletonSectionHeader()
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: SheetMetrics.itemSpacing) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: SheetMetrics.scaled(4)) {
                            SkeletonBar(width: 44, height: 12)
                            SkeletonBar(width: 56, height: 9)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SheetMetrics.scaled(12))
                        .padding(.vertical, SheetMetrics.scaled(10))
                        .anitabiPanel(radius: SheetMetrics.tileRadius)
                    }
                }
            }
        }
        .anitabiSkeletonShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("加载中")
    }
}

// MARK: - 作品カード（頭部より下）

/// 作品カードの骨架：情報カード ＋ 分组控件行 ＋ 点行 6 行。
struct WorkCardSkeleton: View {
    private static let rowTitleWidths: [CGFloat] = [150, 104, 168, 122, 88, 140]

    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
            SheetGroupCard {
                HStack(alignment: .center, spacing: SheetMetrics.thumbnailGap) {
                    SkeletonBox(size: SheetMetrics.infoCoverSize, radius: SheetMetrics.infoCoverRadius)
                    VStack(alignment: .leading, spacing: SheetMetrics.scaled(6)) {
                        SkeletonBar(width: 140, height: 10)
                        SkeletonBar(width: 90, height: 9)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: SheetMetrics.itemSpacing) {
                SkeletonBar(width: nil, height: 26)
                SkeletonBar(width: 64, height: 26)
            }

            SheetListCard {
                ForEach(Array(Self.rowTitleWidths.enumerated()), id: \.offset) { index, width in
                    if index > 0 {
                        SheetHairline(leadingInset: SheetMetrics.pointThumbnailSize.width + SheetMetrics.thumbnailGap)
                    }
                    SkeletonRow(
                        thumbnail: SheetMetrics.pointThumbnailSize,
                        radius: SheetMetrics.pointThumbnailRadius,
                        titleWidth: width
                    )
                }
            }
        }
        .anitabiSkeletonShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("加载中")
    }
}

// MARK: - 地標カード（頭部より下）

/// 地標カードの骨架：全幅の剧照 ＋ 動作排 ＋ 出典行。剧照の高さは実物と同じ
/// `mediaHeightMedium` —— ここが跳ねるとカードの档（`fittedContentHeight`）まで揺れる。
struct PointCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
            SkeletonBox(height: SheetMetrics.mediaHeightMedium, radius: SheetMetrics.mediaRadius)

            HStack(spacing: SheetMetrics.itemSpacing) {
                SkeletonBar(width: nil, height: 37)
                SkeletonBar(width: nil, height: 37)
                SkeletonBar(width: nil, height: 37)
                SkeletonBar(width: 44, height: 37)
            }

            SkeletonBar(width: 180, height: 9)
        }
        .anitabiSkeletonShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("加载中")
    }
}
