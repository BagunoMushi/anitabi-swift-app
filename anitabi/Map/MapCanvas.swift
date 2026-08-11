//
//  MapCanvas.swift
//  anitabi
//
//  地図の唯一の入口（SwiftUI 側の契約）。地図は**ナビゲーション状態を一切持たない** ——
//  何を選んだか・どのカードを開くかは全て `AppRouter` の持ち物で、地図はそれを「描く」のと
//  「操作を上へ投げる」だけ。個々の引数の意味はそれぞれの宣言のコメントに書いてある。
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - 公開型

/// `String` raw value を持たせているのは `@AppStorage` に直接載せるため。
enum MapBaseStyle: String, Equatable {
    case standard
    /// 衛星（ラベル付き）。
    case hybrid
}

struct MapCameraState: Equatable {
    var region: MKCoordinateRegion
    var zoom: Double
    var heading: CLLocationDirection

    static func == (lhs: MapCameraState, rhs: MapCameraState) -> Bool {
        abs(lhs.zoom - rhs.zoom) < 0.001
            && abs(lhs.heading - rhs.heading) < 0.001
            && abs(lhs.region.center.latitude - rhs.region.center.latitude) < 1e-9
            && abs(lhs.region.center.longitude - rhs.region.center.longitude) < 1e-9
            && abs(lhs.region.span.latitudeDelta - rhs.region.span.latitudeDelta) < 1e-9
    }
}

/// 一回きりのカメラ指令。`id` を見て実行するので、同じ内容でも作り直せば必ず再実行される。
struct MapCameraCommand: Identifiable, Equatable {
    enum Kind {
        case region(MKCoordinateRegion)
        case center(CLLocationCoordinate2D, zoom: Double)
        /// 一覧から選んだ 1 点へ。`priority`（最近傍距離 m）から寄り具合を決め、
        /// `verticalOffset` pt ぶん画面上寄りに置く（下半分はカードで隠れるため）。
        case flyToPoint(CLLocationCoordinate2D, priority: Int?, verticalOffset: CGFloat)
        /// 与えられた座標が全部収まる範囲へ（作品モードの「枠を丸ごと見せる」）。`bottomInset` は
        /// カードに譲る帯で、`nil` なら可視カードの上縁を実測して使う。`trimsOutliers` は離群点を
        /// 切り捨てるかで、圧暗レイヤーの頂点を渡すときは `false`。
        case fitWork([CLLocationCoordinate2D], bottomInset: CGFloat?, trimsOutliers: Bool)
        case userLocation(span: CLLocationDegrees)
    }

    let id = UUID()
    var kind: Kind
    var animated = true

    static func == (lhs: MapCameraCommand, rhs: MapCameraCommand) -> Bool { lhs.id == rhs.id }

    static func region(_ region: MKCoordinateRegion, animated: Bool = true) -> MapCameraCommand {
        MapCameraCommand(kind: .region(region), animated: animated)
    }

    static func flyTo(
        _ point: ScenePoint,
        verticalOffset: CGFloat = 0,
        animated: Bool = true
    ) -> MapCameraCommand {
        MapCameraCommand(
            kind: .flyToPoint(point.coordinate, priority: point.priority, verticalOffset: verticalOffset),
            animated: animated
        )
    }

    static func fitWork(
        _ coordinates: [CLLocationCoordinate2D],
        bottomInset: CGFloat? = nil,
        trimsOutliers: Bool = true,
        animated: Bool = true
    ) -> MapCameraCommand {
        MapCameraCommand(
            kind: .fitWork(coordinates, bottomInset: bottomInset, trimsOutliers: trimsOutliers),
            animated: animated
        )
    }
}

/// 署名（Apple ロゴ＋「法的情報」）をどこまで持ち上げるかの指令。Apple マップと同じで、
/// カードが一段式→两段式へ上がる**間はずっと**署名が付いてくるが、三段目へは追わない。
struct MapAttributionLift: Equatable {
    /// 可視カードの上縁（window 座標）。`SheetShapeReader` の実測。nil なら既定位置のまま。
    var cardTopY: CGFloat?
    /// 三段式より下に居るときに最後に見たカードの上縁＝**蓋の実測値**。nil の間は蓋をしない。
    var restingCardTopY: CGFloat?
    /// 蓋の見積もり（地図の下端からの距離）。実測が届くまでの代役。
    var ceiling: CGFloat = MapCanvas.attributionBottomMargin

