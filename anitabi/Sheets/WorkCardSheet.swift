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
            LazyVStack(alignment: .leading, spacing: 24) {
                titleSection
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
            .padding(.horizontal, 16)
            // grabber と見出しがぶつからない分の余白。最小档 128pt はこの見出し 2 行ぶん。
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .onAppear { resetCollapseState() }
        .onChange(of: groupMode) { _, _ in resetCollapseState() }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
    }

    // MARK: 1-2. 見出し・副題

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                Text(store.name(forBangumi: workID))
                    .font(.title2.bold())
                    .lineLimit(2)
                Spacer(minLength: 0)
                CardCloseButton(action: onClose)
            }
            HStack(spacing: 6) {
                ThemeDot(color: store.color(forBangumi: workID))
                Text(subtitleText)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    /// `{cat} · {city} · {N 个点位} · {M 张截图}`。欠けているフィールドは区切り点ごと省く。
    private var subtitleText: String {
        var parts: [String] = []
        if let cat = bangumi?.cat?.nilIfBlank { parts.append(cat) }
        if let city = bangumi?.city?.nilIfBlank { parts.append(city) }
        parts.append("\(points.count) 个点位")
        let screenshotCount = store.screenshotCount(forBangumi: workID)
        if screenshotCount > 0 { parts.append("\(screenshotCount) 张截图") }
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

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onRefit) {
                Label("查看全部点位", systemImage: "map")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)

            ShareLink(item: shareURL, subject: shareSubject) {
                Label("分享", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
        }
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
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: .circle)
            }
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

    private var externalLinksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(externalLinks, id: \.title) { link in
                    Button {
                        safariItem = SafariItem(url: link.url)
                    } label: {
                        Text(link.title)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                links.append(("维基百科", url))
            }
            if let encoded = cnQuery.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://zh.moegirl.org.cn/\(encoded)") {
                links.append(("萌娘百科", url))
            }
        }

        let googleQuery = (bangumi.title?.nilIfBlank ?? bangumi.cn?.nilIfBlank ?? bangumi.displayName) + " 聖地巡礼"
        if let encoded = googleQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
            links.append(("Google 圣地巡礼", url))
        }

        return links
    }

    /// total ≤2 なら「等」を省いた自然な語順にする。
    private func contributorText(_ summary: (top: [String], total: Int)) -> String {
        let names = summary.top.map { "@\($0)" }
        guard !names.isEmpty else {
            return "由 \(summary.total) 位贡献者收集"
        }
        if summary.total <= 2 {
            return "由 \(names.joined(separator: "、")) 收集"
        }
        return "由 \(names.joined(separator: "、")) 等 \(summary.total) 位贡献者收集"
    }
}

/// 作品カード・地標カード共通の閉じる釦（28pt の灰丸）。`PointCardSheet.swift` からも参照される
/// ため（阶段 3 で先に生えた依存）、このファイルに置いたまま動かさない。
struct CardCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color(.tertiarySystemFill), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}
