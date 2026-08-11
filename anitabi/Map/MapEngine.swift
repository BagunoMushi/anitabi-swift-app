//
//  MapEngine.swift
//  anitabi
//
//  「いまこのカメラで、どの標注を出すか」だけを決める純計算の層（actor 隔離）。**数字クラスタ泡は
//  作らず**、密度は Web 版と同じ「揭示阶梯」だけで制御する。出力は「このフレームで在るべき集合」
//  で、add/remove の差分は `MapCanvas.Coordinator` が取る。
//

import CoreLocation
import Foundation
import MapKit

// MARK: - 入力データ

/// 作品標 1 個ぶんの種。`AnitabiStore` の `BangumiLite` から地図に必要な分だけ抜いたもの。
struct MapWorkSeed: Sendable, Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let name: String
    let colorHex: String?
    let hasIcon: Bool
    /// 揭示阶梯に掛ける値（m）＝作品が持つ地標の最近傍距離の最大値、つまり「その作品が
    /// どれだけ広く散らばっているか」。g.json の `priority`（999 既定の順位）は阶梯の桁と
    /// 合わないので使わない。
    let spread: Int
}

/// 地図に流し込むデータ一式。5 万点の `==` は高すぎるので中身は比較せず `version` で判定する。
struct MapDataset: Sendable {
    var points: [ScenePoint]
    var works: [MapWorkSeed]
    var version: Int

    static let empty = MapDataset(points: [], works: [], version: 0)
}

/// 経緯度の矩形。`MKCoordinateRegion` を跨線スレッドで持ち回らないための最小表現。
struct MapViewport: Sendable {
    var minLat: Double
    var maxLat: Double
    var minLng: Double
    var maxLng: Double

    init(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLng = minLng
        self.maxLng = maxLng
    }

    /// 視口を中心から `scale` 倍に広げたもの（先読み用）。
    init(region: MKCoordinateRegion, scale: Double = 1.0) {
        let latHalf = min(region.span.latitudeDelta * scale / 2, 90)
        let lngHalf = min(region.span.longitudeDelta * scale / 2, 180)
        minLat = region.center.latitude - latHalf
        maxLat = region.center.latitude + latHalf
        minLng = region.center.longitude - lngHalf
        maxLng = region.center.longitude + lngHalf
    }

    func contains(lat: Double, lng: Double) -> Bool {
        lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
    }
}

// MARK: - Web スタイルの寸法表

/// Web 版 Mapbox スタイルに書かれている「ズーム → 寸法」の逐字移植。Mapbox GL の長さ単位は
/// CSS px ＝ iOS の pt と 1:1 なので、値は換算せずそのまま使う。
enum MapMarkerMetrics {

