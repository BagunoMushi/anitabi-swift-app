//
//  PointCardSheet.swift
//  anitabi
//
//  地標カード。設計稿 1d（核心页）と 2c（三段式）をそのまま写す。この App の看板機能
//  ＝**対比撮影への入口**でもある。
//
//  档は**二段だけ**（同指示 2026-08-09：「这个页面只允许一段二段」。設計稿 2c の三段式は採らない）：
//  - 一段式 = **在場導航条**。迷你剧照 ＋ 点名 ＋ 作品/EP/距離の 1 行だけ。地図で道を探す用。
//  - 两段式 = 礼儀警示 ＋ 剧照大図（180）＋ 動作排 ＋ 備考 ＋ 出典。カードの全部がここに出る。
//    高さは**中身ぴったり**（`fittedContentHeight` → `SheetLayer.initialHeight`）で、
//    設計稿の比率 53.1% はその上限。備考が長い点だけがこの中でスクロールする。
//
//  呈现の要点：対比撮影（横屏）と画像ビューアの `fullScreenCover` は
//  **このカードの中身に付ける**。3 枚重なった sheet の上を覆えるのはここから出した
//  呈现だけで、根（RootView）側に付けると常駐 sheet に隠れてしまう。
//
//  外部リンクの出し分け：
//  - 貢献フロー（补传截图 / 修正坐标 / 网页版）＋出典リンク → `SFSafariViewController`
//    （端末 Safari と Cookie を共有するのでログイン状態がそのまま使える）
//  - Google マップ / 街景 → `UIApplication.open`（Google Maps アプリが入っていれば
//    universal link でそちらが開く。SFSafari の中では絶対にアプリへ渡らない）
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

    /// 貢献フロー・出典リンクの SFSafariViewController。他カードの呈现スタックへ影響させないよう
    /// router ではなくカード自身で持つ（`WorkCardSheet` と同じ方針）。
    /// sheet の中身は底部安全区を無効にしてあるので、列の末尾だけ自分で足し戻す。
    @Environment(\.sheetBottomInset) private var sheetBottomInset

    @State private var safariItem: SafariItem?
    @State private var isShowingEtiquette = false

    /// テーマ色が取れない作品の代替（`ColorUtilities.anitabiNeutralTheme` と同値）。
    /// `SceneComparisonView` の `sceneColor` は非オプショナルなので、ここで必ず埋める。
    private static let fallbackThemeHex = "8A8A6F"

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

    var body: some View {
        ScrollView {
            if let point {
                VStack(alignment: .leading, spacing: 0) {
                    header(point)
                        // 最小档は**一段式の在場導航条の実高**。中/大档では頭部が別の形に
                        // 変わるので、一段式の複製を高さ 0 の枠に隠してそちらを測る。
                        .overlay(alignment: .top) { compactHeaderProbe(point) }

                    // 一段式では身份条より下を**描かない**。sheet の中身は底部安全区の下にも
                    // 描かれるので、高さを身份条ぴったりにしても次の節がホームインジケータ帯に覗く。
                    // 判定は生の sheet 高さ由来（RootView）なので、拖动に即座に追従する。
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
                    // 一段式では中身を**レイアウトからも外す**（高さ 0 に畳む）。opacity だけで
                    // 隠していた版は、見えないまま場所を要求し続ける —— sheet の高さが足りないぶんを
                    // SwiftUI が身份条の余白から削るので、カードごとに 3〜10pt 潰れて
                    // 「首页の検索だけ上、他の 2 枚は下」という食い違いになっていた（実測）。
                    .frame(height: stage == .compact ? 0 : nil, alignment: .top)
                    .clipped()
                    .allowsHitTesting(stage != .compact)
                }
                .scenePadding(.horizontal)
                .padding(.bottom, SheetMetrics.scrollBottomPadding + sheetBottomInset)
                // 中身の実高を档へ返す（RootView）。剧照・備考・礼儀条の有無で 100pt 近く変わるので、
                // 設計稿の比率のままだと下の空きが点ごとにばらつく。
                // このカードは档で高さの変わる要素を持たない（三段式が無い）ので伸びぶんは 0。
                .fittedContentHeight(.point, stage: stage, expandedDelta: 0)
                .animation(.anitabiSpring, value: stage)
            }
        }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
        .sheet(isPresented: $isShowingEtiquette) { EtiquetteSheet() }
        .fullScreenCover(item: $router.photoViewer) { item in
            ImageViewer(url: item.url, title: item.title)
        }
        // 看板機能の入口。既存の 4 引数 init へ 1:1 で渡すだけ（撮影画面側は一切触らない）。
        .fullScreenCover(item: $router.cameraSession) { session in
            SceneComparisonView(
                scenePhotoURL: session.photoURL,
                sceneName: session.name,
                sceneColor: session.themeHex ?? Self.fallbackThemeHex,
                sceneLocation: session.location
            )
        }
    }

    // MARK: - 1. 頭部（設計稿 2c）

    /// 一段式の身份条は上下の余白まで自前で持つ（`compactBarRow`）。中/大档の頭部だけが
    /// カード共通の上余白（抓手の下 ＋ 8px）と、その下の節との間隔を足す。
    @ViewBuilder
    private func header(_ point: ScenePoint) -> some View {
        if stage == .compact {
            compactHeader(point)
        } else {
            fullHeader(point)
                .padding(.top, SheetMetrics.topInset)
                .padding(.bottom, SheetMetrics.headerBottomSpacing)
        }
    }

    /// 設計稿 2c 一段式の在場導航条：`56×42` の迷你剧照 ＋ 点名 ＋ 1 行の meta ＋ ✕。
    private func compactHeader(_ point: ScenePoint) -> some View {
        HStack(alignment: .center, spacing: SheetMetrics.thumbnailGap) {
            SceneThumbnail(url: point.thumbnailURL, size: SheetMetrics.miniThumbnailSize)
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                // 一段式は 1 行しか無いので、長い点名は `…` に切らず横に流す（`MarqueeText`）。
                MarqueeText(text: pointName(point), font: SheetFont.titleCompactPoint)
                HStack(spacing: SheetMetrics.scaled(5)) {
                    ThemeDot(color: themeColor, size: SheetMetrics.dotSize)
                    Text(compactMetaText(point))
                        .lineLimit(1)
                }
                .font(SheetFont.meta)
                .foregroundStyle(Color.anitabiInkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CardCloseButton(action: onClose)
        }
        // 迷你条の行高は 4 枚のカードで共通（`compactBarRow`）。迷你剧照もこの高さに合わせてある。
        .compactBarRow()
    }

    /// 一段式の実高だけを測るための不可視の複製（レイアウトには効かせない）。
    private func compactHeaderProbe(_ point: ScenePoint) -> some View {
        compactHeader(point)
            .environment(\.isMarqueeEnabled, false)
            .fixedSize(horizontal: false, vertical: true)
            .compactContentHeight(.point)
            .hidden()
            .frame(height: 0, alignment: .top)
    }

    /// 設計稿 2c 两段式／三段式：標題ブロック（18px/900 ＋ 作品 chip ＋ meta）＋ 共有 ◯ ＋ ✕。
    private func fullHeader(_ point: ScenePoint) -> some View {
        CardHeader(title: pointName(point), titleFont: SheetFont.titleLarge, onClose: onClose) {
            ShareLink(
                item: shareURL(point),
                subject: Text(shareTitle(point)),
                message: Text(shareTitle(point))
            ) {
                CardCircleLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享")
        } subtitle: {
            HStack(spacing: SheetMetrics.scaled(6)) {
                workChip
                if !metaText(point).isEmpty {
                    Text(metaText(point))
                        .font(SheetFont.rowMeta)
                        .foregroundStyle(Color.anitabiInkSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func pointName(_ point: ScenePoint) -> String {
        point.displayName.nilIfBlank ?? String(localized: "巡礼点")
    }

    /// 設計稿 1d/2c の作品 chip：主題色 18% の地 ＋ 主題色 50% の縁 ＋ 色点 ＋ 作品名 ＋ `›`。
    /// 系统の `.bordered` では主題色の枠にならないので自前で組む。
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

    /// 設計稿 `EP03 · 08:12 · 距我 1.2 km`。作品 chip の直後に続けるので先頭にも区切りを置く。
    private func metaText(_ point: ScenePoint) -> String {
        let parts = metaParts(point)
        guard !parts.isEmpty else { return "" }
        return "· " + parts.joined(separator: " · ")
    }

    /// 一段式は作品名から続けて書くので区切りの前置きは付けない。
    private func compactMetaText(_ point: ScenePoint) -> String {
        ([store.name(forBangumi: selection.bangumiID)] + metaParts(point)).joined(separator: " · ")
    }

    private func metaParts(_ point: ScenePoint) -> [String] {
        var parts: [String] = []
        if let ep = point.episodeBadge { parts.append(ep) }
        if let timecode = point.timecodeText { parts.append(timecode) }
        if let distance = distanceText(point) { parts.append(distance) }
        return parts
    }

    private func distanceText(_ point: ScenePoint) -> String? {
        guard let here = locationProvider.location else { return nil }
        let meters = here.distance(from: CLLocation(latitude: point.lat, longitude: point.lng))
        return String(localized: "距我 \(DistanceFormatter.string(meters: meters))")
    }

    // MARK: - 2. 剧照（設計稿 2c：全幅・两段式 180 / 三段式 280・右下に等幅の EP 徽章）

    /// 剧照の高さ。このカードは两段式までなので**档で変わらない**（設計稿 2c 三段式の 280 は使わない）。
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
                                ProgressView()
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
            Text("这个点还没有截图")
                .font(SheetFont.rowTitle)
                .foregroundStyle(Color.anitabiInk)
            Button("补传截图") {
                safariItem = SafariItem(url: AnitabiWebLink.createPoint(point: point, bangumi: bangumi))
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .primary, size: .chip))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SheetMetrics.scaled(24))
        .anitabiPanel(radius: SheetMetrics.mediaRadius)
    }

    // MARK: - 3. 動作排（設計稿 2c：`flex 1.4 / 1 / 1` ＋ 幅 44 の「⋯」）

    private func actionRow(_ point: ScenePoint) -> some View {
        WeightedRow(spacing: SheetMetrics.itemSpacing, weights: originalImageURL == nil ? [1, 1, 0] : [1.4, 1, 1, 0]) {
            if let photoURL = originalImageURL {
                Button {
                    startComparison(point, photoURL: photoURL)
                } label: {
                    // 設計稿は `📷 做对比图` と記号を添えているが、記号ぶんの幅が無い
                    // （横は設計稿より詰まる —— `DesignScale` 参照）。この枠でいちばん大事なのは
                    // 語そのものなので、記号を落として字に幅を全部渡す。
                    Text("做对比图")
                }
                .buttonStyle(AnitabiCapsuleStyle(kind: .primary, fullWidth: true, fillsRowHeight: true))
            }

            Button {
                open(AnitabiWebLink.googleMaps(lat: point.lat, lng: point.lng))
            } label: {
                Text("地图")
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, fullWidth: true, fillsRowHeight: true))

            Button {
                open(AnitabiWebLink.streetView(lat: point.lat, lng: point.lng))
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
    ///
    /// 設計稿 2c の三段式には同じ 4 つがカードの末尾にカプセル 3 枚として並んでいたが、
    /// **この ⋯ と丸ごと重複する**ので原生版では持たない（同じ動作への入口は 1 つ）。
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
            // 隣の「地图」「街景」と**同じ面**（`AnitabiCapsuleFace`）で組む。
            // 自前で padding と地を書いていた頃は、記号の高さが字の行高より低いぶんだけ
            // このタイルだけ背が低かった。
            AnitabiCapsuleFace(kind: .secondary, size: .action, fullWidth: true, fillsRowHeight: true) {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityLabel("更多")
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