    /// 「地図の下端からカードの上縁まで」を蓋で止めた最終値。署名と浮控列が共有する ——
    /// 座標変換をここ 1 か所に閉じ込めてあるので、2 つが別の物差しに分かれることがない。
    func resolvedLift(in mapView: MKMapView) -> CGFloat? {
        guard let raised = rawLift(in: mapView) else { return nil }
        // 実測の蓋があるときだけ、そちらを下限として押し上げる。
        guard let restingCardTopY, let capped = lift(of: restingCardTopY, in: mapView) else {
            return raised
        }
        return min(raised, max(ceiling, capped))
    }

    /// 蓋を掛けない生の値＝「地図の下端から**いま見えているカードの上縁**まで」。
    /// カメラのフィットはこちらを使う —— 蓋付きは「三段式まで署名を追わせない」ための頭打ちで、
    /// 畳んだカードに対しては実際より広い帯を返すので、絵が上半分に寄ったままになる。
    func rawLift(in mapView: MKMapView) -> CGFloat? {
        guard let cardTopY else { return nil }
        return lift(of: cardTopY, in: mapView)
    }

    private func lift(of windowY: CGFloat, in mapView: MKMapView) -> CGFloat? {
        guard mapView.window != nil else { return nil }
        return mapView.bounds.maxY - mapView.convert(CGPoint(x: 0, y: windowY), from: nil).y
    }
}

// MARK: - MapCanvas

struct MapCanvas: UIViewRepresentable {

    var dataset: MapDataset
    var command: MapCameraCommand?
    var focusedWorkID: Int?
    var selectedWorkIDs: Set<Int> = []
    var selectedPointID: String?
    var isPhotoLayerVisible = true
    var baseStyle: MapBaseStyle = .standard
    /// 署名を常駐カードの上へ逃がす指令（既定＝`attributionBottomMargin` に据え置き）。
    var attributionLift = MapAttributionLift()
    /// 長押しで落とした針。`nil` なら地図上に何も置かない（系统の赤いマーカーで表示する）。
    var droppedPinCoordinate: CLLocationCoordinate2D?

    var onSelectPoint: (ScenePoint) -> Void = { _ in }
    var onSelectWork: (Int) -> Void = { _ in }
    var onTapDimRegion: () -> Void = {}
    var onTapBlank: () -> Void = {}
    var onLongPress: (CLLocationCoordinate2D) -> Void = { _ in }
    var onCameraIdle: (MapCameraState) -> Void = { _ in }
    /// 在図標注数（HUD・デバッグ用の任意口）。
    var onAnnotationsChange: (Int, Int) -> Void = { _, _ in }
    /// ユーザーが地図を動かし始めた（パン／ピンチの began）。sheet を最小档へ落とす合図。
    /// SwiftUI の `simultaneousGesture` は MKMapView 内部の認識器に食われることがあるので、
    /// 観測専用の認識器を自前で足して確実に拾う。
    var onUserInteractionBegan: (() -> Void)?
    /// 生の `MKMapView` を 1 回だけ手渡す —— `MKCompassButton`/`MKScaleView` が
    /// `init(mapView:)` で同じインスタンスを要求するため。
    var onMapViewReady: ((MKMapView) -> Void)?