    /// Mapbox 旧式 `{base, stops}` の指数補間。両端の外側では端の値で頭打ち。
    private static func interpolate(_ zoom: Double, base: Double, stops: [(z: Double, v: Double)]) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if zoom <= first.z { return first.v }
        if zoom >= last.z { return last.v }
        for index in 1..<stops.count where zoom <= stops[index].z {
            let low = stops[index - 1]
            let high = stops[index]
            let ratio = (pow(base, zoom - low.z) - 1) / (pow(base, high.z - low.z) - 1)
            return low.v + (high.v - low.v) * ratio
        }
        return last.v
    }

    /// Web `bangumi-point` 層の `circle-radius`。返すのは**半径**。
    static func dotRadius(zoom: Double) -> Double {
        interpolate(zoom, base: 1.75, stops: [(12, 4), (18, 8), (22, 16)])
    }

    /// Web `bangumi-point` 層の `circle-stroke-width`。Mapbox の circle 描边は**半径の外側**に
    /// 足されるので、見た目の直径は `2×(radius + stroke)`。
    static func dotStrokeWidth(zoom: Double) -> Double {
        interpolate(zoom, base: 1.75, stops: [(12, 1.5), (18, 3), (22, 6)])
    }

    /// 劇照標 1 段ぶんの寸法。**意匠は 2 段とも同じ**（作品色の枠 ＋ 滴 ＋ 画像の内三角）で、
    /// 違うのは寸法だけ —— Web は大カード無枠・小泡有枠の 2 意匠だが、同画面での混在は
    /// おかしいという指摘で 1 本に統一した。枠色＝作品色なので帰属が一目で分かる。
    struct PhotoPlate {
        var bodySize: CGSize
        var cornerRadius: CGFloat
        var borderWidth: CGFloat
        /// 本体の下に付く作品色の滴。
        var dripSize: CGSize
        /// 滴の上に載る、画像で塗られた三角。`overlap` ぶん本体に食い込む。
        var innerTailSize: CGSize
        var innerTailOverlap: CGFloat
        /// 尾の先端が座標。そこからさらに持ち上げる量。
        var anchorLift: CGFloat = 0
        /// 絵全体の寸法（滴の下の余白まで含む）。
        var totalSize: CGSize

        /// ブラウズ時（z>18）の大カード。Web `points-image` の 160×(120+14)px ÷ pixelRatio 2。
        /// 滴と内三角の比率は小泡からカード幅へ拡大したもの。
        static let card = PhotoPlate(
            bodySize: CGSize(width: 80, height: 60),
            cornerRadius: 4,
            borderWidth: 1,
            dripSize: CGSize(width: 14, height: 7),
            innerTailSize: CGSize(width: 11, height: 7.5),
            innerTailOverlap: 1.7,
            // Web の `icon-offset: [0,-1]` ぶん。
            anchorLift: 1,
            totalSize: CGSize(width: 80, height: 67)
        )

        /// 作品モードの小泡。Web `bangumi-points-theme` の 100×(76+11+2)px ÷ pixelRatio 2
        /// （既定値は 72×54 だが、実データ 891/1019 件が 100×76 なのでそちらを採る）。
        /// 枠線 2px・角丸 5.5px はスプライトに焼き込まれている。
        static let bubble = PhotoPlate(
            bodySize: CGSize(width: 50, height: 38),
            cornerRadius: 3,
            borderWidth: 1,
            dripSize: CGSize(width: 11, height: 5.5),
            innerTailSize: CGSize(width: 9, height: 6),
            innerTailOverlap: 1.35,
            totalSize: CGSize(width: 50, height: 44.5)
        )
    }

    /// Web `bangumis` 層（作品標）の寸法。アイコンは `bangumi-icons` スプライトの 60×60 セルを
    /// `pixelRatio: 2` で載せるので 30pt。文字は 11px ＋ 白ハロー。
    enum WorkMarker {
        static let iconSize: CGFloat = 30
        static let textSize: CGFloat = 11
    }
}

// MARK: - 揭示阶梯

/// Web 版の揭示表をそのまま持つ。値は「最近傍までの距離（m）がこれを**超える**点／作品だけ出す」。
enum MapRevealLadder {

    /// 地標の閾値。Web `bangumi-point` の filter の逐字移植。z17 以上は全部出す。
    static func pointThreshold(zoom: Double) -> Double {
        switch zoom {
        case ..<2: 60_000
        case ..<3: 36_000
        case ..<4: 24_000
        case ..<5: 12_000
        case ..<6: 6_000
        case ..<7: 3_000
        case ..<8: 1_500
        case ..<9: 600
        case ..<10: 300
        case ..<11: 150
        case ..<12: 100
        case ..<13: 40
        case ..<14: 20
        case ..<15: 10
        case ..<16: 5
        case ..<17: 3
        // 閾値は「超える」判定なので、priority 0（座標が完全に重なっている点）まで拾うため -1。
        default: -1
        }
    }

