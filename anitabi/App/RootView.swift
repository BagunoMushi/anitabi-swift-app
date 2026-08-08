//
//  RootView.swift
//  anitabi
//
//  ============================================================================
//  RootView —— 全画面の地図 ＋ 積み重なる 3 枚の sheet
//  ============================================================================
//
//  呈现の入れ子はそのまま「戻る」の階段になっている（Web 版の history と同じ）：
//
//      RootView（地図）
//        └ HomeSheet（常駐・閉じられない）
//             ├ WorkCardSheet          ← 作品モード
//             │    └ PointCardSheet    ← 作品の中の 1 点
//             └ PointCardSheet         ← 作品モード外で地図から選んだ 1 点
//
//  地標カードを出す `.sheet` が 2 か所にあるのは、親が居るかどうかで呈现元が変わるため。
//  同じ Optional に 2 つの `.sheet` を同時に生かすと二重呈现になるので、Home 側は
//  「作品カードが無いときだけ」値を返す派生 Binding にしてある。
//
//  カメラ指令は Router ではなくここが持つ。同じ「地標を選ぶ」でも一覧経由なら寄り、
//  地図経由なら動かさない —— 経路の違いは呈现状態には出ないので、状態機には置けない。
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - 档

/// 3 枚それぞれの档。最小档の数値は各カードの見出しがちょうど残る高さ。
enum SheetLayout {
    static let homeMinHeight: CGFloat = 76
    static let workMinHeight: CGFloat = 128
    static let pointMinHeight: CGFloat = 96

    static let homeFraction = 0.40
    static let workFraction = 0.45
    static let pointFraction = 0.55

    static let homeMin = PresentationDetent.height(homeMinHeight)
    static let workMin = PresentationDetent.height(workMinHeight)
    static let pointMin = PresentationDetent.height(pointMinHeight)

    static let homeInitial = PresentationDetent.fraction(homeFraction)
    static let workInitial = PresentationDetent.fraction(workFraction)
    static let pointInitial = PresentationDetent.fraction(pointFraction)

    static let homeDetents: Set<PresentationDetent> = [homeMin, homeInitial, .large]
    static let workDetents: Set<PresentationDetent> = [workMin, workInitial, .large]
    static let pointDetents: Set<PresentationDetent> = [pointMin, pointInitial, .large]
}

// MARK: - RootView

struct RootView: View {

    @State private var store = AnitabiStore()
    @State private var locationProvider = LocationProvider()
    @State private var router = AppRouter()

    @State private var dataset = MapDataset.empty
    @State private var command: MapCameraCommand?
    /// 画面全体の大きさ。カード高さぶんの下余白・上寄せ量を実測値から出すために持つ。
    @State private var windowSize: CGSize = .zero

    @State private var homeDetent = SheetLayout.homeInitial
    @State private var workDetent = SheetLayout.workInitial
    @State private var pointDetent = SheetLayout.pointInitial

    var body: some View {
        mapLayer
            .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
            .sheet(isPresented: .constant(true)) { homeSheet }
            .task {
                if locationProvider.isAuthorized { locationProvider.start() }
                await store.bootstrap()
                // 名前・劇照は点数を変えずに後からマージされるので、完走後にもう一度取り込む。
                reloadDataset()
            }
            .onChange(of: store.points.count) { _, _ in reloadDataset() }
            .onChange(of: router.workCard) { _, new in didOpenWork(new) }
            .onChange(of: router.pointCard) { _, new in
                if new != nil { pointDetent = SheetLayout.pointInitial }
            }
    }

    // MARK: 地図

    private var mapLayer: some View {
        MapCanvas(
            dataset: dataset,
            command: command,
            focusedWorkID: router.focusedWorkID,
            selectedWorkIDs: router.selectedWorkIDs,
            selectedPointID: router.selectedPointID,
            onSelectPoint: { router.selectPoint($0) },  // 地図経由は镜头を動かさない
            onSelectWork: { router.focusWork(id: $0) },
            onTapDimRegion: { router.backToBrowse() },
            onTapBlank: { router.closePointCard() },
            onCameraIdle: { router.cameraState = $0 },
            // SwiftUI の `simultaneousGesture` でも拾えることは実測済み（3 枚重ねでも発火する）が、
            // あちらは 1 回のドラッグで数十回呼ばれ、ピンチは拾えない。began で 1 回だけの方を使う。
            onUserInteractionBegan: collapseTopSheet
        )
        .ignoresSafeArea()
    }

    // MARK: sheet 3 枚

