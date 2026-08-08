//
//  AnitabiStore.swift
//  anitabi
//
//  首屏が使う唯一の状態。全量データはローカルにあるので、
//  検索・附近・都市集計は全てメモリ上で完結する（ネットワーク往復ゼロ＝ローディング表示なし）。
//

import CoreLocation
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

    // MARK: 派生状態

    private(set) var nearby: [NearbyPoint] = []
    private(set) var cities: [CityTile] = []
    private(set) var recentlyUpdatedWorks: [BangumiLite] = []
    private(set) var newlyAddedWorks: [BangumiLite] = []
    private(set) var popularWorks: [BangumiLite] = []

    /// 直近に開いた作品。半开档の上下文卡に出す。
    private(set) var lastVisitedBangumi: BangumiLite?

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
        restoreLastVisited()
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
    func search(_ query: String, near location: CLLocation?, limit: Int = 40) -> [SearchResult] {
        guard let needle = query.nilIfBlank?.lowercased() else { return [] }

        var works: [BangumiLite] = []
        var scenes: [ScenePoint] = []

        for entry in searchIndex {
            guard entry.key.contains(needle) else { continue }
            if let pointIndex = entry.pointIndex {
                if scenes.count < limit { scenes.append(points[pointIndex]) }
            } else if let bangumi = bangumiByID[entry.bangumiID] {
                if works.count < 10 { works.append(bangumi) }
            }
            if works.count >= 10 && scenes.count >= limit { break }
        }

        // 作品は地標数の多い順＝情報量の多い順（Web 版の並びと同じ考え方）
        works.sort { $0.points.count > $1.points.count }

        if let location {
            scenes.sort {
                distance(from: location, to: $0) < distance(from: location, to: $1)
            }
        }

        return works.prefix(4).map { SearchResult.bangumi($0) }
            + scenes.prefix(limit).map { point in
                SearchResult.point(point, distance: location.map { distance(from: $0, to: point) })
            }
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

    // MARK: - 参照

    func bangumi(id: Int) -> BangumiLite? { bangumiByID[id] }

    func color(forBangumi id: Int) -> Color {
        bangumiByID[id]?.themeColor ?? Color(hex: 0x8A8A6F)
    }

    func name(forBangumi id: Int) -> String {
        bangumiByID[id]?.displayName ?? ""
    }

    // MARK: - 履歴

    private enum Keys {
        static let lastBangumi = "home.lastVisitedBangumiID"
        static let modified = "home.dataModified"
    }

    private var cachedModified: Double {
        get { UserDefaults.standard.double(forKey: Keys.modified) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.modified) }
    }

    func rememberVisit(bangumiID: Int) {
        UserDefaults.standard.set(bangumiID, forKey: Keys.lastBangumi)
        restoreLastVisited()
    }

    private func restoreLastVisited() {
        let id = UserDefaults.standard.integer(forKey: Keys.lastBangumi)
        lastVisitedBangumi = id == 0 ? nil : bangumiByID[id]
    }
}
