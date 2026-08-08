//
//  PointCardSheet.swift
//  anitabi
//
//  地標カード。Apple マップの「地点カード」に相当する最下層の 1 枚で、
//  この App の看板機能＝**対比撮影への入口**でもある。
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
    /// 作品 chip。カードを閉じてから作品カードを開くので、押した瞬間には何も起きない。
    var onSelectWork: (Int) -> Void
    var onClose: () -> Void

    /// 貢献フロー・出典リンクの SFSafariViewController。他カードの呈现スタックへ影響させないよう
    /// router ではなくカード自身で持つ（`WorkCardSheet` と同じ方針）。
    @State private var safariItem: SafariItem?
    @State private var isShowingEtiquette = false

    /// テーマ色が取れない作品の代替（`ColorUtilities.anitabiNeutralTheme` と同値）。
    /// `SceneComparisonView` の `sceneColor` は非オプショナルなので、ここで必ず埋める。
    private static let fallbackThemeHex = "8A8A6F"

    private var point: ScenePoint? {
        store.pointsByBangumi[selection.bangumiID]?.first { $0.id == selection.id }
    }

    private var bangumi: BangumiLite? { store.bangumi(id: selection.bangumiID) }

    /// 剧照の原寸 URL（plan 変換なし）。対比撮影の参考図と全屏ビューアはどちらもこれを使う。
    private var originalImageURL: URL? {
        AnitabiImage.url(path: point?.image, plan: nil)
    }

    /// カード内の剧照は 256pt 幅上限なので、@3x でも 768px。CDN 上限（512×288）に対して
    /// h360 が実質の最大解像度になる。
    private var cardImageURL: URL? {
        AnitabiImage.url(path: point?.image, plan: "h360")
    }

    var body: some View {
        ScrollView {
            if let point {
                VStack(alignment: .leading, spacing: 20) {
                    titleRow(point)
                    subtitleRow(point)
                    if point.needsEtiquetteWarning {
                        etiquetteChip
                    }
                    if cardImageURL != nil {
                        screenshotCard(point)
                    } else {
                        missingScreenshotCard(point)
                    }
                    actionRow(point)
                    if let note = point.note?.nilIfBlank {
                        Text(note)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sourceRow(point)
                }
                .padding(.horizontal, 16)
                // 最小档 96pt がちょうど見出し行だけ見える高さ。この上余白込みの数値。
                .padding(.top, 20)
                .padding(.bottom, 24)
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

    // MARK: - 1. 見出し行

    private func titleRow(_ point: ScenePoint) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(point.displayName.nilIfBlank ?? "巡礼点")
                .font(.title2.bold())
                .lineLimit(2)
            Spacer(minLength: 8)
            moreMenu(point)
            CardCloseButton(action: onClose)
        }
    }

    // MARK: - 2. 副題行

    private func subtitleRow(_ point: ScenePoint) -> some View {
        HStack(spacing: 6) {
            workChip
            if !metaText(point).isEmpty {
                Text(metaText(point))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var workChip: some View {
        Button {
            onSelectWork(selection.bangumiID)
        } label: {
            HStack(spacing: 6) {
                workChipIcon
                Text(store.name(forBangumi: selection.bangumiID))
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// 16pt の丸いカバー。無い作品はテーマ色グラデーションのまま（文字は置かない——硬約束）。
    private var workChipIcon: some View {
        Circle()
            .fill(bangumi?.themeGradient
                  ?? LinearGradient(colors: [store.color(forBangumi: selection.bangumiID)],
                                    startPoint: .top, endPoint: .bottom))
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
            .frame(width: 16, height: 16)
    }

    /// `· EP 3 · 1:23 · 350 m`。作品 chip の直後に続けるので先頭にも区切りを置く。
    private func metaText(_ point: ScenePoint) -> String {
        var parts: [String] = []
        if let ep = point.episodeBadge { parts.append(ep) }
        if let timecode = point.timecodeText { parts.append(timecode) }
        if let distance = distanceText(point) { parts.append(distance) }
        guard !parts.isEmpty else { return "" }
        return "· " + parts.joined(separator: " · ")
    }

    private func distanceText(_ point: ScenePoint) -> String? {
        guard let here = locationProvider.location else { return nil }
        let meters = here.distance(from: CLLocation(latitude: point.lat, longitude: point.lng))
        return DistanceFormatter.string(meters: meters)
    }

    // MARK: - 3. 礼仪警告

    private var etiquetteChip: some View {
        Button {
            isShowingEtiquette = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("注意巡礼礼仪")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. 剧照カード

    /// 剧照は CDN 上限 512×288。全幅に引き伸ばすと必ず粗が出るので **256pt で頭打ち**にして
    /// 中央へ置き、余った左右は器の地（`.tertiarySystemFill`）を見せる。
    private func screenshotCard(_ point: ScenePoint) -> some View {
        Button {
            guard let url = originalImageURL else { return }
            router.photoViewer = PhotoViewerItem(url: url, title: point.displayName.nilIfBlank)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color(.quaternarySystemFill))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: cardImageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .imageScale(.large)
                                    .foregroundStyle(.secondary)
                            default:
                                ProgressView()
                            }
                        }
                    }
                    .clipShape(ConcentricRectangle(corners: .concentric(minimum: 12)))

                overlayBadges(point)
                    .padding(6)
            }
            .frame(maxWidth: 256)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemFill), in: ConcentricRectangle(corners: .concentric(minimum: 16)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看截图")
    }

    /// 剧照の右下に重ねる EP／タイムコード。白抜き＋黒地は画像の上でしか使わない配色
    /// （`HomeBrowseView` の附近行サムネイルと同じ）。
    @ViewBuilder
    private func overlayBadges(_ point: ScenePoint) -> some View {
        let badges = [point.episodeBadge, point.timecodeText].compactMap { $0 }
        if !badges.isEmpty {
            HStack(spacing: 4) {
                ForEach(badges, id: \.self) { text in
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 4))
                }
            }
        }
    }

    /// 剧照が無い点。ここが Web への貢献導線の主戦場なので、空白ではなく誘導カードを出す。
    private func missingScreenshotCard(_ point: ScenePoint) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("这个点还没有截图")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("补传截图") {
                safariItem = SafariItem(url: AnitabiWebLink.createPoint(point: point, bangumi: bangumi))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 16)
        .background(Color(.tertiarySystemFill), in: ConcentricRectangle(corners: .concentric(minimum: 16)))
    }

    // MARK: - 5. 動作排

    /// Apple マップの地点カードと同じ**横並びの小さなカプセル**。等幅に引き伸ばさず、
    /// 内容ぶんの幅で並べて、入り切らなければ行ごと横スクロールする
    /// （大きな色面は Apple の地点カードには存在しない）。
    private func actionRow(_ point: ScenePoint) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let photoURL = originalImageURL {
                    Button {
                        startComparison(point, photoURL: photoURL)
                    } label: {
                        actionPill("camera.viewfinder", "做对比图", prominent: true)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    open(AnitabiWebLink.googleMaps(lat: point.lat, lng: point.lng))
                } label: {
                    actionPill("map", "Google 地图")
                }
                .buttonStyle(.plain)

                Button {
                    open(AnitabiWebLink.streetView(lat: point.lat, lng: point.lng))
                } label: {
                    actionPill("binoculars", "街景")
                }
                .buttonStyle(.plain)

                ShareLink(item: shareURL(point), subject: Text(shareTitle(point)), message: Text(shareTitle(point))) {
                    actionPill("square.and.arrow.up", "分享")
                }
                .buttonStyle(.plain)
            }
            // カプセルの左右が sheet の端で切れないように、スクロール内容側に余白を持たせる
            // （行そのものは全幅でスクロールする）。
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -16)
    }

    /// 見た目 38pt・当たり判定 44pt のカプセル。数値の内訳を変えるときは両方まとめて。
    private func actionPill(_ systemImage: String, _ title: String, prominent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .capsule)
        // 見た目は 38pt のまま、指の当たりだけ 44pt へ広げる（HIG の最小タップ領域）。
        .padding(.vertical, 3)
        .contentShape(.rect)
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
        "\(point.displayName.nilIfBlank ?? "巡礼点")｜《\(store.name(forBangumi: point.bangumiID))》的巡礼点"
    }

    // MARK: - 7. 出典行

    /// Web 版 `ns()` の移植：`origin` 文字列 → `@ニックネーム` → 「地図インポート」→ 非表示。
    /// リンクは `originLink` 優先、無ければ `mid`（Google マイマップ）から組む。
    @ViewBuilder
    private func sourceRow(_ point: ScenePoint) -> some View {
        if let source = sourceInfo(point) {
            if let url = source.url {
                Button {
                    safariItem = SafariItem(url: url)
                } label: {
                    HStack(spacing: 4) {
                        Text(source.text)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                Text(source.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sourceInfo(_ point: ScenePoint) -> (text: String, url: URL?)? {
        let midURL = point.mid?.nilIfBlank.map {
            AnitabiWebLink.myMapsViewer(mid: $0, lat: point.lat, lng: point.lng)
        }
        let link = point.originLink?.nilIfBlank.flatMap { URL(string: $0) } ?? midURL

        if let origin = point.origin?.nilIfBlank {
            return ("来源：\(origin)", link)
        }
        if let uid = point.uid, let nickname = store.userNickname(uid)?.nilIfBlank {
            return ("由 @\(nickname) 贡献", nil)
        }
        if midURL != nil {
            return ("来源：地图导入", midURL)
        }
        return nil
    }

    // MARK: - 8. ⋯メニュー

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
                // Toast は阶段 7 で入るので、今は触覚だけで応答する。
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .accessibilityLabel("更多")
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