    private var homeSheet: some View {
        HomeSheet(
            store: store,
            router: router,
            locationProvider: locationProvider,
            homeDetent: $homeDetent,
            onSelectPoint: { selectPointFromList($0) },
            onFocusCity: { focusCity($0) }
        )
            // 作品カードと（作品モード外の）地標カードは排他。1 つの `.sheet` にまとめて
            // 呈现元を 1 か所に保つ。
            .sheet(item: homeChild, onDismiss: { router.consumePendingWork() }) { child in
                switch child {
                case .work(let selection): workSheet(selection)
                case .point(let selection): pointSheet(selection)
                }
            }
            .presentationDetents(SheetLayout.homeDetents, selection: $homeDetent)
            // 半开までは地図に直接触れる。全开のときだけ sheet が地図を占有する。
            .presentationBackgroundInteraction(.enabled(upThrough: SheetLayout.homeInitial))
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
    }

    private func workSheet(_ selection: WorkSelection) -> some View {
        WorkCardSheet(
            store: store,
            workID: selection.id,
            selectedPointID: router.pointCard?.id,
            onSelectPoint: selectPointFromList,
            onClose: { router.closeWorkCard() },
            onRefit: { refitWork(selection.id) }
        )
        .sheet(item: workChildPoint, onDismiss: { router.consumePendingWork() }) { pointSheet($0) }
        .presentationDetents(SheetLayout.workDetents, selection: $workDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: SheetLayout.workInitial))
        .presentationDragIndicator(.visible)
    }

    private func pointSheet(_ selection: PointSelection) -> some View {
        PointCardSheet(
            store: store,
            router: router,
            locationProvider: locationProvider,
            selection: selection,
            onSelectWork: { router.handOffToWork(id: $0) },
            onClose: { router.closePointCard() }
        )
        .presentationDetents(SheetLayout.pointDetents, selection: $pointDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: SheetLayout.pointInitial))
        .presentationDragIndicator(.visible)
    }

    // MARK: 呈现の派生 Binding

    private enum HomeChild: Identifiable {
        case work(WorkSelection)
        case point(PointSelection)

        var id: String {
            switch self {
            case .work(let selection): "w\(selection.id)"
            case .point(let selection): "p\(selection.id)"
            }
        }
    }

    private var homeChild: Binding<HomeChild?> {
        Binding {
            if let work = router.workCard { return .work(work) }
            if let point = router.pointCard { return .point(point) }
            return nil
        } set: { newValue in
            guard newValue == nil else { return }  // 下スワイプで閉じられた場合だけ来る
            if router.workCard != nil {
                router.closeWorkCard()
            } else {
                router.closePointCard()
            }
        }
    }

    /// 作品カードの上に重ねる地標カード。作品カードが居ないときは Home 側が受け持つので nil。
    private var workChildPoint: Binding<PointSelection?> {
        Binding {
            router.workCard == nil ? nil : router.pointCard
        } set: { newValue in
            if newValue == nil { router.closePointCard() }
        }
    }

    // MARK: 動作

    /// 地図を触ったら、いちばん上のカードが最小档まで落ちる（Apple マップと同じ）。
    private func collapseTopSheet() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if router.pointCard != nil {
                pointDetent = SheetLayout.pointMin
            } else if router.workCard != nil {
                workDetent = SheetLayout.workMin
            } else {
                homeDetent = SheetLayout.homeMin
            }
        }
    }

    /// 作品カードが開いた（＝作品モードに入った）。档を初期値に戻し、全点を収める画へ。
    private func didOpenWork(_ selection: WorkSelection?) {
        workDetent = SheetLayout.workInitial
        guard let selection else { return }
        store.rememberVisit(bangumiID: selection.id)
        refitWork(selection.id)
    }

    /// 作品の全点が収まる画へ寄せ直す。初回 `didOpenWork` と「查看全部点位」ボタンの両方から呼ぶ。
    private func refitWork(_ id: Int) {
        let coordinates = (store.pointsByBangumi[id] ?? []).map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        command = .fitWork(coordinates, bottomInset: windowSize.height * SheetLayout.workFraction)
    }

    /// 一覧から地標を選んだ経路だけ镜头を寄せる。カードに隠れないよう半分ぶん上へ逃がす。
    private func selectPointFromList(_ point: ScenePoint) {
        router.selectPoint(point)
        command = .flyTo(point, verticalOffset: windowSize.height * SheetLayout.pointFraction / 2)
    }

    /// 都市タイル／検索の都市行 tap の镜头移動。`CityTile.radius` は集計円の半径でしかないので、
    /// 2.4 倍して市域全体が収まるくらいの見開きにする（spec に数値の指定は無い経験則）。
    private func focusCity(_ city: CityTile) {
        let latDelta = min(max(city.radius * 2.4 / 111_320, 0.02), 4)
        let lngDelta = latDelta / max(cos(city.center.latitude * .pi / 180), 0.2)
        command = .region(
            MKCoordinateRegion(
                center: city.center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
            )
        )
        // Apple マップ同様、都市へ寄せたら sheet は半开に落として地図を見せる。
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            homeDetent = SheetLayout.homeInitial
        }
    }

    /// `version` は単調増加させること。同じ値だと地図エンジンが索引の建て直しを省く。
    private func reloadDataset() {
        dataset = MapDataset(store: store, version: dataset.version + 1)
    }
}
