//
//  PointCardSheet.swift
//  anitabi
//
//  地標カード（設計稿 1d / 2c）。この App の看板機能＝**対比撮影への入口**。档は**二段だけ**で、
//  一段式＝在場導航条、两段式＝カードの全部（高さは中身ぴったりに詰める）。対比撮影と画像
//  ビューアの `fullScreenCover` は**このカードの中身に付ける** —— 根に付けると sheet に隠れる。
//

import CoreLocation
import SwiftUI
import UIKit

struct PointCardSheet: View {

    let store: AnitabiStore
    /// カメラ・画像ビューアの呈现を握る（`$router.cameraSession` / `$router.photoViewer`）。
    @Bindable var router: AppRouter
    /// 副題の「· 距離」用。未測位なら距離だけ落として他は変えない。
    let locationProvider: LocationProvider
    let selection: PointSelection
    /// いま何段目か（設計稿 2c の三段）。頭部の形と剧照の高さがこれで変わる。
    var stage: SheetStage = .medium
    /// 作品 chip。カードを閉じてから作品カードを開くので、押した瞬間には何も起きない。
    var onSelectWork: (Int) -> Void
    var onClose: () -> Void

    @Environment(\.sheetBottomInset) private var sheetBottomInset

    /// 貢献フロー・出典リンクの呈现は router を介さずカード自身が持つ
    /// （他カードの呈现スタックへ影響させない）。
    @State private var safariItem: SafariItem?
    @State private var isShowingEtiquette = false

    private var point: ScenePoint? {
        store.pointsByBangumi[selection.bangumiID]?.first { $0.id == selection.id }
    }

    private var bangumi: BangumiLite? { store.bangumi(id: selection.bangumiID) }

    private var themeColor: Color { store.color(forBangumi: selection.bangumiID) }

    /// 剧照の原寸 URL（plan 変換なし）。対比撮影の参考図と全屏ビューアはどちらもこれを使う。
    private var originalImageURL: URL? {
        AnitabiImage.url(path: point?.image, plan: nil)
    }

    /// カード内の剧照は全幅（≒362pt）まで伸びる。CDN 上限は 512×288 なので h360 が実質の最大。
    private var cardImageURL: URL? {
        AnitabiImage.url(path: point?.image, plan: "h360")
    }

    /// データ完走前にこのカードへ深链で入った場合だけ骨架屏を出す（完走後に `point` が
    /// 見つからないのはデータ側の欠番なので、骨架を出し続けない）。
    private var isLoadingSkeleton: Bool {
        guard point == nil else { return false }
        switch store.phase {
        case .empty, .geometryOnly: return true
        case .complete, .failed: return false
        }
    }

