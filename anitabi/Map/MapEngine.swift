//
//  MapEngine.swift
//  anitabi
//
//  「いまこのカメラで、どの標注を出すか」だけを決める層。UIKit にも MapKit のビューにも
//  依存しない純計算なので、5 万点の走査ごとメインスレッドから追い出せる（actor 隔離）。
//
//  設計上の要点：
//  - **数字クラスタ泡は作らない**。密度の制御は Web 版と同じ「揭示阶梯」（最近傍距離 priority の
//    閾値をズームごとに切り替える）だけで行う。
//  - 候補の絞り込みは 2 経路。広域では「priority 降順の先頭だけ見る」、近接では「0.02° グリッド」。
//    どちらが安いかはズームで逆転するので毎フレーム選び直す（`candidateIndices`）。
//  - 出力は「このフレームで在るべき集合」。実際の add/remove の差分は、地図に何が載っているかを
//    知っている `MapCanvas.Coordinator`（メインスレッド）が取る。
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
    /// 揭示阶梯に掛ける値（m）。作品が持つ地標の `priority`（＝最近傍までの距離）の最大値、
    /// つまり「その作品がどれだけ広く散らばっているか」。
    ///
    /// g.json idx15 の `priority` は 999 既定の別物（順位）で阶梯の桁（450〜760000）と合わない。
    /// 実データ 1507 作品で本値を阶梯に当てると z1:66 → z12:1180 件と綺麗に単調増加するため、
    /// こちらを採用する。
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

/// Web 版 Mapbox スタイルに書かれている「ズーム → 寸法」の逐字移植。
///
/// Mapbox GL の長さ単位は CSS px ＝ iOS の pt と 1:1 なので、値は換算せずそのまま使う
/// （Retina かどうかは無関係。`pixelRatio: 2` で addImage された画像は、画素の半分の pt で出る）。
enum MapMarkerMetrics {

    /// Mapbox 旧式 `{base, stops}` の補間（指数）。
    /// `v = v1 + (v2 - v1) × (base^(z-z1) - 1) / (base^(z2-z1) - 1)`。
    /// 両端の外側では端の値で頭打ち（Mapbox と同じ）。
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

    /// Web `bangumi-point` 層の `circle-radius`（`docs/js/readable/4b970b29.js:1423-1430`
    /// ＝ `{base: 1.75, stops: [[12,4],[18,8],[22,16]]}`）。返すのは**半径**。
    static func dotRadius(zoom: Double) -> Double {
        interpolate(zoom, base: 1.75, stops: [(12, 4), (18, 8), (22, 16)])
    }

    /// Web `bangumi-point` 層の `circle-stroke-width`（`4b970b29.js:1431-1438`
    /// ＝ `{base: 1.75, stops: [[12,1.5],[18,3],[22,6]]}`）。
    /// Mapbox の circle 描边は**半径の外側**に足されるので、見た目の直径は `2×(radius + stroke)`。
    static func dotStrokeWidth(zoom: Double) -> Double {
        interpolate(zoom, base: 1.75, stops: [(12, 1.5), (18, 3), (22, 6)])
    }

    /// ブラウズ時（z>18）の大カードの寸法。
    ///
    /// **寸法**は Web `points-image`（`4b970b29.js:2364-2394`：160×(120+14) px、pixelRatio 2
    /// → 80×60pt+尾 7pt、`icon-anchor:"bottom"`＋`icon-offset:[0,-1]`）のまま。
    /// **意匠**は Web から意図的に離れる：Web は大カード＝無枠・小泡＝作品色枠の 2 種類だが、
    /// 「同画面で 2 つの意匠が混在するのはおかしい」というユーザー指摘（2026-08-09）により、
    /// 小泡（`PhotoBubble`）と同じ「作品色の枠＋滴」意匠に統一し、寸法だけ 2 段にする。
    /// 枠色＝作品テーマ色はブラウズ時に複数作品が混在しても帰属が一目で分かる利点がある。
    enum PhotoCard {
        static let bodySize = CGSize(width: 80, height: 60)
        static let cornerRadius: CGFloat = 4
        static let borderWidth: CGFloat = 1
        /// 滴・内三角は PhotoBubble の比率をカード幅へ拡大したもの。
        static let dripSize = CGSize(width: 14, height: 7)
        static let innerTailSize = CGSize(width: 11, height: 7.5)
        static let innerTailOverlap: CGFloat = 1.7
        /// 尾の先端が座標。さらに Web の `icon-offset: [0,-1]` ぶん 1pt 上げる。
        static let anchorLift: CGFloat = 1
        static var totalSize: CGSize {
            CGSize(width: bodySize.width, height: bodySize.height + dripSize.height)
        }
    }

