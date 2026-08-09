//
//  WorkCardSheet.swift
//  anitabi
//
//  作品カード。阶段 3 の骨組み（見出し＋素の一覧）を頭部カード・動作排・分组控件・
//  分组点一覧・footer まで実装する。
//

import SwiftUI

struct WorkCardSheet: View {

    let store: AnitabiStore
    let workID: Int
    /// 現在开いている地標カードの id。同じ作品内の点なら一覧行をハイライトする。
    var selectedPointID: String?
    /// 一覧から地標を選んだ経路。地図からの選択とは違い、呼び出し側が镜头を寄せる。
    var onSelectPoint: (ScenePoint) -> Void
    var onClose: () -> Void
    /// 「查看全部点位」＝ RootView に fitWork を再発行してもらう（初回 `didOpenWork` と同じ計算）。
    var onRefit: () -> Void

    /// 全作品で共有する分组方式。作品を跨いでも前回の選択を覚えておく（web 版のタブ記憶と同じ）。
    @AppStorage("workGroupMode") private var groupMode: WorkGroupingMode = .folder
    @State private var collapsedGroupIDs: Set<String> = []
    /// 外链胶囊は router を介さず、このカード自身の档で開閉する。
    @State private var safariItem: SafariItem?

    private var bangumi: BangumiLite? { store.bangumi(id: workID) }
    private var points: [ScenePoint] { store.pointsByBangumi[workID] ?? [] }

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                    // grabber と標題がぶつからない分の余白。最小档 128pt はこの頭部ぶん。
                    .padding(.top, SheetMetrics.cardHeaderTopInset)
                    .padding(.bottom, SheetMetrics.cardHeaderBottomSpacing)

                LazyVStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                    headerCard
                    actionRow
                    if showsGroupingControls {
                        groupingControlsRow
                    }
                    WorkPointList(
                        store: store,
                        groups: groups,
                        showsHeaders: showsGroupingControls,
                        collapsedGroupIDs: $collapsedGroupIDs,
                        selectedPointID: selectedPointID,
                        onSelectPoint: onSelectPoint
                    )
                    footerCard
                }
            }
            .padding(.horizontal, SheetMetrics.horizontalPadding)
            .padding(.bottom, 24)
        }
        .onAppear { resetCollapseState() }
        .onChange(of: groupMode) { _, _ in resetCollapseState() }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    // MARK: 1-2. 頭部（共有 ◯・標題・副題・✕）

    /// 解剖は `CardHeader` 側に集約。ここは中身（共有する URL と副題の組み立て）だけを渡す。
    private var cardHeader: some View {
        CardHeader(title: store.name(forBangumi: workID), onClose: onClose) {
            ShareLink(item: shareURL, subject: shareSubject) {
                CardHeaderCircleLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享")
        } subtitle: {
            HStack(spacing: 6) {
                ThemeDot(color: store.color(forBangumi: workID))
                Text(subtitleText)
            }
        }
    }

    /// `{cat} · {city} · {N 个点位} · {M 张截图}`。欠けているフィールドは区切り点ごと省く。
    private var subtitleText: String {
        var parts: [String] = []
        if let cat = bangumi?.cat?.nilIfBlank { parts.append(cat) }
        if let city = bangumi?.city?.nilIfBlank { parts.append(city) }
        parts.append(String(localized: "\(points.count) 个点位"))
        let screenshotCount = store.screenshotCount(forBangumi: workID)
        if screenshotCount > 0 { parts.append(String(localized: "\(screenshotCount) 张截图")) }
        return parts.joined(separator: " · ")
    }

    // MARK: 3. 頭部カード

    private var headerCard: some View {
        SheetGroupCard {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        bangumi?.themeGradient
                            ?? LinearGradient(colors: [Color(.tertiarySystemFill)], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay {
                        if let url = headerCoverURL {
                            AsyncImage(url: url) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                }
                            }
                        }
                    }
                    .frame(width: 72, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    if let title = bangumi?.title?.nilIfBlank {
                        Text("© \(title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let modified = store.modified(forBangumi: workID) {
                        Text("更新于 \(Self.dateFormatter.string(from: modified))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 剧照 CDN の 512×288 上限（`image.anitabi.cn`）とは別枠——封面は `/images/bangumi/` 経由の
    /// 別 plan 群を持つので、72×96 の器に見合う h360 を明示指定する。HomeBrowseView の
    /// `CoverThumbnail` は 34–60pt 級の小サムネイル用に h160 を固定しているため、サイズが違う
    /// ここでは共有せずローカルに URL を組む。
    private var headerCoverURL: URL? {
        AnitabiImage.url(path: bangumi?.cover, plan: "h360")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    // MARK: 4. 動作排

    /// 地点カードと同じ高さのタイル（実測 総高 51pt・icon 上＋`.footnote` 下）。
    /// 共有は頭部の丸釦へ移したので、この作品カードに残る動作は 1 つだけ——
    /// Apple の地点カードの先頭タイル（青い主動作）と同じ形で**行幅いっぱい**に敷く。
    /// このカードで tint 填充を使うのはここ 1 枚だけ。
    private var actionRow: some View {
        Button(action: onRefit) {
            ActionTileLabel(systemImage: "map", title: "查看全部点位")
        }
        .buttonStyle(ActionTileButtonStyle(prominent: true))
    }

    private var shareURL: URL {
        URL(string: "https://anitabi.cn/map?bangumiId=\(workID)")!
    }

    private var shareSubject: Text {
        Text("《\(store.name(forBangumi: workID))》的巡礼地图")
    }

    // MARK: 5. 分组控件行

    private var groupingControlsRow: some View {
        HStack(spacing: 12) {
            Picker("分组方式", selection: $groupMode) {
                Text("分组").tag(WorkGroupingMode.folder)
                Text("话数").tag(WorkGroupingMode.episode)
                    .disabled(!hasAnyEpisode)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                Button("全部展开") {
                    withAnimation(.anitabiSpring) { collapsedGroupIDs = [] }
                }
                Button("全部折叠") {
                    withAnimation(.anitabiSpring) { collapsedGroupIDs = Set(groups.map(\.id)) }
                }
            } label: {
                CircularGlyphLabel(systemName: "chevron.up.chevron.down", diameter: 32)
            }
            .tint(Color.secondary)
            .padding(.trailing, -6)
            .accessibilityLabel("展开或折叠全部分组")
        }
    }

    /// 総点数 <100 なら初期状態で全展开、≥100 なら先頭组だけ展开。
    private func resetCollapseState() {
        guard showsGroupingControls else {
            collapsedGroupIDs = []
            return
        }
        collapsedGroupIDs = points.count < 100 ? [] : Set(groups.dropFirst().map(\.id))
    }

    // MARK: 7. Footer カード

    private var footerCard: some View {
        SheetGroupCard {
            externalLinksRow
            if let summary = store.contributorSummary(forBangumi: workID) {
                Text(contributorText(summary))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("CC BY-NC-SA 4.0 · 截图版权归原作品所有")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// 外链は系统の `.bordered` カプセル（regular・`.subheadline` で実測 32pt）。
    /// 高さは手書きの padding ではなく `controlSize` に決めさせる。
    private var externalLinksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(externalLinks, id: \.title) { link in
                    Button(link.title) {
                        safariItem = SafariItem(url: link.url)
                    }
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
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
