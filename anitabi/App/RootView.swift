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
import UIKit

// MARK: - 档

/// 3 枚それぞれの档。最小档の数値は各カードの見出しがちょうど残る高さ。
enum SheetLayout {
    /// 検索行の実測内訳 15 + 42 + 15。Apple マップの収起档（72–80pt）と同じ帯に収まる。
    static let homeMinHeight: CGFloat = 72
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

    /// 長押し落針カード。`.large` を持たない——見出し＋近点 3 行＋動作排で収まる軽いカードなので、
    /// 全画面まで持ち上げる意味が無い（spec 通り 2 档だけ）。
    static let droppedPinInitial = PresentationDetent.fraction(0.4)
    static let droppedPinDetents: Set<PresentationDetent> = [pointMin, droppedPinInitial]
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
    @State private var droppedPinDetent = SheetLayout.droppedPinInitial

    /// 浮控の地図钮（阶段 7）。`MapBaseStyle` に `String` raw value を持たせて `@AppStorage` に直接載せる。
    @AppStorage("map.baseStyle") private var baseStyle: MapBaseStyle = .standard
    @AppStorage("map.isPhotoLayerVisible") private var isPhotoLayerVisible = true

    /// 生の `MKMapView`。`MapCanvas.onMapViewReady` から 1 回もらう —— `MKCompassButton`/
    /// `MKScaleView` が `init(mapView:)` で同じインスタンスを要求するため。
    @State private var mapView: MKMapView?
    /// 定位钮の見た目だけの状態(授权+直近にタップ)。地図を自分でパン/ピンチしたら系统のフォロー同様に外す。
    @State private var isLocationActive = false

    // MARK: 深リンク／Handoff／状態復元（阶段 8）