    /// Web `bangumi-points-theme` 層（作品モードの小泡）の絵の寸法。
    ///
    /// 出処：`37476042.js:128-150` の canvas —— セルは `theme.w × theme.h`、
    /// 高さは `h + 11 + 2`、`pixelRatio: 2`。既定値は 72×54 だが、**実データはほぼ全部 100×76**
    /// （実測：`window.mapApp.bangumis` 1499 件中 theme 持ち 1019 件、うち 891 件が `100_76`、
    /// 残り 128 件が w/h 未設定＝既定 72×54）。生成済みスプライトを直接読んで
    /// `{w:100, h:89, pixelRatio:2}` を確認済みなので、100×76 の側を採る。
    /// 枠線 2px・角丸 5.5px もスプライトに焼き込まれている（実測）。
    enum PhotoBubble {
        static let bodySize = CGSize(width: 50, height: 38)
        static let cornerRadius: CGFloat = 3
        /// テーマ色の枠（スプライトに焼かれた 2px ÷ 2）。
        static let borderWidth: CGFloat = 1
        /// テーマ色の滴（`ht` パス 22×11 ÷ 2）。
        static let dripSize = CGSize(width: 11, height: 5.5)
        /// 滴の上に載る、画像で塗られた三角（`pt` パス 18×12 ÷ 2）。上端は本体に 1.35pt 食い込む。
        static let innerTailSize = CGSize(width: 9, height: 6)
        static let innerTailOverlap: CGFloat = 1.35
        /// canvas 全体（76 + 11 + 2）÷ 2。滴の先端より 1pt 下に余白がある。
        static let totalSize = CGSize(width: 50, height: 44.5)
    }

    /// Web `bangumis` 層（作品標）の寸法（`4b970b29.js:1442-1469`）。
    /// アイコンは `bangumi-icons` スプライトの 60×60 セルを `pixelRatio: 2` で載せるので 30pt
    /// （`37476042.js:353-362` の `O = R = 60`）。文字は `text-size: 11` ＋ 白ハロー幅 1、
    /// 位置は `text-anchor: "top"` ＋ `text-offset: [0, 0.8em]`。
    enum WorkMarker {
        static let iconSize: CGFloat = 30
        static let textSize: CGFloat = 11
    }
}

// MARK: - 揭示阶梯

/// Web 版の揭示表をそのまま持つ。値は「最近傍までの距離（m）がこれを**超える**点／作品だけ出す」。
enum MapRevealLadder {

    /// 地標の閾値。Web `4b47e1ef.js`（`bangumi-point` の filter）の逐字移植。z17 以上は全部出す。
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
        // Web は z17 以上で `true`＝全部。閾値は「超える」判定なので、priority 0（座標が完全に
        // 重なっている点）まで拾えるよう -1 を返す。
        default: -1
        }
    }

    /// 作品標の閾値。Web `bangumis` の filter（`4b970b29.js:1977-2007`）＋ `maxzoom: 13`。
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
        // Web は `maxzoom: 13`（`4b970b29.js:1445`）＝ z13 ちょうどから層ごと消える。
        case ..<13: 450
        default: nil
        }
    }

    // MARK: 劇照の揭示

    /// ブラウズ時の大カード（Web `points-image`）が出るズーム。
    /// `4b970b29.js:2325-2331`：`zoom <= 18` ではデータを毎回空にする＝**18 を超えたときだけ**出る。
    static let photoCardZoom: Double = 18

    /// 大カードの priority 閾値。`4b970b29.js:2333` の `Math.pow(2, 19 - o) * 3` そのまま
    /// （点の priority ＝ 最近傍までの距離 m がこれ**以上**なら出す）。
    /// z18.5→4.24m / z19→3m / z20→1.5m / z21→0.75m。
    static func photoCardPriorityThreshold(zoom: Double) -> Double {
        3 * pow(2, 19 - zoom)
    }

    /// 作品モードの小泡（Web `bangumi-points-theme`）の揭示阶梯。
    /// `37476042.js:254-292` の `["step", ["zoom"], ...]` を逐字移植。値は m。
    /// 層の `maxzoom: 18` なので z18 以上は本来描かれない（そこは大カードが引き継ぐ）。
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

    /// MKFeatureDisplayPriority。同じ場所で競合したとき、孤立している＝周りに何も無い標注ほど残る。
    ///
    /// Web 版の式は `250 + 750×min(1, log10(p+1)/5)` で上限がちょうど 1000 になるが、
    /// MapKit の 1000 は `.required`＝**衝突しても絶対に隠さない** という特別な意味を持つ。
    /// そのまま使うと広域で作品標が重なり合ったまま出るので、上限だけ 999 に落とす。
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
    /// Web の 2 層（`points-image` / `bangumi-points-theme`）には枚数上限が無く、
    /// 揭示阶梯と priority 閾値だけで疎になる。こちらはテクスチャ枚数の保険として置くだけなので、
    /// 阶梯が効いている限り当たらない値にする（実測：池袋 z18.6 の大カードで 37 枚、
    /// ユーフォ z13 の小泡で 84 枚）。
    var photoLimit = 120
    var workLimit = 32
}

