//
//  AnitabiDataLoader.swift
//  anitabi
//
//  静的データ（全量ダウンロード → ローカル保持）を扱う層。`/d/g.json` に全作品と全地標の座標、
//  `/d/g0-g6.json` に地標の詳細が入る —— **g.json だけで地図は描ける**ので初回描画はそこで行い、
//  詳細は後からマージする。書式は位置ベースの配列なので、取り出しは全て範囲チェック付き。
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
    /// 全分割がサーバ側と同じ世代か。取得に失敗して古いキャッシュで代替した分割が
    /// 1 つでもあれば false —— 呼び出し側は `modified` を保存してはいけない（保存すると
    /// 次回以降「手元は最新」と誤判定して、その分割が永久に古いままになる）。
    var detailsAreCurrent: Bool = true
}

// MARK: - ローダー

actor AnitabiDataLoader {
    static let shared = AnitabiDataLoader()

    /// 配信ノード。先頭から順に試し、応答したノードをそのプロセスの間は使い続ける。
    /// - `ww.anitabi.cn` … 本命。
    /// - `w.junreimap.com` … ミラー。2026-08 時点で `ww.` と同一内容（作品 1507 件・`modified` 一致）。
    /// - `www.anitabi.cn` … 2026-08 時点では接続自体できないが、復活したら使えるので最後に置く。
    private static let origins = [
        "https://ww.anitabi.cn",
        "https://w.junreimap.com",
        "https://www.anitabi.cn",
    ]
    /// 直近に応答したノード。1 回のフェッチで当たったノードを以降の既定にして、
    /// 死んでいるノードへの往復を毎回繰り返さないようにする。
    private var preferredOriginIndex = 0
    private let detailShardCount = 7  // g0 … g6

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["Accept": "*/*"]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // `d` 側でキャッシュ制御する
        // パケット間の無通信タイムアウト。全ノード試して詰まっても最悪 45 秒で諦める。
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// 現在採用しているノード（スプライト画像の絶対 URL 組み立てにも使う）。
    private var preferredOrigin: String {
        Self.origins[min(preferredOriginIndex, Self.origins.count - 1)]
    }

    // MARK: キャッシュバスター

    /// Web 版 `HS()` と同一式。約 24 分ごとに変わる。
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

    /// ネットワークから取り直す。`cachedModified` がサーバ側と同じなら詳細の再取得を省き、
    /// `onList` は g.json のパースが終わった時点で 1 度だけ呼ぶ（地図の初回描画用）。
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
        var usedStaleShard = false
        for shard in 0..<detailShardCount {
            let data: Data?
            if detailsAreFresh, let cached = cachedData(for: .details(shard)) {
                data = cached
            } else if let fetched = try? await fetch(path: "/d/g\(shard).json", buster: buster) {
                store(fetched, for: .details(shard))
                data = fetched
            } else {
                // 取れなければ古いキャッシュで代替する。詳細（名前・剧照）が丸ごと欠けた
                // 地標を出すより、1 世代古い詳細を出す方がまし。
                log.warning("g\(shard).json の取得に失敗（古いキャッシュで代替）")
                data = cachedData(for: .details(shard))
                usedStaleShard = true
            }
            guard let data else {
                log.warning("g\(shard).json はキャッシュも無いため今回はスキップ")
                continue
            }
            Self.parsePointDetails(data, into: &details, modified: &modifiedByBangumi)
        }

        Self.merge(details: details, into: &dataset.points)
        dataset.modifiedByBangumi = modifiedByBangumi
        dataset.hasDetails = !details.isEmpty
        dataset.detailsAreCurrent = !usedStaleShard
        return dataset
    }

    // MARK: users.csv / bangumi-icons.json

    /// `/d/users.csv` → 投稿者 ID → ニックネームのマップ（約 1214 行）。
    /// 失敗時はディスクキャッシュへフォールバックする（成功時は上書き保存）。
    func loadUsers() async -> [Int: String] {
        let buster = Self.cacheBuster
        if let data = try? await fetch(path: "/d/users.csv", buster: buster),
           let map = Self.parseUsers(data), !map.isEmpty {
            store(data, for: .users)
            return map
        }
        log.warning("users.csv の取得に失敗（キャッシュへフォールバック）")
        if let cached = cachedData(for: .users), let map = Self.parseUsers(cached) {
            return map
        }
        return [:]
    }

    /// `/d/bangumi-icons.json` → 独自アイコンを持つ作品 ID 一覧とスプライト画像 URL。
    /// スプライト画像本体のダウンロードは本メソッドの範囲外（次段の `BangumiIconSprite` が担当）。
    func loadIconIndex() async -> (ids: [Int], spriteURL: URL)? {
        let buster = Self.cacheBuster
        // `src` は相対パスなので、**今 応答したノード**を基準に絶対 URL へ直す。
        if let data = try? await fetch(path: "/d/bangumi-icons.json", buster: buster),
           let result = Self.parseIconIndex(data, origin: preferredOrigin) {
            store(data, for: .icons)
            return result
        }
        log.warning("bangumi-icons.json の取得に失敗（キャッシュへフォールバック）")
        if let cached = cachedData(for: .icons),
           let result = Self.parseIconIndex(cached, origin: preferredOrigin) {
            return result
        }
        return nil
    }

    // MARK: ネットワーク

    /// 採用中のノードから順に全ノードを試す。1 つでも 2xx を返せばそれを採用ノードに昇格させ、
    /// 全滅した時だけ throw する（呼び出し側はそこでディスクキャッシュに退避する）。
    private func fetch(path: String, buster: String) async throws -> Data {
        let order = (0..<Self.origins.count).map { (preferredOriginIndex + $0) % Self.origins.count }
        var lastError: Error = AnitabiDataError.badStatus(path)

        for index in order {
            do {
                let data = try await fetch(path: path, buster: buster, originIndex: index)
                if index != preferredOriginIndex {
                    log.info("配信ノードを \(Self.origins[index]) に切り替えました")
                    preferredOriginIndex = index
                }
                return data
            } catch {
                log.warning("\(Self.origins[index])\(path) が使えません：\(error.localizedDescription)")
                lastError = error
            }
        }
        throw lastError
    }

    private func fetch(path: String, buster: String, originIndex: Int) async throws -> Data {
        guard let url = URL(string: "\(Self.origins[originIndex])\(path)?d=\(buster)") else {
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
        case users
        case icons

        var filename: String {
            switch self {
            case .list: "g.json"
            case .details(let i): "g\(i).json"
            case .users: "users.csv"
            case .icons: "bangumi-icons.json"
            }
        }
    }

    /// 全量データ・アイコンシート共通の置き場（`BangumiIconSprite` も同じディレクトリを使う）。
    /// 無ければ作る。作れなければ nil ＝ キャッシュ無しで動く。
    nonisolated static var cacheDirectory: URL? {
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
        guard let dir = Self.cacheDirectory else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(slot.filename))
    }

    private func store(_ data: Data, for slot: CacheSlot) {
        guard let dir = Self.cacheDirectory else { return }
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
    var isFolder: Bool = false
    var folderName: String?
    var mid: String?
    var uid: Int?
    var fid: String?
    var timecodeS: Int?
    var note: String?
    var origin: String?
    var originLink: String?
}

