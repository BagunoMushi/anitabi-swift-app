//
//  RootView.swift
//  anitabi
//
//  ============================================================================
//  RootView —— 全画面の地図 ＋ **常に 1 枚だけ**の sheet
//  ============================================================================
//
//  Apple マップの呈现モデルをそのまま写す（2026-08-09 に 3 枚重ねから作り直した）。
//  実物を見ると分かる要点は 3 つ：
//
//  1. sheet は**同時に 1 枚しか居ない**。地点カードを開いた瞬間、下に居た検索 sheet は
//     画面から完全に消える（下層が一截だけ覗く、という見え方はしない）。
//  2. なので「重ねる」のではなく**中身を差し替える**。呈现スタックは `SheetContent` の
//     配列としてこちらで持ち、いちばん上だけを見せる。下の層は mount したまま隠すだけ——
//     検索文字列やスクロール位置を失わずに戻すため。
//  3. 覆われた層は**そのときの档を覚える**。上のカードを閉じると、下の層は初期档ではなく
//     覚えていた档で戻ってくる（「弹回来」）。
//
//  下スワイプでカードは閉じない（`interactiveDismissDisabled`）。いちばん低い档は各層の
//  mini 档で、閉じるのは ✕（作品カードは圧暗部タップも）だけ。
//
//  档の集合（`presentationDetents`）と選択中の档は**必ず同じトランザクション**で動かす。
//  別々に動かすと、新しい集合に入っていない古い選択が一瞬だけ適用されて档が跳ねる。
//
//  カメラ指令は Router ではなくここが持つ。同じ「地標を選ぶ」でも一覧経由なら寄り、
//  地図経由なら動かさない —— 経路の違いは呈现状態には出ないので、状態機には置けない。
//
//  档の定数（`SheetLayout` / `SheetLayer`）は `Sheets/SheetDesign.swift` にまとめてある。
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - RootView

struct RootView: View {

    // MARK: 呈现スタックの 1 要素

    /// 常駐 sheet に載る 1 枚ぶんの内容。`id` は**層＋対象**で決まる——同じ「作品カード」でも
    /// 別の作品なら別物として扱いたい（档の記憶も、View の identity も分けたい）ため。
    private enum SheetContent: Identifiable, Equatable {
        case home
        case work(WorkSelection)
        case point(PointSelection)
        case droppedPin(DroppedPin)

        var id: String {
            switch self {
            case .home: "home"
            case .work(let selection): "w\(selection.id)"
            case .point(let selection): "p\(selection.id)"
            case .droppedPin(let pin): "d\(pin.id)"
            }
        }