    static let japanOverview = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.5, longitude: 138.5),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)
    )

    /// 署名を持ち上げる**下限**（＝一段式のときの値）。MKMapView は署名を `layoutMargins` の
    /// 内側にしか置かないので、常駐 sheet に食われないためにはここで逃がすしかない。カードが上がる
    /// 間は `attributionLift` が引き上げる。**この値はカメラには効かせない**。
    static let attributionBottomMargin: CGFloat = 100

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        // 指南針・比例尺は内蔵品を使わず、後段で MKCompassButton / MKScaleView として別置きする。
        mapView.showsCompass = false
        mapView.showsScale = false
        // 3D は巡礼の役に立たず、標注のアンカーがずれるだけ。
        mapView.isPitchEnabled = false
        // POI（駅・地名）は残す —— 巡礼では「最寄り駅」が最重要の文脈。ただし
        // タップで Apple の地物カードが出ると自前の導線と衝突するので選択だけ切る。
        mapView.selectableMapFeatures = []
        mapView.register(
            PointMarkerView.self,
            forAnnotationViewWithReuseIdentifier: PointMarkerView.reuseIdentifier
        )
        mapView.register(
            WorkMarkerView.self,
            forAnnotationViewWithReuseIdentifier: WorkMarkerView.reuseIdentifier
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.droppedPinReuseIdentifier
        )
        // 既定では safe area ぶんが layoutMargins に入り、要求ズームより浅い画が出る。余白は
        // 呼び出し側が edgePadding で明示する方針なので殺し、下辺だけ署名の置き場として残す。
        mapView.insetsLayoutMarginsFromSafeArea = false
        mapView.layoutMargins = UIEdgeInsets(
            top: 0, left: 0, bottom: Self.attributionBottomMargin, right: 0
        )
        mapView.setRegion(Self.japanOverview, animated: false)
        context.coordinator.attach(to: mapView, style: baseStyle)
        // 呼び出し側は 1 拍遅らせる約束 —— `makeUIView` の最中に `@State` を書き換えると
        // 「ビュー更新中に状態を変更した」実行時警告になる。
        onMapViewReady?(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.sync(with: self, mapView: mapView)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.detach()
        mapView.delegate = nil
    }
}

/// `CLLocationCoordinate2D` は `Equatable` を持たない。落針の座標が変わったかどうかだけを
/// 見たいので、誤差吸収込みの簡易比較をここに置く。
private func coordinatesEqual(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case let (l?, r?):
        return abs(l.latitude - r.latitude) < 1e-9 && abs(l.longitude - r.longitude) < 1e-9
    default: return false
    }
}

// MARK: - Coordinator

extension MapCanvas {

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        private var parent: MapCanvas
        private let engine = MapEngine()
        private weak var mapView: MKMapView?

        private var updateTask: Task<Void, Never>?
        private var datasetVersion = -1
        private var colorByWork: [Int: UIColor] = [:]

        private var livePoints: [String: ScenePointAnnotation] = [:]
        private var removingPoints: [String: ScenePointAnnotation] = [:]
        private var liveWorks: [Int: WorkAnnotation] = [:]
        private var removingWorks: [Int: WorkAnnotation] = [:]

        private var appliedZoom: Double = 0
        private var lastCommandID: UUID?
        private var selectedPointID: String?
        private var focusedWorkID: Int?
        private var selectedWorkIDs: Set<Int> = []
        private var isPhotoLayerVisible = true
        private var baseStyle: MapBaseStyle = .standard

        private var regionOverlay: WorkRegionOverlay?
        private var overlayWorkID: Int?

        static let droppedPinReuseIdentifier = "droppedPin"
        private var droppedPinAnnotation: MKPointAnnotation?
        private var droppedPinCoordinate: CLLocationCoordinate2D?

        init(_ parent: MapCanvas) {
            self.parent = parent
            super.init()
        }

        // MARK: 取り付け