    /// 作品標の閾値。Web `bangumis` の filter ＋ `maxzoom: 13`。
    /// z13 以上は nil ＝ 出さない（近接では地標が主役で、作品標は邪魔になる）。
    static func workThreshold(zoom: Double) -> Double? {
        switch zoom {
        case ..<2: 760_000
        case ..<3: 420_000
        case ..<3.5: 160_000
        case ..<4: 130_000
        case ..<4.5: 100_000
        case ..<5: 70_000
        case ..<6: 55_000
        case ..<7: 28_800
        case ..<8: 14_400
        case ..<9: 7_200
        case ..<10: 3_600
        case ..<11: 1_800
        case ..<12: 900
        // Web は `maxzoom: 13` ＝ z13 ちょうどから層ごと消える。
        case ..<13: 450
        default: nil
        }
    }

    // MARK: 劇照の揭示

    /// 絵が小泡から大カードへ切り替わるズーム（Web の層の境目そのまま）。
    static let photoCardZoom: Double = 18

    /// ブラウズ時に劇照が**出始める**ズーム。**web から意図的に離れる** —— web は z≤18 で 1 枚も
    /// 出さないが、それだと「とても大きく寄せないと見えない」。定位钮の着地と一覧からの最遠寄りを
    /// 両方拾える 15 に置く。密度は priority 閾値と MapKit の衝突回避が抑えるので破綻しない。
    static let photoRevealZoom: Double = 15

    /// 大カードの priority 閾値（Web の `3 × 2^(19−z)` そのまま）。点の最近傍距離 m がこれ
    /// **以上**なら出す。
    static func photoCardPriorityThreshold(zoom: Double) -> Double {
        3 * pow(2, 19 - zoom)
    }

    /// 作品モードの小泡（Web `bangumi-points-theme`）の揭示阶梯。値は m。
    static func photoBubbleThreshold(zoom: Double) -> Double {
        switch zoom {
        case ..<3: 48_000
        case ..<4: 24_000
        case ..<5: 12_000
        case ..<6: 6_000
        case ..<7: 3_000
        case ..<8: 1_600
        case ..<9: 800
        case ..<10: 400
        case ..<11: 200
        case ..<12: 100
        case ..<13: 50
        case ..<14: 20
        case ..<15: 10
        case ..<16: 5
        case ..<17: 3
        case ..<18: 2
        case ..<19: 1
        default: 0
        }
    }

    /// MKFeatureDisplayPriority。同じ場所で競合したとき、孤立している標注ほど残る。
    /// Web の式は上限がちょうど 1000 になるが、MapKit の 1000 は `.required`＝衝突しても絶対に
    /// 隠さないという特別な意味なので、上限だけ 999 に落とす。
    static func displayPriority(forPriority p: Int) -> Float {
        let normalized = min(1, log10(Double(max(p, 0)) + 1) / 5)
        return min(Float(250 + 750 * normalized), 999)
    }
}

// MARK: - 要求と結果

struct MapEngineRequest: Sendable {
    var viewport: MapViewport
    var zoom: Double
    /// 作品モード。この作品の点だけを阶梯を無視して全量出す。
    var focusedWorkID: Int?
    /// 複数作品フィルタ（chips）。空でなければ、この集合の点だけを阶梯を無視して出す。
    var selectedWorkIDs: Set<Int>
    var isPhotoLayerVisible: Bool
    /// 選択中の地標。上限で切り落とされないよう必ず結果に含める。
    var selectedPointID: String?

    /// 保険上限。ここを超えると描画コストではなく**画面の情報密度**が破綻する。
    var pointLimit = 600
    /// テクスチャ枚数の保険。Web の 2 層に枚数上限は無く揭示阶梯だけで疎になるので、
    /// 阶梯が効いている限り当たらない値にしてある（実測は密な所でも 100 枚未満）。
    var photoLimit = 120
    var workLimit = 32
}

struct MapPointPlan: Sendable {
    let point: ScenePoint
    /// 劇照サムネイル形態で出すか（判定は `MapEngine.photoForms`）。
    /// どちらの絵で描くかは `PointMarkerView` がズームから決める。
    let usesPhoto: Bool
}