        var layer: SheetLayer {
            switch self {
            case .home: .home
            case .work: .work
            case .point: .point
            case .droppedPin: .droppedPin
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    @State private var store = AnitabiStore()
    @State private var locationProvider = LocationProvider()
    @State private var router = AppRouter()

    @State private var dataset = MapDataset.empty
    @State private var command: MapCameraCommand?
    /// 画面全体の大きさ。カード高さぶんの下余白・上寄せ量を実測値から出すために持つ。
    @State private var windowSize: CGSize = .zero

    // MARK: 呈现スタック（1 枚の sheet の中身）

    /// 下から順に積んだ内容。いちばん後ろ（`top`）だけが見えている。
    /// router の状態から導けるが、**@State に写して持つ**のが肝——内容と档を
    /// 同じ `withAnimation` の中で入れ替えるには、両方が @State である必要がある。
    @State private var stack: [SheetContent] = [.home]
    /// 常駐 sheet の生きている档。全層で 1 本だけ。
    @State private var detent: PresentationDetent = SheetLayer.home.initialDetent
    /// 覆われた層の档の記憶（key は `SheetContent.id`）。閉じて戻ってきたときに復元する。
    /// スタックから外れた層のぶんは毎回間引くので、中身は常に高々 3 件。
    @State private var rememberedDetents: [String: PresentationDetent] = [:]

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
        // 常駐 sheet は一度も dismiss されないので、素朴に `.fullScreenCover` を足すだけだと
        // 欢迎页は「順番待ち」のまま永久に出番が来ない。対策は常駐 sheet 側の `isPresented` を
        // `!isWelcomePresented` にして、欢迎页を出している間だけ枠を明け渡すこと。
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
            .sheet(isPresented: .constant(!isWelcomePresented)) { residentSheet }
            .task {
                if locationProvider.isAuthorized { locationProvider.start() }
                await store.bootstrap()
                // 名前・劇照は点数を変えずに後からマージされるので、完走後にもう一度取り込む。
                reloadDataset()
                isDataReady = true
                resolveInitialState()
            }
            .onChange(of: store.points.count) { _, _ in reloadDataset() }
            // 呈现スタックの唯一の同期点。router がどんな順で書き換わっても、
            // 落ち着いた後の姿がここに 1 回だけ届く（同一フレーム内の複数変更はまとめて 1 回）。
            .onChange(of: routerStack) { _, _ in syncStack() }
            .onChange(of: router.workCard) { _, new in didOpenWork(new) }
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
                // SwiftUI の `simultaneousGesture` でも拾えることは実測済みだが、
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
                    .opacity(detent == .large ? 0 : 1)
                    .animation(.anitabiSpring, value: detent == .large)
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

    // MARK: 常駐 sheet（1 枚）

    /// いちばん上に乗っている内容。呈现・档・背景交互の全部がこれ 1 つから決まる。
    private var top: SheetContent { stack.last ?? .home }

    /// 新しいカードは少し下から浮き上がりつつ現れ、古いカードはその場で淡出する。
    /// `.move(edge: .bottom)`（＝カード 1 枚ぶん丸ごとスライド）も試したが、
    /// 档が同時に動く（sheet 自体の高さが変わる）せいで 2 つの動きが喧嘩して見えた。
    /// Apple の実物も「カードが差し替わる」ように見えるだけで大きくは滑らないので、
    /// 浮き上がりは 24pt に留めて淡入淡出を主にする。
    private static let cardTransition = AnyTransition.asymmetric(
        insertion: .offset(y: 24).combined(with: .opacity),
        removal: .opacity
    )

    /// 常駐 sheet の中身。**閉じない・積まない**——中身だけが入れ替わる。
    ///
    /// 下の層を `if` で消さずに opacity で隠すのは、検索文字列・スクロール位置・
    /// 分组の折り畳み状態を保つため（消すと @State ごと作り直しになる）。
    private var residentSheet: some View {
        ZStack {
            ForEach(stack) { entry in
                sheetContent(entry)
                    .opacity(entry.id == top.id ? 1 : 0)
                    .allowsHitTesting(entry.id == top.id)
                    .accessibilityHidden(entry.id != top.id)
                    .transition(Self.cardTransition)
            }
        }
        // 档の集合と選択は同じ `top` から出る＝必ず同じ更新で入れ替わる。
        .presentationDetents(top.layer.detents, selection: $detent)
        // 半开までは地図に直接触れる。全开のときだけ sheet が地図を占有する。
        .presentationBackgroundInteraction(.enabled(upThrough: top.layer.initialDetent))
        .presentationDragIndicator(.visible)
        // 下スワイプで閉じない（＝各層の mini 档が下限）。閉じるのは ✕ だけ。
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func sheetContent(_ entry: SheetContent) -> some View {
        switch entry {
        case .home:
            HomeSheet(
                store: store,
                router: router,
                locationProvider: locationProvider,
                cameraState: router.cameraState,
                homeDetent: $detent,
                onSelectPoint: { selectPointFromList($0) },
                onFocusCity: { focusCity($0) }
            )
        case .work(let selection):
            WorkCardSheet(
                store: store,
                workID: selection.id,
                selectedPointID: router.pointCard?.id,
                onSelectPoint: selectPointFromList,
                onClose: { router.closeWorkCard() },
                onRefit: { refitWork(selection.id) }
            )
        case .point(let selection):
            PointCardSheet(
                store: store,
                router: router,
                locationProvider: locationProvider,
                selection: selection,
                onSelectWork: { router.handOffToWork(id: $0) },
                onClose: { router.closePointCard() }
            )
        case .droppedPin(let pin):
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
        }
    }

    // MARK: 呈现スタックの同期

    /// router の状態をそのまま積み上げた「本来あるべきスタック」。
    private var routerStack: [SheetContent] {
        var result: [SheetContent] = [.home]
        if let work = router.workCard { result.append(.work(work)) }
        if let point = router.pointCard { result.append(.point(point)) }
        if let pin = router.droppedPin { result.append(.droppedPin(pin)) }
        return result
    }

    /// 内容と档を 1 回のトランザクションで入れ替える。ここが呈现モデルの心臓部：
    ///
    /// - **上へ開く**（深さが増える／同じ深さで別物に替わる）→ 新しい層は**初期档**で出す。
    ///   同時に、覆われる層の「今の档」を覚える。
    /// - **下へ戻る**（深さが減る）→ 覚えていた档があればそれを**復元**する（「弹回来」）。
    ///   一度も見せていない層（深リンクで飛び越えた作品カードなど）は記憶が無いので初期档。
    private func syncStack() {
        let next = routerStack
        let current = top
        guard let target = next.last, target.id != current.id else {
            // いちばん上が同じなら档は動かさない（下の層だけ入れ替わった場合）。
            if next != stack { stack = next }
            return
        }

        var memory = rememberedDetents
        memory[current.id] = detent

        let restored = target.layer < current.layer ? memory[target.id] : nil
        memory.removeValue(forKey: target.id)
        // スタックから外れた層の記憶は捨てる（作品を渡り歩いても増えないように）。
        let live = Set(next.map(\.id))
        rememberedDetents = memory.filter { live.contains($0.key) }

        withAnimation(.anitabiSpring) {
            stack = next
            detent = restored ?? target.layer.initialDetent
        }
    }

    // MARK: 動作

    /// 地図を触ったら、いちばん上のカードが最小档まで落ちる（Apple マップと同じ）。
    /// 定位钮の「アクティブ」見た目もここで外す —— 系统のユーザー追従が自分でパンしたら
    /// 外れるのと同じ理屈（この App には本物の追従モードは無いが、見た目だけ揃える）。
    private func collapseTopSheet() {
        isLocationActive = false
        withAnimation(.anitabiSpring) { detent = top.layer.minDetent }
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

    /// 作品カードが開いた（＝作品モードに入った）。全点を収める画へ。
    /// 档は `syncStack()` が面倒を見るのでここでは触らない。
    /// 深リンクの no-fly 変体（c/z が来ている）ときは `suppressNextWorkFit` が立っているので、
    /// このフィットだけ 1 回黙る——訪問記録（`rememberVisit`）はそれでも取る。
    private func didOpenWork(_ selection: WorkSelection?) {
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
        withAnimation(.anitabiSpring) { detent = SheetLayer.home.initialDetent }
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
    ///
    /// 呈现側は一切ここで触らない——router を書き換えれば `syncStack()` が
    /// 「作品カードの上に地標カードが乗ったスタック」を勝手に組み立てる。
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