        func attach(to mapView: MKMapView, style: MapBaseStyle) {
            self.mapView = mapView
            applyStyle(style, on: mapView)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.delegate = self
            tap.cancelsTouchesInView = false
            // ダブルタップ拡大と競合させない。
            for recognizer in mapView.gestureRecognizers ?? [] {
                if let double = recognizer as? UITapGestureRecognizer, double.numberOfTapsRequired == 2 {
                    tap.require(toFail: double)
                }
            }
            mapView.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            longPress.delegate = self
            longPress.minimumPressDuration = 0.45
            mapView.addGestureRecognizer(longPress)

            // 観測専用。何も消費せず、MapKit 側の pan/pinch と同時に走る
            // （`shouldRecognizeSimultaneouslyWith` が true なので相手の delegate 次第にならない）。
            for observer in [
                UIPanGestureRecognizer(target: self, action: #selector(handleUserInteraction)),
                UIPinchGestureRecognizer(target: self, action: #selector(handleUserInteraction)),
            ] as [UIGestureRecognizer] {
                observer.delegate = self
                observer.cancelsTouchesInView = false
                mapView.addGestureRecognizer(observer)
            }

            BangumiIconSprite.shared.onReady = { [weak self] in self?.refreshWorkIcons() }
            BangumiIconSprite.shared.prepare()
        }

        func detach() {
            updateTask?.cancel()
            updateTask = nil
            BangumiIconSprite.shared.onReady = nil
            mapView = nil
        }

        // MARK: SwiftUI からの同期

        func sync(with parent: MapCanvas, mapView: MKMapView) {
            self.parent = parent

            applyAttributionLift(parent.attributionLift, on: mapView)

            if baseStyle != parent.baseStyle {
                baseStyle = parent.baseStyle
                applyStyle(parent.baseStyle, on: mapView)
            }

            if datasetVersion != parent.dataset.version {
                datasetVersion = parent.dataset.version
                colorByWork = Dictionary(
                    parent.dataset.works.map {
                        ($0.id, $0.colorHex.flatMap(UIColor.init(cssHex:)) ?? .anitabiNeutralTheme)
                    },
                    uniquingKeysWith: { a, _ in a }
                )
                let dataset = parent.dataset
                Task { [engine] in
                    await engine.load(dataset)
                    await MainActor.run { [weak self] in self?.scheduleUpdate(immediate: true) }
                }
            }

            var needsUpdate = false
            if focusedWorkID != parent.focusedWorkID {
                focusedWorkID = parent.focusedWorkID
                needsUpdate = true
            }
            if selectedWorkIDs != parent.selectedWorkIDs {
                selectedWorkIDs = parent.selectedWorkIDs
                needsUpdate = true
            }
            if isPhotoLayerVisible != parent.isPhotoLayerVisible {
                isPhotoLayerVisible = parent.isPhotoLayerVisible
                needsUpdate = true
            }
            if selectedPointID != parent.selectedPointID {
                selectedPointID = parent.selectedPointID
                needsUpdate = true
            }
            if needsUpdate { scheduleUpdate(immediate: true) }

            if !coordinatesEqual(droppedPinCoordinate, parent.droppedPinCoordinate) {
                droppedPinCoordinate = parent.droppedPinCoordinate
                applyDroppedPin(droppedPinCoordinate, on: mapView)
            }

            if let command = parent.command, command.id != lastCommandID {
                lastCommandID = command.id
                execute(command, on: mapView)
            }
        }

        /// 署名を常駐カードの上へ逃がす（`layoutMargins.bottom` が唯一の摘み）。余白を動かしても
        /// **描画は動かない** —— 動くのは `region` の意味と `setVisibleMapRect` の収め先だけで、
        /// そちらは `compensatingMargin` が同じ値を引いて打ち消す。
        private func applyAttributionLift(_ lift: MapAttributionLift, on mapView: MKMapView) {
            let base = MapCanvas.attributionBottomMargin
            let margin = max(lift.resolvedLift(in: mapView) ?? base, base)
            // 拖动中は毎フレーム来るので、1pt 未満の揺れでは版面を組み直させない。
            guard abs(mapView.layoutMargins.bottom - margin) >= 1 else { return }
            mapView.layoutMargins.bottom = margin
        }

        private func applyStyle(_ style: MapBaseStyle, on mapView: MKMapView) {
            switch style {
            case .standard:
                // elevation は .flat 固定。起伏表現は標注の可読性を落とすだけで巡礼の役に立たない。
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            case .hybrid:
                mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            }
        }

        // MARK: 更新ループ

        private func scheduleUpdate(immediate: Bool = false) {
            updateTask?.cancel()
            updateTask = Task { @MainActor [weak self] in
                if !immediate {
                    // カメラが 120ms 静止してから 1 回だけ計算する。
                    try? await Task.sleep(for: .milliseconds(120))
                }
                guard !Task.isCancelled, let self else { return }
                await self.runUpdate()
            }
        }

        private func runUpdate() async {
            guard let mapView, mapView.bounds.width > 0 else { return }
            let region = fullBoundsRegion(of: mapView)
            let zoom = MapCameraPlanner.zoom(for: region, width: mapView.bounds.width)

            parent.onCameraIdle(
                MapCameraState(region: region, zoom: zoom, heading: mapView.camera.heading)
            )

            let request = MapEngineRequest(
                // 視口の 1.4 倍まで先に用意しておくと、少し流したくらいでは標注が湧かない。
                viewport: MapViewport(region: region, scale: 1.4),
                zoom: zoom,
                focusedWorkID: focusedWorkID,
                selectedWorkIDs: selectedWorkIDs,
                isPhotoLayerVisible: isPhotoLayerVisible,
                selectedPointID: selectedPointID
            )
            let frame = await engine.frame(for: request)
            guard !Task.isCancelled, let mapView = self.mapView else { return }
            apply(frame, on: mapView)
        }

        // MARK: 差分適用

        private func apply(_ frame: MapEngineFrame, on mapView: MKMapView) {
            let zoomChanged = abs(frame.zoom - appliedZoom) > 0.02
            appliedZoom = frame.zoom

            applyPoints(frame, on: mapView, zoomChanged: zoomChanged)
            applyWorks(frame, on: mapView)
            applyRegionOverlay(frame.focusedWorkCoordinates, on: mapView)
            applySelection(on: mapView)

            parent.onAnnotationsChange(livePoints.count, liveWorks.count)
        }

        private func applyPoints(_ frame: MapEngineFrame, on mapView: MKMapView, zoomChanged: Bool) {
            var desired: [String: MapPointPlan] = [:]
            desired.reserveCapacity(frame.points.count)
            for plan in frame.points { desired[plan.point.id] = plan }

            for (id, annotation) in livePoints where desired[id] == nil {
                // 選択中の標注は差分から絶対に外さない（カードだけ残って点が消える事故を防ぐ）。
                guard id != selectedPointID else { continue }
                livePoints[id] = nil
                removingPoints[id] = annotation
                fadeOut(annotation, on: mapView) { [weak self] in
                    guard let self, self.removingPoints[id] === annotation else { return false }
                    self.removingPoints[id] = nil
                    return true
                }
            }

            var additions: [ScenePointAnnotation] = []
            for (id, plan) in desired {
                let form: PointMarkerForm = plan.usesPhoto ? .photo : .dot

                if let existing = livePoints[id] {
                    if existing.plannedForm != form {
                        existing.plannedForm = form
                        (mapView.view(for: existing) as? PointMarkerView)?
                            .configure(with: existing, zoom: frame.zoom, animated: true)
                    } else if zoomChanged {
                        (mapView.view(for: existing) as? PointMarkerView)?
                            .updateZoom(frame.zoom, animated: true)
                    }
                    continue
                }

                if let revived = removingPoints.removeValue(forKey: id) {
                    cancelFade(revived, on: mapView)
                    revived.plannedForm = form
                    livePoints[id] = revived
                    (mapView.view(for: revived) as? PointMarkerView)?
                        .configure(with: revived, zoom: frame.zoom, animated: false)
                    continue
                }

                let annotation = ScenePointAnnotation(
                    point: plan.point,
                    themeColor: colorByWork[plan.point.bangumiID] ?? .anitabiNeutralTheme
                )
                annotation.plannedForm = form
                livePoints[id] = annotation
                additions.append(annotation)
            }
            if !additions.isEmpty { mapView.addAnnotations(additions) }
        }

        private func applyWorks(_ frame: MapEngineFrame, on mapView: MKMapView) {
            var desired: [Int: MapWorkSeed] = [:]
            for seed in frame.works { desired[seed.id] = seed }

            for (id, annotation) in liveWorks where desired[id] == nil {
                liveWorks[id] = nil
                removingWorks[id] = annotation
                fadeOut(annotation, on: mapView) { [weak self] in
                    guard let self, self.removingWorks[id] === annotation else { return false }
                    self.removingWorks[id] = nil
                    return true
                }
            }

            var additions: [WorkAnnotation] = []
            for (id, seed) in desired where liveWorks[id] == nil {
                if let revived = removingWorks.removeValue(forKey: id) {
                    cancelFade(revived, on: mapView)
                    liveWorks[id] = revived
                    continue
                }
                let annotation = WorkAnnotation(seed: seed)
                liveWorks[id] = annotation
                additions.append(annotation)
            }
            if !additions.isEmpty { mapView.addAnnotations(additions) }
        }

        /// 消える標注は縮んでから消える。`keepGoing` が false を返したら（＝途中で復活したら）
        /// 削除せず元に戻す。
        private func fadeOut(
            _ annotation: MKAnnotation,
            on mapView: MKMapView,
            keepGoing: @escaping () -> Bool
        ) {
            guard let view = mapView.view(for: annotation) else {
                if keepGoing() { mapView.removeAnnotation(annotation) }
                return
            }
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            } completion: { _ in
                guard keepGoing() else {
                    view.alpha = 1
                    view.transform = .identity
                    return
                }
                view.alpha = 1
                view.transform = .identity
                mapView.removeAnnotation(annotation)
            }
        }

        private func cancelFade(_ annotation: MKAnnotation, on mapView: MKMapView) {
            guard let view = mapView.view(for: annotation) else { return }
            view.layer.removeAllAnimations()
            view.alpha = 1
            view.transform = .identity
        }

        // MARK: 選択

        private func applySelection(on mapView: MKMapView) {
            for case let annotation as ScenePointAnnotation in mapView.selectedAnnotations
            where annotation.id != selectedPointID {
                mapView.deselectAnnotation(annotation, animated: true)
            }
            guard
                let selectedPointID,
                let annotation = livePoints[selectedPointID],
                !annotation.isSelected
            else { return }
            mapView.selectAnnotation(annotation, animated: true)
        }

        // MARK: カメラ指令

        private func execute(_ command: MapCameraCommand, on mapView: MKMapView) {
            let size = mapView.bounds.size
            guard size.width > 0 else { return }

            switch command.kind {
            case .region(let region):
                move(to: region, on: mapView, animated: command.animated)

            case .center(let coordinate, let zoom):
                move(
                    to: MapCameraPlanner.mapRect(center: coordinate, zoom: zoom, size: size),
                    on: mapView,
                    animated: command.animated
                )

            case .flyToPoint(let coordinate, let priority, let verticalOffset):
                move(
                    to: MapCameraPlanner.mapRect(
                        center: coordinate,
                        zoom: MapCameraPlanner.flyZoom(priority: priority),
                        size: size,
                        verticalOffset: verticalOffset
                    ),
                    on: mapView,
                    animated: command.animated
                )

            case .fitWork(let coordinates, let bottomInset, let trimsOutliers):
                let fitted = trimsOutliers
                    ? MapCameraPlanner.fitRect(for: coordinates)
                    : MapCameraPlanner.enclosingRect(of: coordinates)
                guard let raw = fitted else { return }
                let rect = MapCameraPlanner.clampedToMaxZoom(raw, viewSize: size)
                // カードに譲る帯は実測（可視カードの上縁）を第一の出所にし、指令に値が入って
                // いればそちらを尊重する。
                let cardInset = bottomInset
                    ?? parent.attributionLift.rawLift(in: mapView)
                    ?? parent.attributionLift.ceiling
                let padding = Self.compensatingMargin(
                    MapCameraPlanner.edgePadding(
                        viewSize: size,
                        topInset: mapView.safeAreaInsets.top,
                        bottomInset: max(cardInset, 0)
                    ),
                    on: mapView
                )
                // 収め先の計算と移動を**分ける**のが肝：`setVisibleMapRect` 系だと大きな寄りが
                // 飛ばずに 1 コマで切り替わるが、`setRegion(animated:)` なら滑る。なので余白は
                // `mapRectThatFits`（純計算）で畳み、動かすのは `setRegion` に渡す。
                move(
                    to: MKCoordinateRegion(mapView.mapRectThatFits(rect, edgePadding: padding)),
                    on: mapView,
                    animated: command.animated
                )

            case .userLocation(let span):
                guard let coordinate = mapView.userLocation.location?.coordinate else { return }
                move(
                    to: MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                    ),
                    on: mapView,
                    animated: command.animated
                )
            }
        }