struct MapPointPlan: Sendable {
    let point: ScenePoint
    /// 劇照サムネイル形態で出すか。
    ///
    /// 判定は Web の 2 層をそのまま合成したもの（`MapEngine.photoForms`）：
    /// - z > 18 ＝ `points-image`（大カード）。画像あり ＋ `priority ≥ 3·2^(19−z)`。
    /// - z ≤ 18 かつ作品モード ＝ `bangumi-points-theme`（小泡）。作品内で測り直した
    ///   最近傍距離が揭示阶梯を超えるもの。
    /// どちらの絵で描くかは `PointMarkerView` がズームから決める（Web の層分けと同じ境目 z18）。
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

    /// priority 降順の並び（値は `points` の添字）。広域では先頭の数十件しか閾値を超えないので、
    /// ここを前から舐めるのがいちばん速い。
    private var orderByPriority: [Int32] = []
    /// `orderByPriority` と同じ並びの priority 値（二分探索で「閾値を超える件数」を出す）。
    /// priority は最近傍までの距離（m）で、離島の 1 点などは 1e10 に達する。**Int32 には収まらない**。
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

    /// 「どの点を劇照で出すか」を Web の 2 層そのままに決める。
    ///
    /// Web には劇照の層が 2 枚あり、**z18 でバトンを渡す**：
    ///
    /// | 層 | ズーム | 出す条件 | 絵 |
    /// |---|---|---|---|
    /// | `points-image`（`4b970b29.js:2322-2398`） | `z > 18` のみ（18 以下はデータを毎回空にする） | 画像あり ＋ `priority ≥ 3·2^(19−z)` | 80×60pt ＋ 尾 7pt |
    /// | `bangumi-points-theme`（`37476042.js:236-303`） | `maxzoom: 18` ＝ z18 未満。かつ**作品を選んでいるときだけ**（ブラウズ中は `J()` で空にされる） | 揭示阶梯（作品内で測り直した最近傍距離 m） | 50×38pt ＋ 尾 6.5pt |
    ///
    /// つまり **ブラウズ中に z≤18 で劇照は 1 枚も出ない**。以前の実装の z≥16.5 は根拠が無かった。
    ///
    /// z18 ちょうどは Web だとどちらの層も出ない（`<= 18` と `maxzoom: 18` の隙間）が、
    /// 深リンクで z=18.0 に着地したときに劇照が消える方が事故なので、こちらは小泡側に寄せる。
    private func photoForms(
        for selected: [ScenePoint],
        request: MapEngineRequest,
        filterIDs: Set<Int>?
    ) -> [MapPointPlan] {
        guard request.isPhotoLayerVisible else {
            return selected.map { MapPointPlan(point: $0, usesPhoto: false) }
        }

        var eligible: [(offset: Int, rank: Int)] = []
        if request.zoom > MapRevealLadder.photoCardZoom {
            // `points-image` 相当。作品モードでもここは同じ（Web も z>18 では大カードに合流する）。
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

    /// 小泡の間引きに使う priority を、Web の `A()`（`37476042.js:110-127`）どおりに測り直す。
    ///
    /// 大事なのは「点が元から持っている priority（＝全 5 万点の中での最近傍距離）ではない」こと。
    /// 作品モードでは**その作品の画像点だけ**を対象に取り直すので、同じ点でも値がぐっと大きくなり、
    /// 広域でも数十枚は残る。Web の手順は：
    /// 1. 画像点を緯度の降順に並べる
    /// 2. 末尾（南）から順に、それまでに見た点までの最短距離を測る（度のユークリッド距離、
    ///    経度の cos 補正はしない）
    /// 3. `ceil(距離 × 111000)` を priority にする。最初の 1 点だけは 99999（度）＝ 事実上無限大
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

    /// 作品標の重なりは自前で解く。
    ///
    /// MapKit の自動 declutter（collisionMode + displayPriority）に任せると、作品名ラベルを
    /// 抱えた 100pt 幅の標注は**底図の地名ラベルとの競合に負けて丸ごと消える**（実測：日本全域で
    /// 32 個中 1 個しか残らない）。かといって `.required` で出すと今度は一切間引かれず、
    /// ラベルが重なって団子になる。よってここで画面座標の貪欲配置を行い、生き残りだけを
    /// `.required` で出す。並び順は spread 降順＝広く散らばっている作品を優先。
    private static func declutter(
        _ seeds: [MapWorkSeed],
        zoom: Double,
        centerLatitude: Double,
        limit: Int
    ) -> [MapWorkSeed] {
        let pointsPerLng = 256 * pow(2, zoom) / 360
        let pointsPerLat = pointsPerLng / max(cos(centerLatitude * .pi / 180), 0.01)
        // 30pt のカバー（Web `bangumis` のスプライト 60×60@2x）＋ 最大 92pt のラベル。余白込み。
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