extension AnitabiDataLoader {

    /// `/d/g.json` → 作品一覧 + 全地標の座標。ルートは `[bangumiLiteList, pageSize, modified]` で、
    /// 1 作品は 18 要素：`0:id 1:cn 2:en 3:title 4:city 5:color 6:cover 7:score 8:cat 9:lat
    /// 10:lng 11:zoom 12:points 13:abbr 14:tags 15:priority 16:icon 17:tAbbr`（14/16/17 は未使用）。
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
                en: record.string(2),
                title: record.string(3),
                city: record.string(4),
                colorHex: record.string(5),
                cover: record.string(6),
                score: record.double(7),
                cat: record.string(8),
                center: record.coordinate(lat: 9, lng: 10),
                zoom: record.double(11),
                points: geos,
                abbr: record.string(13),
                priority: record.int(15) ?? 999
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

    /// `/d/g{n}.json` → 地標 ID ごとの詳細。1 セルは `[bangumiId, theme, points[], modified]`、
    /// 1 地標は 15 要素：`0:id 1:name 2:folderName 3:isFolder 4:mid 5:uid 6:image 7:fid 8:ep
    /// 9:timecodeS 10:note 11:origin 12:originLink 13:cn`（**web の JS 解析とは並びが違う**）。
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
                    nameCN: point.string(13),
                    image: point.string(6),
                    ep: point.episode(8),
                    isFolder: point.bool(3),
                    folderName: point.string(2),
                    mid: point.string(4),
                    uid: point.int(5),
                    fid: point.string(7),
                    timecodeS: point.int(9),
                    note: point.string(10),
                    origin: point.string(11),
                    originLink: point.string(12)
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
            points[index].isFolder = detail.isFolder
            points[index].folderName = detail.folderName
            points[index].mid = detail.mid
            points[index].uid = detail.uid
            points[index].fid = detail.fid
            points[index].timecodeS = detail.timecodeS
            points[index].note = detail.note
            points[index].origin = detail.origin
            points[index].originLink = detail.originLink
        }
    }
}

// MARK: - users.csv / bangumi-icons.json パース

extension AnitabiDataLoader {

    /// `id,昵称` 形式の CSV。昵称にカンマを含み得るため **最初のカンマだけ**で分割する。
    static func parseUsers(_ data: Data) -> [Int: String]? {
        guard let text = String(data: data, encoding: .utf8) else {
            log.error("users.csv を UTF-8 として読めませんでした")
            return nil
        }
        var result: [Int: String] = [:]
        text.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let commaIndex = line.firstIndex(of: ",") else { return }
            guard let id = Int(line[line.startIndex..<commaIndex]) else { return }
            guard let name = String(line[line.index(after: commaIndex)...]).nilIfBlank else { return }
            result[id] = name
        }
        return result
    }

    /// `{ "src": "/d/bangumi-icons.webp?v=hash", "ids": [id, ...] }`。
    /// `src` は相対パスで来るため、渡された配信ノード基準の絶対 URL に直す。
    static func parseIconIndex(_ data: Data, origin: String) -> (ids: [Int], spriteURL: URL)? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let src = root["src"] as? String,
            let rawIDs = root["ids"] as? [Any]
        else {
            log.error("bangumi-icons.json を読めませんでした")
            return nil
        }
        guard let url = absoluteDPath(src, origin: origin) else { return nil }
        let ids = rawIDs.compactMap { value -> Int? in
            switch value {
            case let v as Int: v
            case let v as Double: Int(v)
            case let v as String: Int(v)
            default: nil
            }
        }
        return (ids: ids, spriteURL: url)
    }

    /// `/d/...` の相対パスを指定ノード基準の絶対 URL にする。
    private static func absoluteDPath(_ path: String, origin: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if path.hasPrefix("/") {
            return URL(string: origin + path)
        }
        return URL(string: origin + "/" + path)
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

    /// `isFolder` などのフラグ。Bool / 0-1 の Int・Double / "true"-"1" 文字列を許容し、
    /// それ以外（未設定含む）は false に降格する。
    func bool(_ index: Int) -> Bool {
        switch value(index) {
        case let v as Bool: v
        case let v as Int: v != 0
        case let v as Double: v != 0
        case let v as String: v == "true" || v == "1"
        default: false
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
