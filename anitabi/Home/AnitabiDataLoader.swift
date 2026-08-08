//
//  AnitabiDataLoader.swift
//  anitabi
//
//  anitabi の静的データ（全量ダウンロード → ローカル保持）を扱う層。
//  Web 版と同じく `/d/g.json` に全作品と全地標の座標が、`/d/g0-g6.json` に地標の詳細が入る。
//  つまり **g.json だけで地図は描ける** ので、初回描画は g.json 完了時点で行い、
//  詳細（名前・スクショ・話数）は g0-g6 が届き次第あとからマージする。
//
//  データ書式は位置ベースの配列。フィールド位置は docs/anitabi-map-api.md §3 と
//  docs/anitabi-web-full-analysis.md §3.2 の解析結果に準拠する。書式が変わっても
//  クラッシュしないよう、取り出しは全て範囲チェック付きの optional キャストで行う。
//

import CoreLocation
import Foundation
import OSLog

private let log = Logger(subsystem: "cn.anitabi.app", category: "data")

// MARK: - 取得結果

struct AnitabiDataset: Sendable {
    var bangumis: [BangumiLite]
    var points: [ScenePoint]
    /// g.json の `modified`。差分判定に使う。
    var modified: Double
    /// 作品ごとの最終更新（g0-g6 の各セル 4 番目）。「最近更新」の並びに使う。
    var modifiedByBangumi: [Int: Double] = [:]
    /// 地標の詳細（g0-g6）までマージ済みか。
    var hasDetails: Bool
}

// MARK: - ローダー

