//
//  AnitabiStore.swift
//  anitabi
//
//  首屏が使う唯一の状態。全量データはローカルにあるので、
//  検索・附近・都市集計は全てメモリ上で完結する（ネットワーク往復ゼロ＝ローディング表示なし）。
//

import CoreLocation
import MapKit
import Observation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "cn.anitabi.app", category: "store")

// MARK: - 派生モデル

struct NearbyPoint: Identifiable, Sendable {
    let point: ScenePoint
    let distance: CLLocationDistance
    var id: String { point.id }
}

struct CityTile: Identifiable, Sendable {
    let id: String
    let name: String
    let center: CLLocationCoordinate2D
    /// 表示半径（m）。集計とカメラ移動の両方に使う。
    let radius: CLLocationDistance
    var pointCount: Int
}

enum WorkBrowseTab: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case newlyAdded
    case popular

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .recentlyUpdated: "最近更新"
        case .newlyAdded: "新收录"
        case .popular: "热门"
        }
    }
}

enum SearchResult: Identifiable {
    case bangumi(BangumiLite)
    case point(ScenePoint, distance: CLLocationDistance?)

    var id: String {
        switch self {
        case .bangumi(let b): "b\(b.id)"
        case .point(let p, _): "p\(p.id)"
        }
    }
}

enum DataLoadPhase: Equatable {
    /// まだ何も無い（初回起動 + ネットワーク待ち）
    case empty
    /// 座標だけある。地図は描けるが名前・スクショはまだ
    case geometryOnly
    /// 全部揃った
    case complete
    case failed(String)
}

// MARK: - Store

@MainActor
@Observable
final class AnitabiStore {

    // MARK: データ

    private(set) var bangumis: [BangumiLite] = []
    private(set) var points: [ScenePoint] = []
    private(set) var phase: DataLoadPhase = .empty

    private var bangumiByID: [Int: BangumiLite] = [:]
    /// 作品ごとの最終更新（g0-g6 のセル 3 番目）。「最近更新」タブに使う。
    private var bangumiModified: [Int: Double] = [:]
    /// 検索用の小文字化済みインデックス。キーストロークごとに再生成しない。
    private var searchIndex: [SearchEntry] = []

    /// 作品 ID → その作品に属する地標。`groupedPoints`/`screenshotCount`/`contributorSummary` が使う。
    private(set) var pointsByBangumi: [Int: [ScenePoint]] = [:]
    /// 作品 ID → スクリーンショット付き地標数（`pointsByBangumi` と一緒に事前計算）。
    private var screenshotCountByBangumi: [Int: Int] = [:]

    /// 投稿者 User ID → ニックネーム（`/d/users.csv`）。起動の非クリティカルパスで低優先度に取得する。
    private(set) var usersByID: [Int: String] = [:]
    /// `bangumi-icons.json` のスプライト画像 URL。画像本体のダウンロードは次段（`BangumiIconSprite`）が担当。
    private(set) var iconSpriteURL: URL?

    // MARK: 派生状態

    private(set) var nearby: [NearbyPoint] = []
    private(set) var cities: [CityTile] = []
    private(set) var recentlyUpdatedWorks: [BangumiLite] = []
    private(set) var newlyAddedWorks: [BangumiLite] = []
    private(set) var popularWorks: [BangumiLite] = []

    /// 直近に開いた作品。半开档の上下文卡に出す。
    private(set) var lastVisitedBangumi: BangumiLite?
    /// 直近に開いた作品 ID の履歴（最大 10 件、新しいものが先頭、重複なし）。
    private(set) var recentVisits: [Int] = []

    var isEmpty: Bool { points.isEmpty }

    // MARK: - 読み込み