    var body: some View {
        ScrollView {
            if isLoadingSkeleton {
                VStack(alignment: .leading, spacing: 0) {
                    CardHeaderSkeleton(isCompact: stage == .compact, onClose: onClose)
                        // 実物と同じく、一段式の実高は身份条の複製で測る。
                        .overlay(alignment: .top) {
                            CardHeaderSkeleton(isCompact: true, onClose: {}).compactHeightProbe(.point)
                        }
                    PointCardSkeleton()
                        .collapsedInCompactStage(stage)
                }
                .scenePadding(.horizontal)
                .sheetScrollBottomPadding(sheetBottomInset)
                .animatesSheetStage(stage)
            } else if let point {
                VStack(alignment: .leading, spacing: 0) {
                    header(point, isCompact: stage == .compact)
                        // 最小档は**一段式の在場導航条の実高**。中/大档では頭部の余白と部品が
                        // 変わるので、一段式の姿の複製を隠して置きそちらを測る。
                        .overlay(alignment: .top) { header(point, isCompact: true).compactHeightProbe(.point) }

                    VStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                        if point.needsEtiquetteWarning {
                            EtiquetteBar { isShowingEtiquette = true }
                        }
                        if cardImageURL != nil {
                            screenshotCard(point)
                        } else {
                            missingScreenshotCard(point)
                        }
                        actionRow(point)
                        if let note = point.note?.nilIfBlank {
                            noteBlock(note)
                        }
                        sourceRow(point)
                    }
                    .collapsedInCompactStage(stage)
                }
                .scenePadding(.horizontal)
                .sheetScrollBottomPadding(sheetBottomInset)
                // 中身の実高を档へ返す（RootView）。剧照・備考・礼儀条の有無で 100pt 近く変わるので、
                // 比率のままだと下の空きが点ごとにばらつく。三段式が無いので伸びぶんは 0。
                .fittedContentHeight(.point, stage: stage, expandedDelta: 0)
                .animatesSheetStage(stage)
            }
        }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
        .sheet(isPresented: $isShowingEtiquette) { EtiquetteSheet() }
        .fullScreenCover(item: $router.photoViewer) { item in
            ImageViewer(url: item.url, title: item.title)
        }
        // 看板機能の入口（対比撮影）。
        .fullScreenCover(item: $router.cameraSession) { session in
            SceneComparisonView(
                scenePhotoURL: session.photoURL,
                sceneName: session.name,
                sceneColor: session.themeHex.flatMap(UIColor.init(cssHex:)) ?? .anitabiNeutralTheme,
                sceneLocation: session.location
            )
        }
    }

    // MARK: - 1. 頭部（設計稿 2c）

    /// **1 つの容器のまま档を跨ぐ**頭部（一段式＝設計稿 2c 在場導航条、中/大档＝標題ブロック）。
    /// 位移感の要は器を入れ替えないこと —— 迷你剧照が抜けると標題ブロックが左端まで**滑って**
    /// 詰まり、行揃え・行距・余白の差はバネが補間する。入れ替わるのは避けようがない葉だけ
    /// （跑马灯 ↔ 2 行標題、meta ↔ 作品 chip、迷你剧照・共有の出入り）で、それらは原位で淡換する。
    private func header(_ point: ScenePoint, isCompact: Bool) -> some View {
        HStack(
            alignment: isCompact ? .center : .top,
            spacing: isCompact ? SheetMetrics.thumbnailGap : SheetMetrics.circleButtonGap
        ) {
            if isCompact {
                SceneThumbnail(url: point.thumbnailURL, size: SheetMetrics.miniThumbnailSize)
                    // 相棒は中/大档の**全幅剧照**。位置も大きさも別物すぎて繋げないので、
                    // 「大図の方向へ育ちながら淡出する」転場で繋がりだけ示す。錨は大図と同じ左上。
                    .transition(.scale(scale: 2, anchor: .topLeading).combined(with: .opacity))
            }

            VStack(
                alignment: .leading,
                spacing: isCompact ? SheetMetrics.rowTitleGap : SheetMetrics.titleSubtitleGap
            ) {
                // 標題の槽。一段式は 1 行で横に流し（`MarqueeText`）、中/大档は 2 行で折る。
                ZStack(alignment: .topLeading) {
                    if isCompact {
                        MarqueeText(text: pointName(point), font: SheetFont.titleCompactPoint)
                            .transition(.opacity)
                    } else {
                        Text(pointName(point))
                            .font(SheetFont.titleLarge)
                            .foregroundStyle(Color.anitabiInk)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                // 副題の槽。一段式は「作品名 · EP · 距離」の 1 行、中/大档は作品 chip ＋ meta。
                ZStack(alignment: .topLeading) {
                    if isCompact {
                        HStack(spacing: SheetMetrics.scaled(5)) {
                            ThemeDot(color: themeColor, size: SheetMetrics.dotSize)
                            Text(compactMetaText(point))
                                .lineLimit(1)
                        }
                        .font(SheetFont.meta)
                        .foregroundStyle(Color.anitabiInkSecondary)
                        .transition(.opacity)
                    } else {
                        HStack(spacing: SheetMetrics.scaled(6)) {
                            workChip
                            if !metaText(point).isEmpty {
                                Text(metaText(point))
                                    .font(SheetFont.rowMeta)
                                    .foregroundStyle(Color.anitabiInkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isCompact {
                ShareLink(
                    item: shareURL(point),
                    subject: Text(shareTitle(point)),
                    message: Text(shareTitle(point))
                ) {
                    CardCircleLabel(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            CardCloseButton(action: onClose)
        }
        .stageHeaderFrame(isCompact: isCompact)
    }

    private func pointName(_ point: ScenePoint) -> String {
        point.displayName.nilIfBlank ?? String(localized: "巡礼点")
    }

    /// 設計稿 1d/2c の作品 chip：主題色 18% の地 ＋ 主題色 50% の縁 ＋ 色点 ＋ 作品名 ＋ `›`。
    /// 系统の `.bordered` では主題色の枠にならないので自前。
    private var workChip: some View {
        Button {
            onSelectWork(selection.bangumiID)
        } label: {
            HStack(spacing: SheetMetrics.scaled(5)) {
                ThemeDot(color: themeColor, size: SheetMetrics.smallDotSize)
                Text(store.name(forBangumi: selection.bangumiID))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: SheetMetrics.scaled(8), weight: .bold))
            }
            .font(SheetFont.workChip)
            .foregroundStyle(Color.anitabiInk)
            .padding(.horizontal, SheetMetrics.scaled(9))
            .padding(.vertical, SheetMetrics.scaled(3))
            .background(themeColor.opacity(0.18), in: .capsule)
            .overlay { Capsule().strokeBorder(themeColor.opacity(0.5), lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    /// 設計稿 `· EP03 · 08:12 · 距我 1.2 km`（作品 chip の直後に続くので先頭にも区切りを置く）。
    /// EP／タイムコードは剧照の右下の徽章と二度書きになるので、剧照がある点では省く。
    private func metaText(_ point: ScenePoint) -> String {
        let parts = metaParts(point, includesEpisode: cardImageURL == nil)
        guard !parts.isEmpty else { return "" }
        return "· " + parts.joined(separator: " · ")
    }

    /// 一段式は作品名から続けて書くので前置きの区切りは無し。迷你サムネイルには徽章が
    /// 乗らないので、EP／タイムコードもこちらに書く。
    private func compactMetaText(_ point: ScenePoint) -> String {
        let parts = metaParts(point, includesEpisode: true)
        return ([store.name(forBangumi: selection.bangumiID)] + parts).joined(separator: " · ")
    }

    private func metaParts(_ point: ScenePoint, includesEpisode: Bool) -> [String] {
        var parts: [String] = []
        if includesEpisode {
            if let ep = point.episodeBadge { parts.append(ep) }
            if let timecode = point.timecodeText { parts.append(timecode) }
        }
        if let distance = distanceText(point) { parts.append(distance) }
        return parts
    }

    private func distanceText(_ point: ScenePoint) -> String? {
        guard let here = locationProvider.location else { return nil }
        let meters = here.distance(from: CLLocation(latitude: point.lat, longitude: point.lng))
        return String(localized: "距我 \(DistanceFormatter.string(meters: meters))")
    }

    // MARK: - 2. 剧照（設計稿 2c：全幅・右下に等幅の EP 徽章）

    /// 剧照の高さ。このカードは两段式までなので**档で変わらない**。
    private var mediaHeight: CGFloat { SheetMetrics.mediaHeightMedium }

    private func screenshotCard(_ point: ScenePoint) -> some View {
        Button {
            guard let url = originalImageURL else { return }
            router.photoViewer = PhotoViewerItem(url: url, title: point.displayName.nilIfBlank)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color.anitabiMediaPlaceholder)
                    .overlay {
                        RemoteImage(url: cardImageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .imageScale(.large)
                                    .foregroundStyle(Color.anitabiInkFaint)
                            case .empty:
                                // 読み込み中は骨架の掃過。菊花（ProgressView）より地と馴染む。
                                Color.anitabiMediaPlaceholder
                                    .anitabiSkeletonShimmer()
                            }
                        }
                    }
                    .frame(height: mediaHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: SheetMetrics.mediaRadius, style: .continuous))

                overlayBadge(point)
                    .padding(SheetMetrics.scaled(10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SheetMetrics.mediaRadius, style: .continuous)
                    .strokeBorder(Color.anitabiSurfaceStroke, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看截图")
    }

    /// 設計稿は `EP03 08:12` を 1 枚の等幅徽章にまとめている（区切りは空白）。
    @ViewBuilder
    private func overlayBadge(_ point: ScenePoint) -> some View {
        let badges = [point.episodeBadge, point.timecodeText].compactMap { $0 }
        if !badges.isEmpty {
            MediaBadge(text: badges.joined(separator: " "))
        }
    }

    /// 剧照が無い点。ここが Web への貢献導線の主戦場なので、空白ではなく誘導カードを出す。
    private func missingScreenshotCard(_ point: ScenePoint) -> some View {
        VStack(spacing: SheetMetrics.scaled(10)) {
            Image(systemName: "photo.badge.plus")
                .font(SheetFont.titleLarge)
                .foregroundStyle(Color.anitabiInkTertiary)
            // 一行で言い切る短さに保つ —— 折り返すと下の釦を押し出す。
            Text("还没有截图")
                .font(SheetFont.rowTitle)
                .foregroundStyle(Color.anitabiInk)
            Button("补传截图") {
                safariItem = SafariItem(url: AnitabiWebLink.createPoint(point: point, bangumi: bangumi))
            }
            // すぐ下に並ぶ動作排と同じ寸法。chip 級に落とすと一段小さく見える。
            .buttonStyle(AnitabiCapsuleStyle(kind: .primary, size: .action))
        }
        // 高さは剧照と**同じ**にする。内容から作ると点を切り替えるたびにカードの背丈と
        // 動作排の位置が跳ねる。
        .frame(maxWidth: .infinity)
        .frame(height: mediaHeight)
        .anitabiPanel(radius: SheetMetrics.mediaRadius)
    }

    // MARK: - 3. 動作排（設計稿 2c：`flex 1.4 / 1 / 1` ＋ 幅 44 の「⋯」）

    private func actionRow(_ point: ScenePoint) -> some View {
        WeightedRow(spacing: SheetMetrics.itemSpacing, weights: originalImageURL == nil ? [1, 1, 0] : [1.4, 1, 1, 0]) {
            if let photoURL = originalImageURL {
                Button {
                    startComparison(point, photoURL: photoURL)
                } label: {
                    // 設計稿の `📷` は落とす —— 横は設計稿より詰まるので、記号より語に幅を渡す。
                    Text("做对比图")
                }
                .buttonStyle(AnitabiCapsuleStyle(kind: .primary, fullWidth: true, fillsRowHeight: true))
            }

            Button {
                AnitabiWebLink.openExternally(AnitabiWebLink.googleMaps(lat: point.lat, lng: point.lng))
            } label: {
                Text("地图")
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, fullWidth: true, fillsRowHeight: true))

            Button {
                AnitabiWebLink.openExternally(AnitabiWebLink.streetView(lat: point.lat, lng: point.lng))
            } label: {
                Text("街景")
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, fullWidth: true, fillsRowHeight: true))

            moreMenu(point)
                .frame(width: SheetMetrics.moreTileWidth)
        }
    }

    /// 対比撮影へ渡す 4 つ。`location` は成片の右下に等幅で焼き込まれる文字列。
    private func startComparison(_ point: ScenePoint, photoURL: URL) {
        router.cameraSession = CameraSession(
            photoURL: photoURL,
            name: point.displayName.nilIfBlank ?? store.name(forBangumi: point.bangumiID),
            themeHex: bangumi?.colorHex?.nilIfBlank,
            location: String(format: "%.6f,%.6f", point.lat, point.lng)
        )
    }

    private func shareURL(_ point: ScenePoint) -> URL {
        AnitabiWebLink.canonical(
            bangumiID: point.bangumiID,
            pointID: point.id,
            coordinate: point.coordinate
        )
    }

    private func shareTitle(_ point: ScenePoint) -> String {
        let name = point.displayName.nilIfBlank ?? String(localized: "巡礼点")
        return String(localized: "\(name)｜《\(store.name(forBangumi: point.bangumiID))》的巡礼点")
    }

    // MARK: - 4. 備考（設計稿 2c：白 40% の地・角丸 14・行間 1.7）

    private func noteBlock(_ note: String) -> some View {
        Text(note)
            .font(SheetFont.note)
            .foregroundStyle(Color.anitabiInkSecondary)
            .lineSpacing(SheetMetrics.noteLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetMetrics.scaled(12))
            .padding(.vertical, SheetMetrics.scaled(10))
            .anitabiPanel(radius: SheetMetrics.tileRadius, fill: .anitabiSubtle, stroke: .clear)
    }

    // MARK: - 5. 出典行

    /// Web 版 `ns()` の移植：`origin` 文字列 → `@ニックネーム` → 「地図インポート」→ 非表示。
    /// リンクは `originLink` 優先、無ければ `mid`（Google マイマップ）から組む。
    @ViewBuilder
    private func sourceRow(_ point: ScenePoint) -> some View {
        if let source = sourceInfo(point) {
            if let url = source.url {
                Button {
                    safariItem = SafariItem(url: url)
                } label: {
                    HStack(spacing: SheetMetrics.scaled(4)) {
                        Text(source.text)
                        Text("查看原始链接")
                            .underline()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: SheetMetrics.scaled(8), weight: .bold))
                    }
                    .font(SheetFont.meta)
                    .foregroundStyle(Color.anitabiInkTertiary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Text(source.text)
                    .font(SheetFont.meta)
                    .foregroundStyle(Color.anitabiInkTertiary)
            }
        }
    }

    private func sourceInfo(_ point: ScenePoint) -> (text: String, url: URL?)? {
        let midURL = point.mid?.nilIfBlank.map {
            AnitabiWebLink.myMapsViewer(mid: $0, lat: point.lat, lng: point.lng)
        }
        let link = point.originLink?.nilIfBlank.flatMap { URL(string: $0) } ?? midURL

        if let origin = point.origin?.nilIfBlank {
            return (String(localized: "来源：\(origin)"), link)
        }
        if let uid = point.uid, let nickname = store.userNickname(uid)?.nilIfBlank {
            return (String(localized: "由 @\(nickname) 贡献"), nil)
        }
        if midURL != nil {
            return (String(localized: "来源：地图导入"), midURL)
        }
        return nil
    }

    // MARK: - 6. 「更多」メニュー（動作排の末尾タイル）

    /// 貢献フロー（补传截图 / 修正坐标）＋ 在网页版打开 ＋ 拷贝坐标。
    /// 設計稿 2c は同じ 4 つをカード末尾にも並べているが、同じ動作への入口は 1 つに絞る。
    private func moreMenu(_ point: ScenePoint) -> some View {
        Menu {
            Button("补传截图", systemImage: "photo.badge.plus") {
                safariItem = SafariItem(url: AnitabiWebLink.createPoint(point: point, bangumi: bangumi))
            }
            Button("修正坐标", systemImage: "mappin.and.ellipse") {
                safariItem = SafariItem(url: AnitabiWebLink.fixPointGPS(point: point, bangumi: bangumi))
            }
            Button("在网页版打开", systemImage: "safari") {
                safariItem = SafariItem(url: AnitabiWebLink.canonical(
                    bangumiID: point.bangumiID,
                    pointID: point.id,
                    coordinate: point.coordinate
                ))
            }
            Button("拷贝坐标", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = String(format: "%.6f,%.6f", point.lat, point.lng)
                router.toast.show(String(localized: "已拷贝坐标"), symbol: "doc.on.doc")
            }
        } label: {
            // 隣の「地图」「街景」と**同じ面**（`AnitabiCapsuleFace`）で組む —— 自前で
            // padding を書くと、記号の行高が字より低いぶんこのタイルだけ背が低くなる。
            AnitabiCapsuleFace(kind: .secondary, size: .action, fullWidth: true, fillsRowHeight: true) {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityLabel("更多")
    }
}