actor AnitabiDataLoader {
    static let shared = AnitabiDataLoader()

    private let origin = "https://www.anitabi.cn"
    private let detailShardCount = 7  // g0 … g6

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Accept": "*/*"]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // `d` 側でキャッシュ制御する
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    // MARK: キャッシュバスター

    /// Web 版 `HS()` と同一式。約 24 分ごとに変わる。
    /// （本家は ms を `/1e3/60/24` しており実質 24 分刻み。Swift 側は既に秒なので同値になる。）
    nonisolated static var cacheBuster: String {
        String(Int(Date().timeIntervalSince1970 / 60 / 24) + 6, radix: 36)
    }

    // MARK: 公開 API

    /// ディスクキャッシュだけで組み立てる。起動直後の即描画用。
    func loadFromCache() -> AnitabiDataset? {
        guard let listData = cachedData(for: .list) else { return nil }
        guard var dataset = Self.parseBangumiList(listData) else { return nil }

        var details: [String: PointDetail] = [:]
        var modifiedByBangumi: [Int: Double] = [:]
        for shard in 0..<detailShardCount {
            guard let data = cachedData(for: .details(shard)) else { continue }
            Self.parsePointDetails(data, into: &details, modified: &modifiedByBangumi)
        }
        if !details.isEmpty {
            Self.merge(details: details, into: &dataset.points)
            dataset.modifiedByBangumi = modifiedByBangumi
            dataset.hasDetails = true
        }
        return dataset
    }

    /// ネットワークから取り直す。
    /// - Parameters:
    ///   - cachedModified: 手元のデータの `modified`。サーバ側が新しくないなら詳細の再取得を省く。
    ///   - onList: g.json のパースが終わった時点で 1 度だけ呼ばれる（地図の初回描画用）。
    func refresh(
        cachedModified: Double,
        onList: @Sendable (AnitabiDataset) -> Void
    ) async throws -> AnitabiDataset {
        let buster = Self.cacheBuster

        let listData = try await fetch(path: "/d/g.json", buster: buster)
        guard var dataset = Self.parseBangumiList(listData) else {
            throw AnitabiDataError.malformed("g.json")
        }
        store(listData, for: .list)
        onList(dataset)

        // 手元が最新なら詳細はキャッシュを使い回す（本家の増分判定と同じ）。
        let detailsAreFresh = dataset.modified <= cachedModified

        var details: [String: PointDetail] = [:]
        var modifiedByBangumi: [Int: Double] = [:]
        for shard in 0..<detailShardCount {
            let data: Data?
            if detailsAreFresh, let cached = cachedData(for: .details(shard)) {
                data = cached
            } else {
                data = try? await fetch(path: "/d/g\(shard).json", buster: buster)
                if let data { store(data, for: .details(shard)) }
            }
            guard let data else {
                log.warning("g\(shard).json の取得に失敗（この分割はスキップ）")
                continue
            }
            Self.parsePointDetails(data, into: &details, modified: &modifiedByBangumi)
        }

        Self.merge(details: details, into: &dataset.points)
        dataset.modifiedByBangumi = modifiedByBangumi
        dataset.hasDetails = !details.isEmpty
        return dataset
    }

    // MARK: ネットワーク

    private func fetch(path: String, buster: String) async throws -> Data {
        guard let url = URL(string: "\(origin)\(path)?d=\(buster)") else {
            throw AnitabiDataError.malformed(path)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AnitabiDataError.badStatus(path)
        }
        return data
    }

    // MARK: ディスクキャッシュ

    private enum CacheSlot {
        case list
        case details(Int)

        var filename: String {
            switch self {
            case .list: "g.json"
            case .details(let i): "g\(i).json"
            }
        }
    }

    private var cacheDirectory: URL? {
        guard let base = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("anitabi-data", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cachedData(for slot: CacheSlot) -> Data? {
        guard let dir = cacheDirectory else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(slot.filename))
    }

    private func store(_ data: Data, for slot: CacheSlot) {
        guard let dir = cacheDirectory else { return }
        try? data.write(to: dir.appendingPathComponent(slot.filename), options: .atomic)
    }
}

// MARK: - エラー

enum AnitabiDataError: LocalizedError {
    case malformed(String)
    case badStatus(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let f): "データ形式が想定と異なります（\(f)）"
        case .badStatus(let f): "データの取得に失敗しました（\(f)）"
        }
    }
}

// MARK: - パース

/// g0-g6 側の地標詳細。
struct PointDetail: Sendable {
    var name: String?
    var nameCN: String?
    var image: String?
    var ep: String?
}

extension AnitabiDataLoader {

    /// `/d/g.json` → 作品一覧 + 全地標の座標。
    ///
    /// ルートは `[bangumiLiteList, pageSize, modified]`。
    /// 1 作品のレコード（18 要素）のうち本アプリが使うのは
    /// `0:id 1:cn 3:title 4:city 5:color 6:cover 8:cat 9:lat 10:lng 11:zoom 12:points`。
    static func parseBangumiList(_ data: Data) -> AnitabiDataset? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let rawList = root.first as? [Any]
        else {
            log.error("g.json のルート配列を読めませんでした")
            return nil
        }

        let modified = root.count > 2 ? (root[2] as? Double ?? 0) : 0

        var bangumis: [BangumiLite] = []
        var points: [ScenePoint] = []
        bangumis.reserveCapacity(rawList.count)
        points.reserveCapacity(rawList.count * 30)

        for case let record as [Any] in rawList {
            guard let id = record.int(0) else { continue }

            let geos = parsePointGeos(record.value(12))
            let bangumi = BangumiLite(
                id: id,
                cn: record.string(1),
                title: record.string(3),
                city: record.string(4),
                colorHex: record.string(5),
                cover: record.string(6),
                cat: record.string(8),
                center: record.coordinate(lat: 9, lng: 10),
                zoom: record.double(11),
                points: geos
            )
            bangumis.append(bangumi)

            for geo in geos {
                points.append(
                    ScenePoint(
                        id: geo.id,
                        bangumiID: id,
                        lat: geo.lat,
                        lng: geo.lng,
                        priority: geo.priority
                    )
                )
            }
        }

        log.info("g.json: 作品 \(bangumis.count) 件 / 地標 \(points.count) 点")
        return AnitabiDataset(bangumis: bangumis, points: points, modified: modified, hasDetails: false)
    }

    /// 作品レコードの 12 番目。`[id, lat, lng, priority]` が 4 個ずつフラットに並ぶ。
    private static func parsePointGeos(_ raw: Any?) -> [PointGeo] {
        guard let flat = raw as? [Any], flat.count >= 4 else { return [] }
        var result: [PointGeo] = []
        result.reserveCapacity(flat.count / 4)

        var index = 0
        while index + 3 < flat.count {
            defer { index += 4 }
            guard
                let id = flat.string(index),
                let lat = flat.double(index + 1),
                let lng = flat.double(index + 2),
                CLLocationCoordinate2DIsValid(
                    CLLocationCoordinate2D(latitude: lat, longitude: lng)
                ),
                lat != 0 || lng != 0
            else { continue }
            result.append(
                PointGeo(id: id, lat: lat, lng: lng, priority: flat.int(index + 3) ?? 0)
            )
        }
        return result
    }

    /// `/d/g{n}.json` → 地標 ID ごとの詳細。
    ///
    /// ルートはセルの配列。1 セルは `[bangumiId, theme, points[], modified]`、
    /// 1 地標は 15 要素で `0:id 1:name 2:cn 7:image 9:ep`。
    static func parsePointDetails(
        _ data: Data,
        into store: inout [String: PointDetail],
        modified: inout [Int: Double]
    ) {
        guard let cells = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            log.error("地標詳細のルート配列を読めませんでした")
            return
        }

        for case let cell as [Any] in cells {
            if let bangumiID = cell.int(0), let cellModified = cell.double(3) {
                modified[bangumiID] = cellModified
            }
            guard let rawPoints = cell.value(2) as? [Any] else { continue }
            for case let point as [Any] in rawPoints {
                guard let id = point.string(0) else { continue }
                store[id] = PointDetail(
                    name: point.string(1),
                    nameCN: point.string(2),
                    image: point.string(7),
                    ep: point.episode(9)
                )
            }
        }
    }

    static func merge(details: [String: PointDetail], into points: inout [ScenePoint]) {
        guard !details.isEmpty else { return }
        for index in points.indices {
            guard let detail = details[points[index].id] else { continue }
            points[index].name = detail.name
            points[index].nameCN = detail.nameCN
            points[index].image = detail.image
            points[index].ep = detail.ep
        }
    }
}

// MARK: - 位置ベース配列の安全な取り出し

private extension Array where Element == Any {
    func value(_ index: Int) -> Any? {
        indices.contains(index) ? self[index] : nil
    }

    func string(_ index: Int) -> String? {
        (value(index) as? String)?.nilIfBlank
    }

    func double(_ index: Int) -> Double? {
        switch value(index) {
        case let v as Double: v
        case let v as Int: Double(v)
        case let v as String: Double(v)
        default: nil
        }
    }

    func int(_ index: Int) -> Int? {
        switch value(index) {
        case let v as Int: v
        case let v as Double: Int(v)
        case let v as String: Int(v)
        default: nil
        }
    }

    /// 話数は数値でもタイムコード文字列でも来る。
    func episode(_ index: Int) -> String? {
        switch value(index) {
        case let v as String: v.nilIfBlank
        case let v as Int: String(v)
        case let v as Double: v == v.rounded() ? String(Int(v)) : String(v)
        default: nil
        }
    }

    func coordinate(lat: Int, lng: Int) -> CLLocationCoordinate2D? {
        guard
            let latitude = double(lat), let longitude = double(lng),
            latitude != 0 || longitude != 0
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