    func bootstrap() async {
        #if DEBUG
        if AnitabiSampleData.isEnabled {
            apply(AnitabiSampleData.dataset())
            log.info("サンプルデータで起動（-anitabiUseSampleData）")
            return
        }
        #endif

        // 1) ディスクキャッシュで即描画
        if let cached = await AnitabiDataLoader.shared.loadFromCache() {
            apply(cached)
            log.info("キャッシュから復元：作品 \(cached.bangumis.count) / 地標 \(cached.points.count)")
        }

        // 2) ネットワークで最新化
        let known = cachedModified
        do {
            let fresh = try await AnitabiDataLoader.shared.refresh(cachedModified: known) { [weak self] partial in
                // g.json だけ届いた段階。座標があれば地図は描ける。
                Task { @MainActor in
                    guard let self, self.points.isEmpty else { return }
                    self.apply(partial)
                }
            }
            apply(fresh)
            cachedModified = fresh.modified
            log.info("最新化完了：作品 \(fresh.bangumis.count) / 地標 \(fresh.points.count)")
        } catch {
            if points.isEmpty {
                phase = .failed(error.localizedDescription)
            }
            log.error("データ更新に失敗：\(error.localizedDescription)")
        }

        // 3) users.csv / bangumi-icons.json はクリティカルパスではないので低優先度で追走させる。
        // （サンプルデータ利用時は先頭で return 済みなのでここに来ない）
        Task(priority: .background) { [weak self] in
            let users = await AnitabiDataLoader.shared.loadUsers()
            guard let self else { return }
            self.usersByID = users
        }
        Task(priority: .background) { [weak self] in
            guard let iconIndex = await AnitabiDataLoader.shared.loadIconIndex() else { return }
            guard let self else { return }
            self.iconSpriteURL = iconIndex.spriteURL
            self.applyIconIndex(iconIndex.ids)
        }
    }