        private func move(to region: MKCoordinateRegion, on mapView: MKMapView, animated: Bool) {
            guard animated else {
                mapView.setRegion(region, animated: false)
                return
            }
            animateCamera { mapView.setRegion(region, animated: true) }
        }

        /// 署名のために `layoutMargins.bottom` へ入れた量をカメラ指令からだけ差し引く。**定数では
        /// なく今の余白を読む**（余白はカードの高さに合わせて動く）。戻すのは**下辺だけ** ——
        /// 上下に半分ずつ分けると縮尺は直るが枠の中心が上へ寄って描画が丸ごと上がる。
        private static func compensatingMargin(
            _ padding: UIEdgeInsets = .zero,
            on mapView: MKMapView
        ) -> UIEdgeInsets {
            var padding = padding
            padding.bottom -= mapView.layoutMargins.bottom
            return padding
        }

        /// `mapView.region` は論理視口（署名ぶんの余白を除いた帯）を指すので、そのまま外へ流すと
        /// 中心が余白の半分だけ北にずれ、状態復元のたびに同じ量ずつ流れていく。画面中心を引き直し、
        /// 緯度方向の span だけ余白ぶん伸ばして相殺する（左右の余白は 0 なので経度側はそのまま）。
        private func fullBoundsRegion(of mapView: MKMapView) -> MKCoordinateRegion {
            let height = mapView.bounds.height
            let inner = height - mapView.layoutMargins.bottom
            guard inner > 0 else { return mapView.region }
            let span = mapView.region.span
            return MKCoordinateRegion(
                center: mapView.convert(
                    CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY), toCoordinateFrom: mapView
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: min(span.latitudeDelta * Double(height / inner), 180),
                    longitudeDelta: span.longitudeDelta
                )
            )
        }

        private func move(to rect: MKMapRect, on mapView: MKMapView, animated: Bool) {
            move(to: rect, padding: Self.compensatingMargin(on: mapView), on: mapView, animated: animated)
        }

        /// 矩形を余白付きで収める（`.center` と一覧からの `.flyToPoint`）。この経路はちゃんと滑る。
        /// 作品の枠フィット（`.fitWork`）だけは同じ書き方では滑らないので `setRegion` に渡している
        /// —— 理由はあちらのコメントに。
        private func move(
            to rect: MKMapRect,
            padding: UIEdgeInsets,
            on mapView: MKMapView,
            animated: Bool
        ) {
            let fitted = mapView.mapRectThatFits(rect, edgePadding: padding)
            guard animated else {
                mapView.setVisibleMapRect(fitted, animated: false)
                return
            }
            animateCamera { mapView.setVisibleMapRect(fitted, animated: true) }
        }

        /// MKMapView 既定のカメラ移動は 0.3 秒ほどで、Web 版の 1.2 秒より忙しない。
        /// UIView のアニメーション文脈で包むと MapKit がその duration を拾う。
        private func animateCamera(_ body: @escaping () -> Void) {
            UIView.animate(
                withDuration: MapCameraPlanner.flyDuration,
                delay: 0,
                options: [.curveEaseInOut],
                animations: body
            )
        }

        // MARK: 圧暗レイヤー

        private func applyRegionOverlay(_ coordinates: [CLLocationCoordinate2D]?, on mapView: MKMapView) {
            guard let coordinates, !coordinates.isEmpty, let focusedWorkID else {
                if let regionOverlay {
                    mapView.removeOverlay(regionOverlay)
                    self.regionOverlay = nil
                    overlayWorkID = nil
                }
                return
            }
            guard overlayWorkID != focusedWorkID else { return }
            if let regionOverlay { mapView.removeOverlay(regionOverlay) }
            guard let overlay = WorkRegionOverlay.make(for: coordinates) else {
                regionOverlay = nil
                overlayWorkID = nil
                return
            }
            overlay.themeColor = colorByWork[focusedWorkID] ?? .anitabiNeutralTheme
            regionOverlay = overlay
            overlayWorkID = focusedWorkID
            mapView.addOverlay(overlay, level: .aboveRoads)
        }

        // MARK: 落針（長押し）

        /// `nil` → 撤去、値あり → 作り直す。座標を直接書き換えるより、削除→追加のほうが
        /// `animatesWhenAdded` の落下演出を毎回拾える。
        private func applyDroppedPin(_ coordinate: CLLocationCoordinate2D?, on mapView: MKMapView) {
            if let existing = droppedPinAnnotation {
                mapView.removeAnnotation(existing)
                droppedPinAnnotation = nil
            }
            guard let coordinate else { return }
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            droppedPinAnnotation = annotation
            mapView.addAnnotation(annotation)
        }

        private func refreshWorkIcons() {
            guard let mapView else { return }
            for annotation in liveWorks.values {
                (mapView.view(for: annotation) as? WorkMarkerView)?.refreshIcon()
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let point as ScenePointAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PointMarkerView.reuseIdentifier, for: point
                ) as? PointMarkerView
                view?.configure(with: point, zoom: appliedZoom, animated: false)
                return view

            case let work as WorkAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: WorkMarkerView.reuseIdentifier, for: work
                ) as? WorkMarkerView
                view?.configure(with: work)
                return view

            case let pin as MKPointAnnotation where pin === droppedPinAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Coordinator.droppedPinReuseIdentifier, for: pin
                ) as? MKMarkerAnnotationView
                view?.markerTintColor = .systemRed
                view?.canShowCallout = false
                // 系统の落下演出（`animatesWhenAdded`）に任せる——自前でスケール／不透明度は組まない。
                view?.animatesWhenAdded = true
                return view

            default:
                return nil  // ユーザー位置は MapKit の既定表示に任せる。
            }
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views {
                // ユーザー位置と落針には自前の演出を掛けない（落針は系统の落下演出に任せる）。
                guard !(view.annotation is MKUserLocation),
                      !(view.annotation is MKPointAnnotation)
                else { continue }
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                // 一斉に湧くと「点が降ってきた」ように見えるので、80ms 以内でばらけさせる。
                UIView.animate(
                    withDuration: 0.25,
                    delay: Double.random(in: 0...0.08),
                    options: [.curveEaseOut, .beginFromCurrentState]
                ) {
                    view.alpha = 1
                    view.transform = .identity
                }
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let work = view.annotation as? WorkAnnotation {
                // 作品標に選択状態は無い。押した瞬間に外へ投げて自分は素に戻る。
                mapView.deselectAnnotation(work, animated: false)
                parent.onSelectWork(work.bangumiID)
                return
            }
            guard let point = view.annotation as? ScenePointAnnotation else { return }
            let isNew = selectedPointID != point.id
            selectedPointID = point.id
            point.isSelected = true
            (view as? PointMarkerView)?.configure(with: point, zoom: appliedZoom, animated: true)
            if isNew { parent.onSelectPoint(point.point) }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let point = view.annotation as? ScenePointAnnotation, point.isSelected else { return }
            point.isSelected = false
            (view as? PointMarkerView)?.configure(with: point, zoom: appliedZoom, animated: true)
            if selectedPointID == point.id { selectedPointID = nil }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let region = overlay as? WorkRegionOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            // Web 版と同じ：暗幕＝テーマ色 50%、縁取り＝テーマ色の太い帯（地面幅一定）。
            let renderer = WorkRegionRenderer(overlay: region)
            renderer.fillColor = region.themeColor.withAlphaComponent(0.5)
            renderer.strokeColor = region.themeColor
            return renderer
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            scheduleUpdate()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            scheduleUpdate()
        }

        // MARK: ジェスチャ

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView, recognizer.state == .ended else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            if let regionOverlay, focusedWorkID != nil, !regionOverlay.contains(coordinate) {
                parent.onTapDimRegion()
                return
            }
            parent.onTapBlank()
        }

        @objc private func handleUserInteraction(_ recognizer: UIGestureRecognizer) {
            guard recognizer.state == .began else { return }
            parent.onUserInteractionBegan?()
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let mapView, recognizer.state == .began else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            parent.onLongPress(coordinate)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // 標注のタップは MapKit の選択に任せる。
            var view = touch.view
            while let current = view {
                if current is MKAnnotationView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
