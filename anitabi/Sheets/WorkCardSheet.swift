//
//  WorkCardSheet.swift
//  anitabi
//
//  作品カード（設計稿 1c / 2b）。档で変わるのは頭部だけ —— 一段式は**身份条**（標題＋副題＋
//  「全部点位」＋✕ の 1 行）にして残りを地図に譲り、两段式以上は標題ブロックに戻る。
//  「全部点位」が一段式だけなのは、中/大档では地図が隠れていて押しても何も見えないから。
//

import SwiftUI

struct WorkCardSheet: View {

    let store: AnitabiStore
    let workID: Int
    /// 現在开いている地標カードの id。同じ作品内の点なら一覧行をハイライトする。
    var selectedPointID: String?
    /// 最小档に落ちているか（設計稿 2b 一段式の身份条へ切り替える）。
    var isMinimized = false
    /// 一覧から地標を選んだ経路。地図からの選択とは違い、呼び出し側が镜头を寄せる。
    var onSelectPoint: (ScenePoint) -> Void
    var onClose: () -> Void
    /// 一段式の「全部点位」＝ RootView に fitWork を再発行してもらう（初回 `didOpenWork` と同じ計算）。
    var onRefit: () -> Void

    /// 全作品で共有する分组方式。作品を跨いでも前回の選択を覚えておく（web 版のタブ記憶と同じ）。
    @AppStorage("workGroupMode") private var groupMode: WorkGroupingMode = .folder
    @Environment(\.sheetBottomInset) private var sheetBottomInset

    @State private var collapsedGroupIDs: Set<String> = []
    /// 外链胶囊は router を介さず、このカード自身で開閉する。
    @State private var safariItem: SafariItem?

    private var bangumi: BangumiLite? { store.bangumi(id: workID) }
    private var points: [ScenePoint] { store.pointsByBangumi[workID] ?? [] }
    private var themeColor: Color { store.color(forBangumi: workID) }

    // MARK: 分组の出し分け

    private var hasAnyEpisode: Bool {
        points.contains { $0.ep?.nilIfBlank != nil }
    }

    private var folderGroups: [PointGroup] {
        store.groupedPoints(for: workID, mode: .folder)
    }

    /// folder 组数が 2 以上、または ep を持つ点が 1 つでもあるときだけ分组控件を出す。
    /// 両方とも無ければ（＝作品全体が単一のフォルダで話数も無い）平铺一覧に落とす。
    private var showsGroupingControls: Bool {
        folderGroups.count > 1 || hasAnyEpisode
    }

    /// ep が 1 つも無い作品では `groupMode` が過去に「話数」を指していても folder に強制する
    /// （@AppStorage は全作品共有なので、ここを書き換えて次の作品の選択を壊さないようにする）。
    private var effectiveMode: WorkGroupingMode {
        hasAnyEpisode ? groupMode : .folder
    }

    private var groups: [PointGroup] {
        showsGroupingControls ? store.groupedPoints(for: workID, mode: effectiveMode) : folderGroups
    }