struct MapEngineFrame: Sendable {
    var points: [MapPointPlan]
    var works: [MapWorkSeed]
    var zoom: Double
    /// 作品モードのとき、その作品の全点（圧暗レイヤーの凸包に使う）。
    var focusedWorkCoordinates: [CLLocationCoordinate2D]?
}

// MARK: - エンジン

actor MapEngine {

    private var points: [ScenePoint] = []
    private var works: [MapWorkSeed] = []
    private var version = -1

    /// priority 降順の並び（値は `points` の添字）。広域では先頭の数十件しか閾値を超えない。
    private var orderByPriority: [Int32] = []
    /// 上と同じ並びの priority 値（二分探索で「閾値を超える件数」を出す）。値は最近傍までの
    /// 距離（m）で離島の点は 1e10 に達するので **Int32 には収まらない**。
    private var priorityDescending: [Int] = []

    /// 0.02° グリッド。キーは緯度セル・経度セルを 32bit ずつ詰めたもの。
    private var grid: [Int64: [Int32]] = [:]
    private static let cellSize = 0.02

    /// 作品 ID → その作品の点の添字。作品モードで阶梯を跳ばすときに使う。
    private var indicesByWork: [Int: [Int32]] = [:]
    /// 地標 ID → 添字。選択中の点を毎フレーム線形探索しないため。
    private var indexByID: [String: Int32] = [:]

    /// 作品モードの小泡用に測り直した priority のキャッシュ（作品 ID 集合ごと）。
    /// O(n²) なので選択が変わったときだけ計算する。
    private var themePriorityCache: (works: Set<Int>, values: [String: Int])?

    // MARK: 索引構築

    /// データが差し替わったときだけ索引を建て直す。5 万点で数十 ms 掛かるが actor 上なので
    /// メインスレッドは止まらない。
    func load(_ dataset: MapDataset) {
        guard dataset.version != version else { return }
        version = dataset.version
        points = dataset.points
        works = dataset.works

        var order = Array(Int32(0)..<Int32(points.count))
        order.sort { points[Int($0)].priority > points[Int($1)].priority }
        orderByPriority = order
        priorityDescending = order.map { points[Int($0)].priority }

        var newGrid: [Int64: [Int32]] = [:]
        newGrid.reserveCapacity(points.count / 4)
        var byWork: [Int: [Int32]] = [:]
        byWork.reserveCapacity(works.count)
        var byID: [String: Int32] = [:]
        byID.reserveCapacity(points.count)
        for (offset, point) in points.enumerated() {
            let index = Int32(offset)
            newGrid[Self.cellKey(lat: point.lat, lng: point.lng), default: []].append(index)
            byWork[point.bangumiID, default: []].append(index)
            byID[point.id] = index
        }
        grid = newGrid
        indicesByWork = byWork
        indexByID = byID
        themePriorityCache = nil
    }

    // MARK: フレーム計算

    func frame(for request: MapEngineRequest) -> MapEngineFrame {
        guard !points.isEmpty else {
            return MapEngineFrame(points: [], works: [], zoom: request.zoom, focusedWorkCoordinates: nil)
        }

        let filterIDs: Set<Int>? = {
            if let focused = request.focusedWorkID { return [focused] }
            return request.selectedWorkIDs.isEmpty ? nil : request.selectedWorkIDs
        }()

        let selected = filterIDs == nil
            ? ladderPoints(request: request)
            : filteredPoints(workIDs: filterIDs!, viewport: request.viewport, limit: request.pointLimit)

        var plans = photoForms(for: selected, request: request, filterIDs: filterIDs)

        // 選択中の点は絶対に消さない（カードが開いたまま標注だけ消えるのを防ぐ）。
        if let selectedID = request.selectedPointID,
           !plans.contains(where: { $0.point.id == selectedID }),
           let index = indexByID[selectedID] {
            plans.append(MapPointPlan(point: points[Int(index)], usesPhoto: false))
        }

        let visibleWorks = filterIDs == nil ? ladderWorks(request: request) : []

        var focusedCoordinates: [CLLocationCoordinate2D]?
        if let focused = request.focusedWorkID, let indices = indicesByWork[focused] {
            focusedCoordinates = indices.map { points[Int($0)].coordinate }
        }

        return MapEngineFrame(
            points: plans,
            works: visibleWorks,
            zoom: request.zoom,
            focusedWorkCoordinates: focusedCoordinates
        )
    }

    // MARK: 地標の絞り込み

    private func ladderPoints(request: MapEngineRequest) -> [ScenePoint] {
        let threshold = Int(MapRevealLadder.pointThreshold(zoom: request.zoom))
        let candidates = candidateIndices(viewport: request.viewport, threshold: threshold)

        var picked: [ScenePoint] = []
        picked.reserveCapacity(min(candidates.count, request.pointLimit))
        for index in candidates {
            let point = points[Int(index)]
            guard point.priority > threshold else { continue }
            guard request.viewport.contains(lat: point.lat, lng: point.lng) else { continue }
            picked.append(point)
        }

        guard picked.count > request.pointLimit else { return picked }
        // 上限に当たったら「孤立している点」から残す ＝ 間引いても地図の骨格が保たれる。
        picked.sort { $0.priority > $1.priority }
        return Array(picked.prefix(request.pointLimit))
    }

    /// 作品モード / bids モード。阶梯を無視して対象作品の点を全部出す（上限だけは掛ける）。
    private func filteredPoints(workIDs: Set<Int>, viewport: MapViewport, limit: Int) -> [ScenePoint] {
        var picked: [ScenePoint] = []
        for workID in workIDs {
            guard let indices = indicesByWork[workID] else { continue }
            for index in indices {
                let point = points[Int(index)]
                guard viewport.contains(lat: point.lat, lng: point.lng) else { continue }
                picked.append(point)
            }
        }
        guard picked.count > limit else { return picked }
        picked.sort { $0.priority > $1.priority }
        return Array(picked.prefix(limit))
    }

    /// 候補の取り方を「priority 上位の走査」と「グリッド走査」で選ぶ。
    /// 広域＝閾値が高く上位数十件しか通らない、近接＝セル数が少ない、と得意領域が逆なので、
    /// 見積もりコストが小さい方を毎回選ぶ。
    private func candidateIndices(viewport: MapViewport, threshold: Int) -> ArraySlice<Int32> {
        let prefixCount = countAbove(threshold)

        let latCells = Int(((viewport.maxLat - viewport.minLat) / Self.cellSize).rounded(.up)) + 1
        let lngCells = Int(((viewport.maxLng - viewport.minLng) / Self.cellSize).rounded(.up)) + 1
        let cellCount = latCells * lngCells

        if prefixCount <= cellCount {
            return orderByPriority[0..<prefixCount]
        }
        return gridIndices(viewport: viewport)[...]
    }

    /// priority > threshold の件数（降順配列なので二分探索）。
    private func countAbove(_ threshold: Int) -> Int {
        var low = 0
        var high = priorityDescending.count
        while low < high {
            let mid = (low + high) / 2
            if priorityDescending[mid] > threshold { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private func gridIndices(viewport: MapViewport) -> [Int32] {
        let latStart = Int32(floor(viewport.minLat / Self.cellSize))
        let latEnd = Int32(floor(viewport.maxLat / Self.cellSize))
        let lngStart = Int32(floor(viewport.minLng / Self.cellSize))
        let lngEnd = Int32(floor(viewport.maxLng / Self.cellSize))

        var result: [Int32] = []
        result.reserveCapacity(1024)
        var latCell = latStart
        while latCell <= latEnd {
            var lngCell = lngStart
            while lngCell <= lngEnd {
                if let bucket = grid[Self.key(latCell: latCell, lngCell: lngCell)] {
                    result.append(contentsOf: bucket)
                }
                lngCell += 1
            }
            latCell += 1
        }
        return result
    }

    private static func cellKey(lat: Double, lng: Double) -> Int64 {
        key(latCell: Int32(floor(lat / cellSize)), lngCell: Int32(floor(lng / cellSize)))
    }

    private static func key(latCell: Int32, lngCell: Int32) -> Int64 {
        (Int64(latCell) << 32) | Int64(UInt32(bitPattern: lngCell))
    }

    // MARK: 形態の割り当て

    /// 「どの点を劇照で出すか」を決める。土台は Web の 2 層（z18 でバトンを渡す）—— z>18 は全点の
    /// priority 閾値、z≤18 は作品内で測り直した最近傍距離で間引く。**出始める線だけ web から外し**
    /// `photoRevealZoom` から出すが、判定式は続けて使うので境目は連続し寸法だけが変わる。
    private func photoForms(
        for selected: [ScenePoint],
        request: MapEngineRequest,
        filterIDs: Set<Int>?
    ) -> [MapPointPlan] {
        guard request.isPhotoLayerVisible else {
            return selected.map { MapPointPlan(point: $0, usesPhoto: false) }
        }

        // 全点の priority で間引く経路（大カードと、ブラウズ時の小泡）。作品モードは z18 以下では
        // 下の「作品内で測り直す」経路を使う —— そちらの方が同じ作品の点を多く残せる。
        let usesGlobalPriority = request.zoom > MapRevealLadder.photoCardZoom
            || (filterIDs == nil && request.zoom > MapRevealLadder.photoRevealZoom)

        var eligible: [(offset: Int, rank: Int)] = []
        if usesGlobalPriority {
            // `points-image` 相当。作品モードでも z>18 はここに合流する（Web も同じ）。
            let threshold = MapRevealLadder.photoCardPriorityThreshold(zoom: request.zoom)
            for (offset, point) in selected.enumerated()
            where point.image != nil && Double(point.priority) >= threshold {
                eligible.append((offset, point.priority))
            }
        } else if let filterIDs {
            // `bangumi-points-theme` 相当。作品を選んでいるときだけ。
            let threshold = MapRevealLadder.photoBubbleThreshold(zoom: request.zoom)
            let priorities = themePriorities(for: filterIDs)
            for (offset, point) in selected.enumerated() where point.image != nil {
                guard let rank = priorities[point.id], Double(rank) > threshold else { continue }
                eligible.append((offset, rank))
            }
        }

        guard !eligible.isEmpty else {
            return selected.map { MapPointPlan(point: $0, usesPhoto: false) }
        }
        if eligible.count > request.photoLimit {
            eligible.sort { $0.rank > $1.rank }
            eligible = Array(eligible.prefix(request.photoLimit))
        }
        let promoted = Set(eligible.map(\.offset))
        return selected.enumerated().map {
            MapPointPlan(point: $0.element, usesPhoto: promoted.contains($0.offset))
        }
    }

    /// 小泡の間引きに使う priority を Web の `A()` どおりに測り直す。**点が元から持っている値
    /// （全 5 万点での最近傍距離）ではない** —— その作品の画像点だけで取り直すので値が大きくなり、
    /// 広域でも数十枚残る。手順は「緯度降順に並べ、南から順にそれまで見た点への最短距離を測る」。
    private func themePriorities(for workIDs: Set<Int>) -> [String: Int] {
        if let cache = themePriorityCache, cache.works == workIDs { return cache.values }

        var seeds: [(id: String, lat: Double, lng: Double)] = []
        for workID in workIDs.sorted() {
            guard let indices = indicesByWork[workID] else { continue }
            for index in indices {
                let point = points[Int(index)]
                guard point.image != nil else { continue }
                seeds.append((point.id, point.lat, point.lng))
            }
        }
        seeds.sort { $0.lat > $1.lat }

        var values: [String: Int] = [:]
        values.reserveCapacity(seeds.count)
        var seenLat: [Double] = []
        var seenLng: [Double] = []
        seenLat.reserveCapacity(seeds.count)
        seenLng.reserveCapacity(seeds.count)
        for seed in seeds.reversed() {
            var nearest = 99_999.0
            for index in seenLat.indices {
                let dx = seed.lng - seenLng[index]
                let dy = seed.lat - seenLat[index]
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < nearest { nearest = distance }
            }
            seenLat.append(seed.lat)
            seenLng.append(seed.lng)
            values[seed.id] = Int((nearest * 111_000).rounded(.up))
        }

        themePriorityCache = (workIDs, values)
        return values
    }

    // MARK: 作品標

    private func ladderWorks(request: MapEngineRequest) -> [MapWorkSeed] {
        guard let threshold = MapRevealLadder.workThreshold(zoom: request.zoom) else { return [] }
        var candidates = works.filter {
            Double($0.spread) > threshold
                && request.viewport.contains(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude)
        }
        candidates.sort { $0.spread > $1.spread }
        if candidates.count > 200 { candidates = Array(candidates.prefix(200)) }
        return Self.declutter(
            candidates,
            zoom: request.zoom,
            centerLatitude: (request.viewport.minLat + request.viewport.maxLat) / 2,
            limit: request.workLimit
        )
    }

    /// 作品標の重なりは自前で解く —— MapKit の自動 declutter に任せるとラベル付きの標注は
    /// **底図の地名ラベルに負けて丸ごと消え**、`.required` だと逆に一切間引かれず団子になる。
    /// なので画面座標の貪欲配置で生き残りを決め、それだけを `.required` で出す（spread 降順）。
    private static func declutter(
        _ seeds: [MapWorkSeed],
        zoom: Double,
        centerLatitude: Double,
        limit: Int
    ) -> [MapWorkSeed] {
        let pointsPerLng = 256 * pow(2, zoom) / 360
        let pointsPerLat = pointsPerLng / max(cos(centerLatitude * .pi / 180), 0.01)
        // 30pt のカバー ＋ 最大 92pt のラベル、余白込み。
        let box = CGSize(width: 100, height: 54)

        var placed: [CGRect] = []
        var result: [MapWorkSeed] = []
        for seed in seeds {
            let frame = CGRect(
                x: seed.coordinate.longitude * pointsPerLng - box.width / 2,
                y: -seed.coordinate.latitude * pointsPerLat - box.height / 2,
                width: box.width,
                height: box.height
            )
            guard !placed.contains(where: { $0.intersects(frame) }) else { continue }
            placed.append(frame)
            result.append(seed)
            if result.count >= limit { break }
        }
        return result
    }
}

// MARK: - Store からの組み立て

extension MapDataset {
    /// `AnitabiStore` から地図用の種を作る。作品の中心座標は g.json の center を優先し、
    /// 未設定（多くの作品が `[0,0]`）なら自分の点群の重心を使う。
    @MainActor
    init(store: AnitabiStore, version: Int) {
        let works: [MapWorkSeed] = store.bangumis.compactMap { bangumi in
            guard !bangumi.points.isEmpty else { return nil }
            let coordinate = bangumi.center ?? CLLocationCoordinate2D(
                latitude: bangumi.points.reduce(0) { $0 + $1.lat } / Double(bangumi.points.count),
                longitude: bangumi.points.reduce(0) { $0 + $1.lng } / Double(bangumi.points.count)
            )
            return MapWorkSeed(
                id: bangumi.id,
                coordinate: coordinate,
                name: bangumi.displayName,
                colorHex: bangumi.colorHex,
                hasIcon: bangumi.hasIcon,
                spread: bangumi.points.reduce(0) { max($0, $1.priority) }
            )
        }
        self.init(points: store.points, works: works, version: version)
    }
}