    /// `store.bootstrap()` 完走前に着いた深リンク。完走した瞬間に 1 回だけ吐き出す。
    @State private var pendingDeepLink: MapDeepLink?
    /// `store.bootstrap()` が完走したか。深リンクをすぐ適用してよいかの判定に使う。
    @State private var isDataReady = false
    /// `focusWork` が `didOpenWork` 経由で自動 fitBounds するのを次の 1 回だけ黙らせる
    /// （深リンクの no-fly 変体——c/z が来ているときは fitBounds ではなく直接 center/zoom を使う）。
    @State private var suppressNextWorkFit = false
    /// 欢迎页（`hasCompletedOnboarding` が既に true でも「重看欢迎页」からもう一度立てられる）。
    /// 初期値は UserDefaults を 1 回だけ読む——`@AppStorage` にすると門と表示状態が同じキーに
    /// 縛られ、「見終わった後にもう一度見る」を表現できなくなる。
    @State private var isWelcomePresented = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    /// Handoff で運ぶ URL。`nil` の間は `.userActivity` を非アクティブにする。
    @State private var handoffURL: URL?
    @State private var handoffDebounceTask: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // SwiftUI の呈现キューは「シーン内で同時に有効な sheet 系は 1 枚」——
        // `.fullScreenCover` もこのキューを共有する（実機ログで確認：
        // `Currently, only presenting a single sheet is supported.` が Fault で出る）。
        // HomeSheet の `.sheet` は常駐（一度も dismiss されない）ので、素朴に
        // `.fullScreenCover` を足すだけだと欢迎页は「順番待ち」のまま永久に出番が来ない。
        // 対策は HomeSheet 側の `isPresented` を `!isWelcomePresented` にして、
        // 欢迎页を出している間だけ HomeSheet 自身の枠を明け渡すこと。
        //
        // スクリーンショット専用の透かし（`AppIdentityPillOverlay`）は旧 `ContentView` と同じく
        // 根部の ZStack に同居させる——欢迎页が出ている間は `.fullScreenCover` がまるごと覆うので
        // 自然に隠れる。
        ZStack {
            content
            AppIdentityPillOverlay()
        }
        .fullScreenCover(isPresented: $isWelcomePresented) {
            WelcomeView(onFinish: { isWelcomePresented = false })
        }
    }

    private var content: some View {
        mapLayer
            .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
            .sheet(isPresented: .constant(!isWelcomePresented)) { homeSheet }
            .task {
                if locationProvider.isAuthorized { locationProvider.start() }
                await store.bootstrap()
                // 名前・劇照は点数を変えずに後からマージされるので、完走後にもう一度取り込む。
                reloadDataset()
                isDataReady = true
                resolveInitialState()
            }
            .onChange(of: store.points.count) { _, _ in reloadDataset() }
            .onChange(of: router.workCard) { _, new in didOpenWork(new) }
            .onChange(of: router.pointCard) { _, new in
                if new != nil { pointDetent = SheetLayout.pointInitial }
            }
            .onChange(of: router.wantsWelcomeReplay) { _, wants in
                guard wants else { return }
                router.wantsWelcomeReplay = false
                isWelcomePresented = true
            }
            // Handoff（600ms 防抖）。選択状態と镜头静止のどちらも「今どこを見ているか」の
            // 一部なので、まとめて同じデバウンスに乗せる。
            .onChange(of: router.workCard) { _, _ in scheduleHandoffUpdate() }
            .onChange(of: router.pointCard) { _, _ in scheduleHandoffUpdate() }
            .onChange(of: router.selectedWorkIDs) { _, _ in scheduleHandoffUpdate() }
            .onChange(of: router.cameraState) { _, _ in scheduleHandoffUpdate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { currentDeepLink.persist() }
            }
            .userActivity(NSUserActivityTypeBrowsingWeb, isActive: handoffURL != nil) { activity in
                activity.webpageURL = handoffURL
                activity.isEligibleForHandoff = true
            }
            .onOpenURL { url in
                guard let link = MapDeepLink(url: url) else { return }
                receive(deepLink: link)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL, let link = MapDeepLink(url: url) else { return }
                receive(deepLink: link)
            }
    }

    // MARK: 地図

    private var mapLayer: some View {
        ZStack {
            MapCanvas(
                dataset: dataset,
                command: command,
                focusedWorkID: router.focusedWorkID,
                selectedWorkIDs: router.selectedWorkIDs,
                selectedPointID: router.selectedPointID,
                isPhotoLayerVisible: isPhotoLayerVisible,
                baseStyle: baseStyle,
                droppedPinCoordinate: router.droppedPin?.coordinate,
                onSelectPoint: { router.selectPoint($0) },  // 地図経由は镜头を動かさない
                onSelectWork: { router.focusWork(id: $0) },
                onTapDimRegion: { router.backToBrowse() },
                onTapBlank: { router.closePointCard() },
                onLongPress: { router.dropPin(at: $0) },
                onCameraIdle: { router.cameraState = $0 },
                // SwiftUI の `simultaneousGesture` でも拾えることは実測済み（3 枚重ねでも発火する）が、
                // あちらは 1 回のドラッグで数十回呼ばれ、ピンチは拾えない。began で 1 回だけの方を使う。
                onUserInteractionBegan: collapseTopSheet,
                // `makeUIView` の最中に `@State` を直接書き換えると「ビュー更新中に状態変更」の
                // 実行時警告になるので、必ず 1 拍遅らせる。
                onMapViewReady: { view in DispatchQueue.main.async { mapView = view } }
            )
            .ignoresSafeArea()

            // 浮控列・比例尺は安全区を尊重する側（`ignoresSafeArea` を掛けない ZStack の子）。
            // 地図だけが全画面まで伸び、これらは Dynamic Island／ノッチの下に自然に収まる。
            if let mapView {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        MapScaleView(mapView: mapView)
                            .fixedSize()
                        Spacer(minLength: 0)
                        MapControlStack(
                            mapView: mapView,
                            isLocationAuthorized: locationProvider.isAuthorized,
                            isLocationActive: $isLocationActive,
                            baseStyle: $baseStyle,
                            isPhotoLayerVisible: $isPhotoLayerVisible,
                            onLocationTap: handleLocationTap
                        )
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .opacity(isTopSheetFullyOpen ? 0 : 1)
                    .animation(.anitabiSpring, value: isTopSheetFullyOpen)
                    Spacer(minLength: 0)
                }
            }

            VStack(spacing: 0) {
                ToastOverlayView(toast: router.toast.current)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
    }

    /// いちばん上に乗っているカードが全开档か。全开は sheet が画面全体を覆うので、
    /// 浮控は地図ごと見えなくなる——出しっぱなしにする理由が無い。
    private var isTopSheetFullyOpen: Bool {
        if router.pointCard != nil { return pointDetent == .large }
        if router.workCard != nil { return workDetent == .large }
        return homeDetent == .large
    }

    // MARK: sheet 3 枚

    private var homeSheet: some View {
        HomeSheet(
            store: store,
            router: router,
            locationProvider: locationProvider,
            cameraState: router.cameraState,
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
            // 長押し落針カード。`AppRouter.dropPin` が work/point を先に畳んでいるので、
            // 上の `.sheet(item: homeChild)` と同時に値を持つことは無い。
            .sheet(item: droppedPinBinding) { pin in
                droppedPinSheet(pin)
            }
            .presentationDetents(SheetLayout.homeDetents, selection: $homeDetent)
            // 半开までは地図に直接触れる。全开のときだけ sheet が地図を占有する。
            .presentationBackgroundInteraction(.enabled(upThrough: SheetLayout.homeInitial))
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
    }

    private func droppedPinSheet(_ pin: DroppedPin) -> some View {
        DroppedPinSheet(
            store: store,
            coordinate: pin.coordinate,
            currentZoom: router.cameraState?.zoom ?? 0,
            onSelectPoint: { point in
                router.droppedPin = nil
                selectPointFromList(point)
            },
            onClose: { router.droppedPin = nil }
        )
        .presentationDetents(SheetLayout.droppedPinDetents, selection: $droppedPinDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: SheetLayout.droppedPinInitial))
        .presentationDragIndicator(.visible)
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

    /// `router.droppedPin` を `.sheet(item:)` に渡すための Binding。`AppRouter` は `@State`
    /// 経由で持っているので、`$router.droppedPin` の動的メンバー添字は使えない
    /// （`homeChild`/`workChildPoint` と同じ理由で自前の Binding を組む）。
    private var droppedPinBinding: Binding<DroppedPin?> {
        Binding {
            router.droppedPin
        } set: { newValue in
            if newValue == nil { router.droppedPin = nil }
        }
    }

    // MARK: 動作

    /// 地図を触ったら、いちばん上のカードが最小档まで落ちる（Apple マップと同じ）。
    /// 定位钮の「アクティブ」見た目もここで外す —— 系统のユーザー追従が自分でパンしたら
    /// 外れるのと同じ理屈（この App には本物の追従モードは無いが、見た目だけ揃える）。
    private func collapseTopSheet() {
        isLocationActive = false
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

    /// 浮控の定位钮。授权済みなら镜头を寄せて「アクティブ」表示に、拒否済みなら設定アプリへ、
    /// 未決定ならまず権限要求だけ行う(このタップでは镜头を動かさない——初回許可の自動 1 回寄せは
    /// A2 の別項目)。
    private func handleLocationTap() {
        switch locationProvider.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            // `.region`/`.flyTo`/`.fitWork` と違い `.userLocation` には static ファクトリが無い
            // （`MapCameraCommand.Kind` 側にしか生えていない）ので、直接組み立てる。
            command = MapCameraCommand(kind: .userLocation(span: 0.01))
            withAnimation(.anitabiSpring) { isLocationActive = true }
        case .denied, .restricted:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        default:
            locationProvider.requestAuthorization()
        }
    }

    /// 作品カードが開いた（＝作品モードに入った）。档を初期値に戻し、全点を収める画へ。
    /// 深リンクの no-fly 変体（c/z が来ている）ときは `suppressNextWorkFit` が立っているので、
    /// このフィットだけ 1 回黙る——訪問記録（`rememberVisit`）はそれでも取る。
    private func didOpenWork(_ selection: WorkSelection?) {
        workDetent = SheetLayout.workInitial
        guard let selection else { return }
        store.rememberVisit(bangumiID: selection.id)
        if suppressNextWorkFit {
            suppressNextWorkFit = false
            return
        }
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

    // MARK: 深リンク（阶段 8）

    /// `onOpenURL`/`onContinueUserActivity` の共通入口。データがまだ揃っていなければ
    /// 預けておくだけ——`store.bootstrap()` 完走後に `resolveInitialState()` が拾う。
    /// 揃っていれば即適用（実行中の受信＝アニメーション有り）。
    private func receive(deepLink link: MapDeepLink) {
        if isDataReady {
            apply(deepLink: link, animated: true)
        } else {
            pendingDeepLink = link
        }
    }

    /// `store.bootstrap()` が完走した瞬間の着地判定。優先順位は
    /// 「着信していた深リンク → 直前にバックグラウンドへ落ちたときの状態 → 位置情報が
    /// 許可済みならユーザーの現在地 → 何もしない（`MapCanvas.initialRegion` の日本全境）」。
    /// ここで動かすカメラはすべて無アニメーション——まだ何も描かれていない画面が
    /// 初めて絵になる瞬間なので、飛んで見せる意味が無い。
    private func resolveInitialState() {
        if let pending = pendingDeepLink {
            pendingDeepLink = nil
            apply(deepLink: pending, animated: false)
            return
        }
        if let restored = MapDeepLink.loadPersisted() {
            apply(deepLink: restored, animated: false)
            return
        }
        if locationProvider.isAuthorized {
            command = MapCameraCommand(kind: .userLocation(span: 0.01), animated: false)
        }
        // それ以外は何もしない —— `MapCanvas.initialRegion` の既定（日本全境）がそのまま出る。
    }

    /// 深リンク／状態復元／Handoff 着地の共通実行部。web 版の着地順そのまま：
    /// `bids` → 作品（c/z が有れば no-fly）→ 地標（地図経路と同じく镜头は動かさない）→
    /// 最後に c/z があれば直接そこへ。個々の id が見つからなければトーストで知らせるだけで
    /// 他のパラメータの処理は続ける（1 つ壊れていても丸ごと無視しない）。
    private func apply(deepLink link: MapDeepLink, animated: Bool) {
        guard !link.isEmpty else { return }

        if !link.bids.isEmpty {
            router.selectedWorkIDs = Set(link.bids)
        }

        let hasCameraTarget = link.center != nil && link.zoom != nil

        if let bangumiID = link.bangumiID {
            if store.bangumi(id: bangumiID) != nil {
                if hasCameraTarget { suppressNextWorkFit = true }
                router.focusWork(id: bangumiID)
            } else {
                // `ToastCenter.show` は素の `String` 引数なので、文字列カタログへ載せるには
                // ここで `String(localized:)` を経由する必要がある（`Text` と違い自動抽出されない）。
                router.toast.show(String(localized: "链接的内容不存在或已删除"), symbol: "exclamationmark.triangle")
            }
        }

        if let pointID = link.pointID {
            if let point = store.points.first(where: { $0.id == pointID }) {
                router.selectPoint(point)
            } else {
                // `ToastCenter.show` は素の `String` 引数なので、文字列カタログへ載せるには
                // ここで `String(localized:)` を経由する必要がある（`Text` と違い自動抽出されない）。
                router.toast.show(String(localized: "链接的内容不存在或已删除"), symbol: "exclamationmark.triangle")
            }
        }

        if let coordinate = link.center, let zoom = link.zoom {
            command = MapCameraCommand(kind: .center(coordinate, zoom: zoom), animated: animated)
        }
    }

    // MARK: Handoff（阶段 8）

    /// 選択状態・カメラを 1 つの `MapDeepLink` に写す。Handoff の発信にも
    /// バックグラウンド遷移時の状態保存にも、同じ値をそのまま使う。
    private var currentDeepLink: MapDeepLink {
        MapDeepLink(
            bangumiID: router.workCard?.id,
            pointID: router.pointCard?.id,
            center: router.cameraState?.region.center,
            zoom: router.cameraState?.zoom,
            bids: router.selectedWorkIDs.sorted()
        )
    }

    /// 600ms 防抖。選択やカメラが動いている最中に毎回 `NSUserActivity` を作り直さない。
    private func scheduleHandoffUpdate() {
        handoffDebounceTask?.cancel()
        handoffDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let link = currentDeepLink
            handoffURL = link.isEmpty ? nil : link.canonicalURL
        }
    }
}