    private func apply(_ dataset: AnitabiDataset) {
        bangumis = dataset.bangumis
        points = dataset.points
        bangumiByID = Dictionary(dataset.bangumis.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if !dataset.modifiedByBangumi.isEmpty {
            bangumiModified = dataset.modifiedByBangumi
        }
        phase = dataset.hasDetails ? .complete : .geometryOnly

        rebuildSearchIndex()
        rebuildCities()
        rebuildWorkLists()
        rebuildBangumiPointIndex()
        restoreLastVisited()
    }

    /// `bangumi-icons.json` の `ids` を `BangumiLite.hasIcon` に回填する。
    private func applyIconIndex(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        for index in bangumis.indices {
            bangumis[index].hasIcon = idSet.contains(bangumis[index].id)
        }
        bangumiByID = Dictionary(bangumis.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - 附近

    /// 現在地から近い順に地標を並べる。5 万点の線形走査だがバックグラウンドで行う。
    func recomputeNearby(around location: CLLocation, limit: Int = 30) async {
        let snapshot = points
        let coordinate = location.coordinate

        let result: [NearbyPoint] = await Task.detached(priority: .userInitiated) {
            // 等距長方形近似。ソート用の相対比較なので測地線精度は要らない。
            let latRad = coordinate.latitude * .pi / 180
            let metersPerLat = 111_320.0
            let metersPerLng = 111_320.0 * cos(latRad)

            var scored: [(ScenePoint, Double)] = []
            scored.reserveCapacity(min(snapshot.count, 4096))

            for point in snapshot {
                let dy = (point.lat - coordinate.latitude) * metersPerLat
                let dx = (point.lng - coordinate.longitude) * metersPerLng
                let squared = dx * dx + dy * dy
                // 50km 以遠は「附近」ではない
                guard squared < 50_000 * 50_000 else { continue }
                scored.append((point, squared))
            }
            scored.sort { $0.1 < $1.1 }
            return scored.prefix(limit).map {
                NearbyPoint(point: $0.0, distance: $0.1.squareRoot())
            }
        }.value

        nearby = result
    }

    /// 附近に何も無いときに提示する「いちばん近い巡礼地」。
    var nearestBeyondNeighborhood: NearbyPoint? {
        nearby.first
    }

    // MARK: - 検索

    private struct SearchEntry: Sendable {
        let key: String
        let bangumiID: Int
        /// 地標なら point のインデックス、作品行なら nil
        let pointIndex: Int?
    }

    private func rebuildSearchIndex() {
        var index: [SearchEntry] = []
        index.reserveCapacity(bangumis.count + points.count)

        for bangumi in bangumis {
            let key = [bangumi.cn, bangumi.title, bangumi.city, bangumi.cat]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            index.append(SearchEntry(key: key, bangumiID: bangumi.id, pointIndex: nil))
        }

        for (offset, point) in points.enumerated() {
            guard point.name != nil || point.nameCN != nil else { continue }
            let key = [point.name, point.nameCN]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            index.append(SearchEntry(key: key, bangumiID: point.bangumiID, pointIndex: offset))
        }

        searchIndex = index
    }

    /// ローカル全文検索。全データが手元にあるので同期で返す＝ローディング表示は不要。
    /// 上限は作品 ≤`workLimit`・地標 ≤`sceneLimit`（合計は既定で 60 件）。
    func search(
        _ query: String,
        near location: CLLocation?,
        workLimit: Int = 10,
        sceneLimit: Int = 50
    ) -> [SearchResult] {
        guard let needle = query.nilIfBlank?.lowercased() else { return [] }

        var works: [BangumiLite] = []
        var scenes: [ScenePoint] = []

        for entry in searchIndex {
            guard entry.key.contains(needle) else { continue }
            if let pointIndex = entry.pointIndex {
                if scenes.count < sceneLimit { scenes.append(points[pointIndex]) }
            } else if let bangumi = bangumiByID[entry.bangumiID] {
                if works.count < workLimit { works.append(bangumi) }
            }
            if works.count >= workLimit && scenes.count >= sceneLimit { break }
        }

        // 作品は地標数の多い順＝情報量の多い順（Web 版の並びと同じ考え方）
        works.sort { $0.points.count > $1.points.count }

        if let location {
            scenes.sort {
                distance(from: location, to: $0) < distance(from: location, to: $1)
            }
        }

        return works.prefix(workLimit).map { SearchResult.bangumi($0) }
            + scenes.prefix(sceneLimit).map { point in
                SearchResult.point(point, distance: location.map { distance(from: $0, to: point) })
            }
    }

    /// 都市名の一致（HomeSheet 検索用、阶段 4 で追加）。候補は最大 12 件しかないので上限は設けない。
    /// `SearchResult` 本体に `.city` を足すと、既存（削除待ち）の `HomeSheetView` 側の
    /// 網羅 switch が壊れるため、こちらは独立した便宜クエリにしてある。
    func matchingCities(_ query: String) -> [CityTile] {
        guard let needle = query.nilIfBlank?.lowercased() else { return [] }
        return cities.filter { $0.name.lowercased().contains(needle) }
    }

    private func distance(from location: CLLocation, to point: ScenePoint) -> CLLocationDistance {
        CLLocation(latitude: point.lat, longitude: point.lng).distance(from: location)
    }

    // MARK: - 都市

    /// 巡礼の主要都市。作品側の `city` フィールドは国・地域粒度（「日本」など）で
    /// 都市集計に使えないため、座標から実データを数える方式にしている。
    private static let cityCenters: [(id: String, name: String, lat: Double, lng: Double, radius: Double)] = [
        ("tokyo", "東京", 35.6812, 139.7671, 30_000),
        ("kyoto", "京都", 35.0116, 135.7681, 22_000),
        ("osaka", "大阪", 34.6937, 135.5023, 20_000),
        ("kamakura", "鎌倉", 35.3192, 139.5467, 9_000),
        ("nagoya", "名古屋", 35.1815, 136.9066, 20_000),
        ("sapporo", "札幌", 43.0618, 141.3545, 25_000),
        ("fukuoka", "福岡", 33.5904, 130.4017, 20_000),
        ("kobe", "神戸", 34.6901, 135.1955, 18_000),
        ("hiroshima", "広島", 34.3853, 132.4553, 18_000),
        ("kanazawa", "金沢", 36.5613, 136.6562, 15_000),
        ("numazu", "沼津", 35.0955, 138.8635, 12_000),
        ("chichibu", "秩父", 35.9924, 139.0784, 12_000),
    ]

    private func rebuildCities() {
        guard !points.isEmpty else { return }
        var counts: [String: Int] = [:]

        for point in points {
            for city in Self.cityCenters {
                let dy = (point.lat - city.lat) * 111_320
                let dx = (point.lng - city.lng) * 111_320 * cos(city.lat * .pi / 180)
                if dx * dx + dy * dy < city.radius * city.radius {
                    counts[city.id, default: 0] += 1
                    break  // いちばん最初にヒットした都市に数える
                }
            }
        }

        cities = Self.cityCenters
            .map {
                CityTile(
                    id: $0.id,
                    name: $0.name,
                    center: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng),
                    radius: $0.radius,
                    pointCount: counts[$0.id] ?? 0
                )
            }
            .filter { $0.pointCount > 0 }
            .sorted { $0.pointCount > $1.pointCount }
    }

    // MARK: - 作品リスト

    func works(for tab: WorkBrowseTab) -> [BangumiLite] {
        switch tab {
        case .recentlyUpdated: recentlyUpdatedWorks
        case .newlyAdded: newlyAddedWorks
        case .popular: popularWorks
        }
    }

    private func rebuildWorkLists() {
        let withPoints = bangumis.filter { !$0.points.isEmpty }

        // 地標数の多い順＝データが充実している作品
        popularWorks = Array(withPoints.sorted { $0.points.count > $1.points.count }.prefix(20))

        // Bangumi の subject id は登録順に振られるため、地標付き作品の中で id が大きい
        // ＝新しく巡礼データが付いた作品、の近似として使う。
        newlyAddedWorks = Array(withPoints.sorted { $0.id > $1.id }.prefix(20))

        // g0-g6 のセルが持つ modified。未取得なら人気順にフォールバック。
        if bangumiModified.isEmpty {
            recentlyUpdatedWorks = popularWorks
        } else {
            recentlyUpdatedWorks = Array(
                withPoints
                    .sorted { (bangumiModified[$0.id] ?? 0) > (bangumiModified[$1.id] ?? 0) }
                    .prefix(20)
            )
        }
    }

    /// 「ランダムな作品」の候補 = スクリーンショット付き地標が 3 件超ある作品。
    func randomWork() -> BangumiLite? {
        bangumis.filter { screenshotCount(forBangumi: $0.id) > 3 }.randomElement()
    }

    /// 作品のスクリーンショット付き地標数（`rebuildBangumiPointIndex` で事前計算）。
    func screenshotCount(forBangumi id: Int) -> Int {
        screenshotCountByBangumi[id] ?? 0
    }

    private func rebuildBangumiPointIndex() {
        var grouped: [Int: [ScenePoint]] = [:]
        grouped.reserveCapacity(bangumis.count)
        for point in points {
            grouped[point.bangumiID, default: []].append(point)
        }
        pointsByBangumi = grouped
        screenshotCountByBangumi = grouped.mapValues { pts in
            pts.reduce(into: 0) { count, point in
                if point.image != nil { count += 1 }
            }
        }
    }

    // MARK: - 視口

    /// 現在の地図表示範囲に地標を持つ作品を、点数の多い順に集計する（chips 用）。
    /// 全点の線形走査だが、呼び出し側でデバウンスする前提。
    func worksInViewport(region: MKCoordinateRegion) -> [(id: Int, count: Int)] {
        let latHalf = region.span.latitudeDelta / 2
        let lngHalf = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - latHalf
        let maxLat = region.center.latitude + latHalf
        let minLng = region.center.longitude - lngHalf
        let maxLng = region.center.longitude + lngHalf

        var counts: [Int: Int] = [:]
        for point in points {
            guard
                point.lat >= minLat, point.lat <= maxLat,
                point.lng >= minLng, point.lng <= maxLng
            else { continue }
            counts[point.bangumiID, default: 0] += 1
        }
        return counts.map { (id: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    // MARK: - 作品内グルーピング

    /// 作品詳細パネルの「フォルダ」「話数」タブ用の束ね。Web 版のロジックを移植。
    func groupedPoints(for bangumiID: Int, mode: WorkGroupingMode) -> [PointGroup] {
        let pts = pointsByBangumi[bangumiID] ?? []
        return switch mode {
        case .folder: groupedByFolder(pts, bangumiID: bangumiID)
        case .episode: groupedByEpisode(pts)
        }
    }

    /// folder モード：
    /// - `isFolder` の点は自身がグループになる（その点自身を先頭行として残す）
    /// - `fid` を持つ点は対応する `isFolder` 点のグループへ
    /// - `folderName` 文字列を持つ点（旧データ）はその名前でグループへ
    /// - それ以外は作品名を組名にしたデフォルトグループへ
    /// - 結果が空のグループは作らない（`isFolder` 自身のグループは常に非空）
    private func groupedByFolder(_ pts: [ScenePoint], bangumiID: Int) -> [PointGroup] {
        var folderOrder: [String] = []
        var membersByFolderID: [String: [ScenePoint]] = [:]
        for point in pts where point.isFolder {
            folderOrder.append(point.id)
            membersByFolderID[point.id] = [point]
        }

        var namedOrder: [String] = []
        var membersByName: [String: [ScenePoint]] = [:]
        var defaultMembers: [ScenePoint] = []

        for point in pts where !point.isFolder {
            if let fid = point.fid, membersByFolderID[fid] != nil {
                membersByFolderID[fid]?.append(point)
                continue
            }
            if let folderName = point.folderName?.nilIfBlank {
                if membersByName[folderName] == nil {
                    namedOrder.append(folderName)
                    membersByName[folderName] = []
                }
                membersByName[folderName]?.append(point)
                continue
            }
            defaultMembers.append(point)
        }

        var groups: [PointGroup] = []
        for fid in folderOrder {
            guard let members = membersByFolderID[fid], !members.isEmpty else { continue }
            let name = members.first?.displayName.nilIfBlank ?? fid
            groups.append(PointGroup(id: fid, name: name, points: members))
        }
        for name in namedOrder {
            guard let members = membersByName[name], !members.isEmpty else { continue }
            groups.append(PointGroup(id: "name:\(name)", name: name, points: members))
        }
        if !defaultMembers.isEmpty {
            groups.append(
                PointGroup(id: "default:\(bangumiID)", name: name(forBangumi: bangumiID), points: defaultMembers)
            )
        }
        return groups
    }

    /// episode モード：純数字組は数値昇順で先頭、非数字組は `localizedCompare` でその後、
    /// `ep` の無い点は「未分组」として最後にまとめる（本段階は未ローカライズの固定文言）。
    private func groupedByEpisode(_ pts: [ScenePoint]) -> [PointGroup] {
        var numericOrder: [String] = []
        var numericMembers: [String: [ScenePoint]] = [:]
        var nonNumericOrder: [String] = []
        var nonNumericMembers: [String: [ScenePoint]] = [:]
        var unassigned: [ScenePoint] = []

        for point in pts {
            guard let ep = point.ep?.nilIfBlank else {
                unassigned.append(point)
                continue
            }
            if Int(ep) != nil {
                if numericMembers[ep] == nil {
                    numericOrder.append(ep)
                    numericMembers[ep] = []
                }
                numericMembers[ep]?.append(point)
            } else {
                if nonNumericMembers[ep] == nil {
                    nonNumericOrder.append(ep)
                    nonNumericMembers[ep] = []
                }
                nonNumericMembers[ep]?.append(point)
            }
        }

        let numericGroups = numericOrder
            .sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
            .compactMap { ep -> PointGroup? in
                guard let members = numericMembers[ep], !members.isEmpty else { return nil }
                return PointGroup(id: "ep:\(ep)", name: ep, points: members)
            }

        let nonNumericGroups = nonNumericOrder
            .sorted { $0.localizedCompare($1) == .orderedAscending }
            .compactMap { ep -> PointGroup? in
                guard let members = nonNumericMembers[ep], !members.isEmpty else { return nil }
                return PointGroup(id: "ep:\(ep)", name: ep, points: members)
            }

        var groups = numericGroups + nonNumericGroups
        if !unassigned.isEmpty {
            groups.append(PointGroup(id: "ep:none", name: "未分组", points: unassigned))
        }
        return groups
    }

    // MARK: - 参照

    func bangumi(id: Int) -> BangumiLite? { bangumiByID[id] }

    func color(forBangumi id: Int) -> Color {
        bangumiByID[id]?.themeColor ?? Color(hex: 0x8A8A6F)
    }

    func name(forBangumi id: Int) -> String {
        bangumiByID[id]?.displayName ?? ""
    }

    /// 作品の最終更新（g0-g6 セルの modified、ミリ秒エポック）。未取得の作品は nil。
    /// WorkCardSheet の「更新于」表示用（阶段 5 で追加）。
    func modified(forBangumi id: Int) -> Date? {
        guard let millis = bangumiModified[id], millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    // MARK: - 投稿者

    /// User ID → ニックネーム（`/d/users.csv`）。未取得・該当なしは nil。
    func userNickname(_ uid: Int) -> String? {
        usersByID[uid]
    }

    /// 地標に添える出典表示。優先度は `origin` の文言 → `uid` のニックネーム（`@名前`）→ nil。
    /// `mid`（Google マイマップ由来）の「地図インポート」表記は UI 層の判断に委ねる。
    func contributorLabel(for point: ScenePoint) -> String? {
        if let origin = point.origin?.nilIfBlank { return origin }
        if let uid = point.uid, let nickname = usersByID[uid]?.nilIfBlank {
            return "@\(nickname)"
        }
        return nil
    }

    /// 作品全体の投稿者サマリー：uid の出現回数上位 2 名のニックネームと、重複排除した投稿者総数。
    /// `uid` が 1 件も無ければ nil。
    func contributorSummary(forBangumi id: Int) -> (top: [String], total: Int)? {
        guard let pts = pointsByBangumi[id] else { return nil }
        var counts: [Int: Int] = [:]
        for point in pts {
            guard let uid = point.uid else { continue }
            counts[uid, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }

        let ranked = counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        let top = ranked.prefix(2).compactMap { usersByID[$0.key] }
        return (top: top, total: counts.count)
    }

    // MARK: - 履歴

    private enum Keys {
        static let lastBangumi = "home.lastVisitedBangumiID"
        static let recentVisits = "home.recentVisitBangumiIDs"
        static let modified = "home.dataModified"
    }

    private var cachedModified: Double {
        get { UserDefaults.standard.double(forKey: Keys.modified) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.modified) }
    }

    /// 訪問を記録する。`lastVisitedBangumi`（単一・互換維持）と `recentVisits`（最大 10 件）の
    /// 両方を同時に更新する。
    func rememberVisit(bangumiID: Int) {
        UserDefaults.standard.set(bangumiID, forKey: Keys.lastBangumi)

        var ids = recentVisits
        ids.removeAll { $0 == bangumiID }
        ids.insert(bangumiID, at: 0)
        if ids.count > 10 { ids = Array(ids.prefix(10)) }
        UserDefaults.standard.set(ids, forKey: Keys.recentVisits)

        restoreLastVisited()
    }

    private func restoreLastVisited() {
        let id = UserDefaults.standard.integer(forKey: Keys.lastBangumi)
        lastVisitedBangumi = id == 0 ? nil : bangumiByID[id]
        recentVisits = (UserDefaults.standard.array(forKey: Keys.recentVisits) as? [Int]) ?? []
    }
}