    private var isFullyExpanded: Bool { collapsedGroupIDs.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    // 最小档は**一段式の身份条の実高**。中/大档では頭部が別の形に変わるので、
                    // 一段式の複製を隠して置き、常にそちらを測る。
                    .overlay(alignment: .top) { compactHeader.compactHeightProbe(.work) }

                LazyVStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                    infoCard
                    if showsGroupingControls {
                        groupingControlsRow
                    }
                    WorkPointList(
                        store: store,
                        groups: groups,
                        showsHeaders: showsGroupingControls,
                        collapsedGroupIDs: $collapsedGroupIDs,
                        selectedPointID: selectedPointID,
                        themeColor: themeColor,
                        onSelectPoint: onSelectPoint
                    )
                    externalLinksRow
                    contributorRow
                }
                .collapsedInCompactStage(isMinimized ? .compact : .medium)
            }
            .scenePadding(.horizontal)
            .sheetScrollBottomPadding(sheetBottomInset)
        }
        .onAppear { resetCollapseState() }
        .onChange(of: groupMode) { _, _ in resetCollapseState() }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    // MARK: 1. 頭部（設計稿 2b）

    /// 一段式の身份条は上下の余白まで自前で持つ（`compactBarRow`）。中/大档の頭部だけが
    /// カード共通の上余白と、その下の節との間隔を足す。
    @ViewBuilder
    private var header: some View {
        if isMinimized {
            compactHeader
        } else {
            fullHeader
                .padding(.top, SheetMetrics.topInset)
                .padding(.bottom, SheetMetrics.headerBottomSpacing)
        }
    }

    /// 設計稿 2b 一段式：標題 ＋ 副題 ＋ 深緑の「全部点位」＋ ✕。共有は出さない。
    private var compactHeader: some View {
        HStack(alignment: .center, spacing: SheetMetrics.circleButtonGap) {
            VStack(alignment: .leading, spacing: SheetMetrics.rowTitleGap) {
                // 1 行しか無いので、長い作品名は `…` に切らず横に流す。
                MarqueeText(text: store.name(forBangumi: workID), font: SheetFont.titleCompactWork)
                subtitleRow(includesScreenshots: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 隣の ✕ と同じ背丈（`barChip`）。行末に並ぶコントロールは高さを揃える。
            Button("全部点位", action: onRefit)
                .buttonStyle(AnitabiCapsuleStyle(kind: .primary, size: .barChip))
                .fixedSize(horizontal: true, vertical: false)
            CardCloseButton(action: onClose)
        }
        // 迷你条の行高は 4 枚のカードで共通（`compactBarRow`）。
        .compactBarRow()
    }

    /// 設計稿 2b 两段式／三段式：左寄せの標題ブロック（18px/900）＋ 共有 ◯ ＋ ✕。
    private var fullHeader: some View {
        CardHeader(
            title: store.name(forBangumi: workID),
            titleFont: SheetFont.titleLarge,
            onClose: onClose
        ) {
            ShareLink(item: shareURL, subject: shareSubject) {
                CardCircleLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享")
        } subtitle: {
            subtitleRow(includesScreenshots: true)
        }
    }

    /// 設計稿の副題：主題色点 ＋ `{cat} · {city} · {N 个点位}`（中/大档はさらに `{M 张截图}`）。
    private func subtitleRow(includesScreenshots: Bool) -> some View {
        HStack(spacing: SheetMetrics.scaled(5)) {
            ThemeDot(color: themeColor, size: SheetMetrics.dotSize)
            Text(subtitleText(includesScreenshots: includesScreenshots))
                .lineLimit(1)
        }
        .font(SheetFont.rowMeta)
        .foregroundStyle(Color.anitabiInkSecondary)
    }

    private func subtitleText(includesScreenshots: Bool) -> String {
        var parts: [String] = []
        if let cat = bangumi?.cat?.nilIfBlank { parts.append(cat) }
        if let city = bangumi?.city?.nilIfBlank { parts.append(city) }
        parts.append(String(localized: "\(points.count) 个点位"))
        if includesScreenshots {
            let screenshotCount = store.screenshotCount(forBangumi: workID)
            if screenshotCount > 0 { parts.append(String(localized: "\(screenshotCount) 张截图")) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 2. 情報カード（設計稿 2b の `44×60 封面 ＋ 原名/© ＋ 更新日`）

    private var infoCard: some View {
        SheetGroupCard {
            HStack(alignment: .center, spacing: SheetMetrics.thumbnailGap) {
                RoundedRectangle(cornerRadius: SheetMetrics.infoCoverRadius, style: .continuous)
                    .fill(themeColor.anitabiThemeGradient)
                    .overlay {
                        if let url = headerCoverURL {
                            RemoteImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                }
                            }
                        }
                    }
                    .frame(width: SheetMetrics.infoCoverSize.width, height: SheetMetrics.infoCoverSize.height)
                    .clipShape(.rect(cornerRadius: SheetMetrics.infoCoverRadius, style: .continuous))

                VStack(alignment: .leading, spacing: SheetMetrics.scaled(3)) {
                    if let title = bangumi?.title?.nilIfBlank {
                        Text("© \(title)")
                            .font(SheetFont.rowMeta)
                            .foregroundStyle(Color.anitabiInkSecondary)
                            .lineLimit(2)
                    }
                    if let modified = store.modified(forBangumi: workID) {
                        Text("更新于 \(Self.dateFormatter.string(from: modified))")
                            .font(SheetFont.meta)
                            .foregroundStyle(Color.anitabiInkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 剧照 CDN の 512×288 上限（`image.anitabi.cn`）とは別枠——封面は `/images/bangumi/` 経由の
    /// 別 plan 群を持つので、44×60 の器に見合う h360 を明示指定する。
    private var headerCoverURL: URL? {
        AnitabiImage.url(path: bangumi?.cover, plan: "h360")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    private var shareURL: URL {
        URL(string: "https://anitabi.cn/map?bangumiId=\(workID)")!
    }

    private var shareSubject: Text {
        Text("《\(store.name(forBangumi: workID))》的巡礼地图")
    }

    // MARK: 3. 分组控件行（設計稿 2b：分段控件 ＋ 「全部展开」カプセル）

    private var groupingControlsRow: some View {
        HStack(spacing: SheetMetrics.itemSpacing) {
            AnitabiSegmentedPicker(
                selection: $groupMode,
                options: hasAnyEpisode
                    ? [AnitabiSegment(.folder, "按分组"), AnitabiSegment(.episode, "按话数")]
                    : [AnitabiSegment(.folder, "按分组")]
            )
            Button(isFullyExpanded ? "全部折叠" : "全部展开") {
                withAnimation(.anitabiSpring) {
                    collapsedGroupIDs = isFullyExpanded ? Set(groups.map(\.id)) : []
                }
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, size: .rowChip))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 初期状態は常に全展开（折叠は「全部折叠」ボタンから明示的に行う）。
    private func resetCollapseState() {
        collapsedGroupIDs = []
    }

    // MARK: 4. 外链（設計稿 2b：白い薄膜のカプセルを折り返して並べる）

    private var externalLinksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SheetMetrics.itemSpacing) {
                ForEach(externalLinks, id: \.title) { link in
                    Button {
                        safariItem = SafariItem(url: link.url)
                    } label: {
                        HStack(spacing: SheetMetrics.scaled(4)) {
                            Text(link.title)
                            Image(systemName: "arrow.up.right")
                                .font(SheetFont.meta)
                        }
                    }
                    .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, size: .chip))
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    /// 外链胶囊の並び。中国語圏の百科・Google 検索は非 ASCII を含むので必ずパーセントエンコードする。
    private var externalLinks: [(title: String, url: URL)] {
        guard let bangumi else { return [] }
        var links: [(String, URL)] = [
            ("Bangumi", URL(string: "https://bgm.tv/subject/\(bangumi.id)")!)
        ]

        let cnQuery = bangumi.cn?.nilIfBlank ?? bangumi.displayName
        if !cnQuery.isEmpty {
            if let encoded = cnQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://zh.wikipedia.org/w/index.php?search=\(encoded)") {
                links.append((String(localized: "维基百科"), url))
            }
            if let encoded = cnQuery.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://zh.moegirl.org.cn/\(encoded)") {
                links.append((String(localized: "萌娘百科"), url))
            }
        }

        let googleQuery = (bangumi.title?.nilIfBlank ?? bangumi.cn?.nilIfBlank ?? bangumi.displayName) + " 聖地巡礼"
        if let encoded = googleQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            links.append((String(localized: "Google 圣地巡礼"), url))
        }

        return links
    }

    // MARK: 5. 貢献者（設計稿 2b：22pt の丸を 8pt 重ねて並べ、右に人数と授权）

    @ViewBuilder
    private var contributorRow: some View {
        let summary = store.contributorSummary(forBangumi: workID)
        HStack(spacing: SheetMetrics.itemSpacing) {
            if let summary, !summary.top.isEmpty {
                // 設計稿は色違いの丸 3 つ。貢献者ごとの画像は API に無いので、
                // 記号（人）＋作品の主題色で「人が居る」ことだけを示す（字の代替は置かない——硬約束）。
                HStack(spacing: -SheetMetrics.scaled(8)) {
                    ForEach(Array(summary.top.prefix(3).enumerated()), id: \.offset) { index, _ in
                        Image(systemName: "person.fill")
                            .font(SheetFont.meta)
                            .foregroundStyle(Color.anitabiOnAccent)
                            .frame(width: SheetMetrics.contributorAvatarDiameter, height: SheetMetrics.contributorAvatarDiameter)
                            .background(themeColor.opacity(1 - Double(index) * 0.2), in: .circle)
                            .overlay { Circle().strokeBorder(Color.anitabiRaisedStroke, lineWidth: SheetMetrics.shape(2)) }
                    }
                }
            }
            // 授权表記は設計稿どおり同じ 1 行の末尾に付ける。翻訳キーを増やさないため、
            // 既存キーの訳文へ `verbatim` で連結する（`CC BY-NC-SA 4.0` は 3 言語共通の固有名）。
            Text(verbatim: summary.map { "\(contributorText($0)) · CC BY-NC-SA 4.0" }
                 ?? String(localized: "数据由 anitabi.cn 社区贡献 · CC BY-NC-SA 4.0"))
                .font(SheetFont.meta)
                .foregroundStyle(Color.anitabiInkTertiary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// total ≤2 なら「等」を省いた自然な語順にする。
    private func contributorText(_ summary: (top: [String], total: Int)) -> String {
        let names = summary.top.map { "@\($0)" }
        guard !names.isEmpty else {
            return String(localized: "由 \(summary.total) 位贡献者收集")
        }
        let joined = names.joined(separator: "、")
        if summary.total <= 2 {
            return String(localized: "由 \(joined) 收集")
        }
        return String(localized: "由 \(joined) 等 \(summary.total) 位贡献者收集")
    }
}
