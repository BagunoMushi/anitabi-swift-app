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

// MARK: - 常駐 sheet の生の寸法

/// `residentSheet` の中身の実寸。**sheet の内側**で測った値だけを持つ。
private struct SheetGeometry: Equatable {
    /// 中身の高さ。拖动の途中も毎フレーム更新される。
    var height: CGFloat = 0
    /// 中身に入る底部安全区。
    var bottomInset: CGFloat = 34
    /// 中身の枠の画面座標。可視カード（`SheetShapeReader` の実測）との差を出すのに使う。
    var minY: CGFloat = 0
    /// 系统が中身の**外側・上**に確保している帯（抓手ぶん）。
    /// 「中身の上端の画面座標」−「档の高さから逆算した sheet の上端」で実測する。
    /// ここを見積もりで埋めると一段式の下余白が必ずずれるので、必ず実測値を使う。
    var topChrome: CGFloat = 0
}

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
    /// 常駐 sheet の中身の生の寸法。**sheet の内側**で測る —— 窓の底部安全区（実測 34）と
    /// sheet の中身に入る底部安全区（実測 32）は別の値で、後者でないと最小档が 2pt ずれる。
    /// 高さは拖动の**途中も**毎フレーム届くので、いま何段目かの判定にもこれを使う。
    @State private var sheetGeometry = SheetGeometry()
    /// 各層が報せてきた「一段式の中身の実高」。最小档はこの実測値で組む
    /// ——定数だと Dynamic Type・言語で必ずズレる（一段式は「身份条がちょうど残る高さ」なので、
    /// ズレると余る／切れる）。一度届いた値は消さずに残す。
    @State private var compactHeights: [SheetLayer: CGFloat] = [:]
    /// 各層が報せてきた「中身の実高」（两段式・三段式ぶん）。設計稿の比率を**上限**として、
    /// 中身がそこまで無いカードは档をここまで詰める（`SheetLayer.initialHeight` / `maxHeight`）——
    /// 比率は固定・中身は可変なので、詰めないと同じ地標カードでも剧照／備考の有無で
    /// カードの下が 40〜300pt 空く。
    @State private var fittedHeights: [SheetLayer: SheetContentHeights] = [:]
    /// 上の値の反映待ち。档を跨ぐ最中は剧照が伸び縮みし切るまで毎フレーム値が変わるので、
    /// 落ち着いてから 1 回だけ档へ渡す。
    @State private var fitTask: Task<Void, Never>?
    /// 可視カードの枠（`SheetShapeReader` の実測。グローバル座標）。
    @State private var cardFrame: CGRect?
    /// 三段式より下に居るときに見たカードの上縁（window 座標）。署名・浮控の蓋の実測値
    /// （`attributionLift` / `recordRestingCardTop`）。
    @State private var restingCardTopY: CGFloat?

    // MARK: 呈现スタック（1 枚の sheet の中身）

    /// 下から順に積んだ内容。いちばん後ろ（`top`）だけが見えている。
    /// router の状態から導けるが、**@State に写して持つ**のが肝——内容と档を
    /// 同じ `withAnimation` の中で入れ替えるには、両方が @State である必要がある。
    @State private var stack: [SheetContent] = [.home]
    /// 常駐 sheet の生きている档。全層で 1 本だけ。
    @State private var detent: PresentationDetent = SheetLayout.detent(
        SheetLayer.home.initialFraction,
        screenHeight: DesignScale.screenHeight
    )
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

    // MARK: 作品モードの枠追従

    /// 档が動いたら作品の枠を置き直すか。作品カードを開いた／「全部点位」を押した時点で true、
    /// **ユーザーが自分で地図を動かしたら false** —— 自分で決めた画角を档の上下で奪われるのは、
    /// Apple マップでも起きない振る舞い。もう一度合わせたい人は「全部点位」を押せる。
    @State private var workFitFollowsSheet = false
    @State private var workFitTask: Task<Void, Never>?
    /// 直近のフィットで使った可視カードの上縁。帯が実質変わっていない档移動を弾くのに使う。
    @State private var lastWorkFitCardTop: CGFloat?

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
    /// 字級。**値そのものは使わない** —— 寸法トークン（`SheetMetrics` / `SheetFont`）は
    /// `UITraitCollection.current` を直に読むので、SwiftUI から見ると字級への依存が無く、
    /// 「設定」で字を変えても木が作り直されない限り古い寸法のまま描き続ける（実測）。
    /// `@ScaledMetric` は環境値を読むのでこの問題が起きない —— こちらは環境値を 1 つ読んで
    /// カードの identity に混ぜ、字級が変わったら中身を作り直させる（`residentSheet` の `.id`）。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // 設計稿（claude.ai/design「圣地巡礼卡片组件」）の Zen Maru Gothic に最も近い系统書体。
        // 根で 1 回だけ掛けて、シート・浮控・トーストの全部を同じ書体に揃える
        // （等幅にしたい座標／EP 徽章だけ `SheetFont` 側で `.monospaced()` を上書きする）。
        .fontDesign(.rounded)
        .fullScreenCover(isPresented: $isWelcomePresented) {
            WelcomeView(onFinish: { isWelcomePresented = false })
        }
    }

    private var content: some View {
        mapLayer
            // 見えている地図の大きさ。一覧から選んだ点をカードの上へ逃がす量に使う
            // （`selectPointFromList`）。作品フィットの帯はこちらではなく可視カードの実測を使う
            // （`refitWork` のメモ参照）。
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
            // 地標カードを ✕ で閉じて作品カードへ戻ったら、作品の全点が収まる画へ寄せ直す。
            // 一覧から点を選んだ時点で镜头はその 1 点に寄っている（`selectPointFromList`）ので、
            // 戻ったのに寄ったままだと「一覧に戻ったのに地図は別の話をしている」状態になる。
            // これがあるので中/大档には「查看全部点位」の釦を置かない（`WorkCardSheet`）。
            //
            // 針を落とした／作品カードごと閉じた経路では `workCard` も同時に nil になるので、
            // ここは自然に黙る（＝作品カードへ**戻った**ときだけ効く）。
            .onChange(of: router.pointCard) { old, new in
                guard old != nil, new == nil, router.workCard != nil else { return }
                // 档は `syncStack()` が同じフレームで作品カードの記憶値へ戻す。帯が確定してから
                // 測りたいので、ここは即時フィットではなく追従（防抖）に乗せる。
                workFitFollowsSheet = true
                lastWorkFitCardTop = nil
                scheduleWorkRefit()
            }
            // 档が吸着したら枠を置き直す（畳めば中央へゆっくり収まる）。`PresentationDetent` は
            // 吸着後にしか変わらないので、拖动の途中に镜头が付いてくることはない。
            .onChange(of: detent) { _, _ in scheduleWorkRefit() }
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
                attributionLift: attributionLift,
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
            // 浮控列は**地図の overlay として**載せ、`.ignoresSafeArea()` は**その後**に掛ける。
            // 順番が肝：`.ignoresSafeArea()` の後ろに付けた overlay は「広がる前」の枠
            // （下端 ＝ 安全区の上端）に並ぶので、`mapView.bounds.maxY`（＝窓の下端）を
            // 物差しにしている下余白と 34pt 食い違う —— 実測で 34pt 高く浮いた。
            // 内側に入れれば地図と同じ枠（窓いっぱい）で並び、署名と同じ物差しが通る。
            .overlay(alignment: .bottomTrailing) {
                if let mapView {
                    mapControls(mapView)
                        .opacity(isMapChromeHidden ? 0 : 1)
                        .animation(.anitabiSpring, value: isMapChromeHidden)
                }
            }
            .ignoresSafeArea()

            // 比例尺は左上のまま（Apple マップ同位）。安全区を尊重する側に置くので
            // Dynamic Island／ノッチの下に自然に収まる。
            if let mapView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        MapScaleView(mapView: mapView)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                }
                .opacity(isMapChromeHidden ? 0 : 1)
                .animation(.anitabiSpring, value: isMapChromeHidden)
            }

            VStack(spacing: 0) {
                ToastOverlayView(toast: router.toast.current)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        }
    }

    /// 浮控列（定位・底図・方位）。左下の署名と同じく、カードの上縁に貼り付いて拖动に追従する。
    private func mapControls(_ mapView: MKMapView) -> some View {
        MapControlStack(
            mapView: mapView,
            isLocationAuthorized: locationProvider.isAuthorized,
            isLocationActive: $isLocationActive,
            baseStyle: $baseStyle,
            isPhotoLayerVisible: $isPhotoLayerVisible,
            onLocationTap: handleLocationTap
        )
        .padding(.trailing, 16)
        .padding(.bottom, controlsBottomMargin(mapView))
    }

    /// 浮控列の下余白＝「地図の下端からカードの上縁まで」＋隙間。
    ///
    /// 持ち上げ量は**署名とまったく同じ関数から取る**（`MapAttributionLift.resolvedLift`）——
    /// 座標変換も蓋もあちらに 1 つだけ置いてあるので、左下の署名と右下の浮控が別の物差しに
    /// 分かれることがない。ここが自前計算だった版は、SwiftUI で測った枠が `.ignoresSafeArea()`
    /// で広がる前の値だったせいで 18pt 低く出た（実機）。
    private func controlsBottomMargin(_ mapView: MKMapView) -> CGFloat {
        let gap = Self.controlsCardGap
        let lift = attributionLift
        // 実測が届く前（初回フレーム・欢迎页の裏）は两段式の見積もりに置いておく。
        return (lift.resolvedLift(in: mapView) ?? lift.ceiling) + gap
    }

    /// カードの上縁との隙間（Apple マップ実物と同じ「浮きぶん 8 ＋ 8」）。
    private static let controlsCardGap = SheetLayout.floatingGap + 8


    /// 三段式（設計稿 92.2%）まで持ち上がったら地図の付属品（浮控・比例尺）は退かせる。
    private var isMapChromeHidden: Bool { stage(of: top) == .expanded }

    /// 署名（Apple ロゴ＋「法的情報」）をカードの上へ逃がす指令。
    ///
    /// Apple マップの実物と同じ：カードを一段式から持ち上げていく間、署名はその上縁に
    /// 貼り付いたまま一緒に上がる。ただし**三段目までは追わない** —— 全开したカードは
    /// 署名を覆ってよく、追うと署名だけが地図の上端まで登って浮いて見える。
    /// なので蓋（`ceiling`）は两段式のカードの上縁に置く。
    ///
    /// 上縁は `SheetShapeReader` の実測（拖动の途中も毎フレーム届く）。
    ///
    /// 蓋は**実測を第一の出所にする**（`restingCardTopY`）。档の高さから組んだ見積もり
    /// （档 ＋ 底部安全区 ＋ 浮きぶん）だけで蓋をしていた版は、見積もりが実際のカードより
    /// 低く出た端末で `min(実測, 蓋)` が蓋を選び、**署名も浮控もカードの下に潜った**（実機）。
    /// 見積もりは実測が 1 回も届いていない間の代役でしかない（`resolvedLift` 参照）。
    private var attributionLift: MapAttributionLift {
        let layer = top.layer
        let medium = layer.initialHeight(
            screenHeight: DesignScale.screenHeight, fitted: fittedHeights[layer]
        )
        return MapAttributionLift(
            cardTopY: cardFrame?.minY,
            restingCardTopY: restingCardTopY,
            ceiling: medium + sheetGeometry.bottomInset + SheetLayout.floatingGap
        )
    }

    /// 三段式へ持ち上げる前（一段式〜两段式）に見たカードの上縁を覚える＝蓋の実測値。
    /// window 座標をそのまま持つので、`mapView` がまだ来ていなくても記録できる
    /// （`SheetShapeReader` は同じ枠を 2 回報せない —— 取り逃すと二度と来ない）。
    /// カードが差し替わったら忘れる（層ごとに两段式の高さが違う）。
    private func recordRestingCardTop(_ frame: CGRect?) {
        guard let frame, stage(of: top) != .expanded else { return }
        restingCardTopY = frame.minY
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
        ZStack(alignment: .top) {
            ForEach(stack) { entry in
                sheetContent(entry)
                    // 隠れた層の最小高さを sheet に**伝えない**。首页の身份条（検索行＋chips）は
                    // 潰せないので、他カードの一段式（それより低い）では ZStack の最小高さが档を超え、
                    // 系统が中身をセンタリングして**カードの上下へはみ出す**（実測）。
                    // 隠れた層は高さ 0 の枠に上詰めで収める——mount したまま・状態は保つ。
                    .frame(maxHeight: entry.id == top.id ? .infinity : 0, alignment: .top)
                    .opacity(entry.id == top.id ? 1 : 0)
                    .allowsHitTesting(entry.id == top.id)
                    .accessibilityHidden(entry.id != top.id)
                    .transition(Self.cardTransition)
            }
        }
        // 字級が変わったらカードを作り直す（上の `dynamicTypeSize` のメモ参照）。
        // 巻き戻るのはスクロール位置と検索文字列だけで、呈现スタックと档は RootView 側なので残る。
        .id(dynamicTypeSize)
        // 設計稿の一段式は身份条の下が 14px しかない。系统は中身を底部安全区の**上**に
        // 閉じ込めるので、ここで無効にして可視カードの下端まで使う（スクロールする列の
        // 末尾だけ環境値 `sheetBottomInset` で足し戻す）。
        // **必ず呈现修饰（presentationDetents 等）より内側に付けること** —— 外側（presentation
        // 修飾の後ろ）に付けた版は無効で、中身がカード下端に届かないのに safeAreaInsets だけ
        // 34 を報せていた（実測）。
        .ignoresSafeArea(.container, edges: .bottom)
        // 档の集合と選択は同じ `top` から出る＝必ず同じ更新で入れ替わる。
        .presentationDetents(
            top.layer.detents(
                measured: compactHeights[top.layer],
                fitted: fittedHeights[top.layer],
                screenHeight: DesignScale.screenHeight
            ),
            selection: $detent
        )
        // カードの地は設計稿そのまま —— `blur(24px) saturate(1.6)`（＝系统の material）の上に
        // 「淡緑 #D4FFD5 ＋ 白 55%」の合成色 #ECFFEC を敷く。**中身の面**（一覧カード・
        // カプセル）はガラスにしない（設計稿も白い薄膜であって、ガラスの重ね掛けはしていない）。
        //
        // iOS 26 の公式指針は「`presentationBackground` を使わず系统の Liquid Glass に任せる」だが、
        // **ここは意図的に外れる**：系统のガラスは透けすぎて、地図の海（青）・緑地・全彩の剧照標が
        // そのままカードに映り込む（実機で確認済み。同じ見た目を一度出して却下されている）。
        // 設計稿の地色はこのアプリの identity なので、公式指針より設計稿を優先する。
        .presentationBackground {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(Color.anitabiCardGlass)
                .ignoresSafeArea()
        }
        // 半开までは地図に直接触れる。全开のときだけ sheet が地図を占有する。
        .presentationBackgroundInteraction(.enabled(upThrough: initialDetent(top.layer)))
        .presentationDragIndicator(.visible)
        // 下スワイプで閉じない（＝各層の mini 档が下限）。閉じるのは ✕ だけ。
        .interactiveDismissDisabled()
        .environment(\.sheetBottomInset, sheetGeometry.bottomInset)
        // 可視カード（系统が描く浮きカプセル）の枠を UIKit 側から実測する。SwiftUI の中身の枠とは
        // 一致せず、系统は API でも safe area でも教えてくれないので、ここだけ UIKit を覗く。
        .background {
            SheetShapeReader { frame in
                cardFrame = frame
                recordRestingCardTop(frame)
            }
        }
        .environment(\.compactBarInsets, compactBarInsets)
        .onGeometryChange(for: SheetGeometry.self) { proxy in
            SheetGeometry(
                height: proxy.size.height,
                bottomInset: proxy.safeAreaInsets.bottom,
                minY: proxy.frame(in: .global).minY,
                topChrome: proxy.frame(in: .global).minY - (DesignScale.screenHeight - proxy.size.height)
            )
        } action: { sheetGeometry = $0 }
        // 身份条の実高が届いたら覚える。1pt 未満の揺れでは書き換えない
        // （拖动中に @State を毎フレーム書くと档の集合が作り直されて操作が重くなる）。
        .onPreferenceChange(CompactContentHeightKey.self) { measured in
            for (layer, height) in measured where height > 1 {
                let old = compactHeights[layer]
                guard abs((old ?? -1) - height) > 1 else { continue }
                compactHeights[layer] = height
                // 一段式に**居る最中**に身份条の実高が変わったら（chips 行の出入りなど）、
                // 選択中の档も同じ更新で新しい最小档へ移す。置き去りにすると古い選択が
                // 新しい集合に無くなり、系统が sheet を初期档まで跳ね上げる（実測）。
                if layer == top.layer, detent == layer.minDetent(measured: old) {
                    detent = layer.minDetent(measured: height)
                }
            }
        }
        // 中身の実高。こちらは**いちばん上の層のぶんだけ**採る（隠れた層は見えないまま
        // 中身が変わることがあり、その値で見えている档を動かす理由が無い）。
        .onPreferenceChange(FittedContentHeightKey.self) { measured in
            guard let content = measured[top.layer] else { return }
            // 中身の実高 → 档の高さ。可視カードは档より底部安全区ぶん高い
            // （`SheetLayout.minHeight` のメモ：可視高さ ＝ h ＋ 底部安全区）。
            let inset = sheetGeometry.bottomInset
            scheduleFit(
                layer: top.layer,
                heights: SheetContentHeights(medium: content.medium - inset, expanded: content.expanded - inset)
            )
        }
    }

    /// 档を中身の実高まで詰める。**すぐには適用しない** —— 档を跨ぐ最中は剧照が
    /// 伸び縮みし切るまで毎フレーム値が変わるので、落ち着いてから 1 回だけ渡す。
    /// 待ちは 80ms —— カードが開くバネ（0.35s）より短いので、開いた直後の補正は
    /// その動きに溶けて 1 つの動作に見える。
    private func scheduleFit(layer: SheetLayer, heights: SheetContentHeights) {
        fitTask?.cancel()
        guard let old = fittedHeights[layer] else {
            // その層の初回だけは待たずに入れる（待つと開くバネの後に一段遅れて動く）。
            applyFit(layer: layer, heights: heights, old: nil)
            return
        }
        guard abs(old.medium - heights.medium) > 1 || abs(old.expanded - heights.expanded) > 1 else { return }
        fitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            applyFit(layer: layer, heights: heights, old: old)
        }
    }

    /// 詰めた高さを档へ。**選択中の档も同じ更新で移す** —— 置き去りにすると古い選択が
    /// 新しい集合から消え、系统が档を跳ねさせる（最小档と同じ理屈）。
    private func applyFit(layer: SheetLayer, heights: SheetContentHeights, old: SheetContentHeights?) {
        let screenHeight = DesignScale.screenHeight
        let wasInitial = detent == layer.initialDetent(screenHeight: screenHeight, fitted: old)
        let wasMax = detent == layer.maxDetent(screenHeight: screenHeight, fitted: old)
        withAnimation(.anitabiSpring) {
            fittedHeights[layer] = heights
            guard layer == top.layer else { return }
            if wasInitial {
                detent = layer.initialDetent(screenHeight: screenHeight, fitted: heights)
            } else if wasMax {
                detent = layer.maxDetent(screenHeight: screenHeight, fitted: heights)
            }
        }
    }

    /// 迷你条の「中身の枠」と「可視カード」のズレ。身份条の上下余白はこれを足してから置く
    /// （`CompactBarRow`）—— 定数で埋めると機種・OS 更新でずれる。
    /// 一段式に居るときだけ意味がある値なので、それ以外は 0（＝素の余白）に落とす。
    private var compactBarInsets: CompactBarInsets {
        guard let cardFrame, stage(of: top) == .compact, sheetGeometry.height > 0 else {
            return CompactBarInsets()
        }
        let contentTop = sheetGeometry.minY
        let barBottom = contentTop + SheetLayout.minHeight(compactHeights[top.layer] ?? top.layer.minContentFallback)
        // 0.5pt 未満は捨てる（実測値が毎フレーム微動するとレイアウトが揺れ続ける）。
        func quantized(_ value: CGFloat) -> CGFloat { (max(0, value) * 2).rounded() / 2 }
        return CompactBarInsets(
            top: quantized(cardFrame.minY - contentTop),
            bottom: quantized(barBottom - cardFrame.maxY)
        )
    }

    /// 两段式の档（層ごとの実測反映込み）。呈现・背景交互・镜头の全部がこれを使う。
    private func initialDetent(_ layer: SheetLayer) -> PresentationDetent {
        layer.initialDetent(screenHeight: DesignScale.screenHeight, fitted: fittedHeights[layer])
    }

    /// 三段式の档（同上）。
    private func maxDetent(_ layer: SheetLayer) -> PresentationDetent {
        layer.maxDetent(screenHeight: DesignScale.screenHeight, fitted: fittedHeights[layer])
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
                stage: stage(of: entry),
                expandedDetent: maxDetent(.home),
                initialDetent: initialDetent(.home),
                onSelectPoint: { selectPointFromList($0) },
                onFocusCity: { focusCity($0) }
            )
        case .work(let selection):
            WorkCardSheet(
                store: store,
                workID: selection.id,
                selectedPointID: router.pointCard?.id,
                isMinimized: stage(of: entry) == .compact,
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
                stage: stage(of: entry),
                onSelectWork: { router.handOffToWork(id: $0) },
                onClose: { router.closePointCard() }
            )
        case .droppedPin(let pin):
            DroppedPinSheet(
                store: store,
                coordinate: pin.coordinate,
                currentZoom: router.cameraState?.zoom ?? 0,
                stage: stage(of: entry),
                onSelectPoint: { point in
                    router.droppedPin = nil
                    selectPointFromList(point)
                },
                onClose: { router.droppedPin = nil }
            )
        }
    }

    /// いま何段目に居るか（設計稿 t2 の 小/中/大）。
    ///
    /// 判定に `PresentationDetent` の等値比較を使わないのが肝：あれは**吸着した後**にしか変わらないので、
    /// 「一段式では身份条より下を描かない」を等値比較で実装すると、拖动の途中はカードが空のまま伸びて
    /// 吸着した瞬間に中身が湧く、という見え方になる。生の高さで見れば指の動きにそのまま追従する。
    ///
    /// 境界は隣の档との**中点**に置く（`.height()` で頼んだ値と実際の中身の高さには数 pt のズレがあるので、
    /// 等値に近い閾値だと取りこぼす）。隠れている層は常に「中」——見えていない頭部を作り替える意味が無い。
    private func stage(of entry: SheetContent) -> SheetStage {
        guard entry.id == top.id, sheetGeometry.height > 0 else { return .medium }
        let layer = entry.layer
        let minHeight = SheetLayout.minHeight(compactHeights[layer] ?? layer.minContentFallback)
        let initialHeight = layer.initialHeight(screenHeight: DesignScale.screenHeight, fitted: fittedHeights[layer])
        let maxHeight = layer.maxHeight(screenHeight: DesignScale.screenHeight, fitted: fittedHeights[layer])

        // 目標高さのうち、いま実際にいちばん近いものを採る。
        // （`.height()` で頼んだ値と実際の中身の高さには数 pt のズレがあるので閾値では取りこぼす）
        var targets: [(SheetStage, CGFloat)] = [(.compact, minHeight), (.medium, initialHeight)]
        // 三段目を持たない層（地標カード）では `.expanded` を候補に入れない —— 入れると
        // 行けもしない档に吸い寄せられて頭部や剧照が別物に化ける。
        if layer.hasExpandedStage { targets.append((.expanded, maxHeight)) }
        return targets.min { abs($0.1 - sheetGeometry.height) < abs($1.1 - sheetGeometry.height) }?.0 ?? .medium
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

        // 蓋の実測値は層ごとに違う（两段式の高さが違う）ので、カードが差し替わったら捨てる。
        restingCardTopY = nil

        withAnimation(.anitabiSpring) {
            stack = next
            detent = restored ?? initialDetent(target.layer)
        }
    }

    // MARK: 動作

    /// 地図を触ったら、いちばん上のカードが最小档まで落ちる（Apple マップと同じ）。
    /// 定位钮の「アクティブ」見た目もここで外す —— 系统のユーザー追従が自分でパンしたら
    /// 外れるのと同じ理屈（この App には本物の追従モードは無いが、見た目だけ揃える）。
    private func collapseTopSheet() {
        isLocationActive = false
        // 自分で地図を動かした人の画角は奪わない —— これから落ちる档の変化で枠へ寄せ直すと、
        // パンし始めた瞬間に镜头が戻ってしまう。
        stopWorkFitFollowing()
        withAnimation(.anitabiSpring) {
            detent = top.layer.minDetent(measured: compactHeights[top.layer])
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

    /// 作品カードが開いた（＝作品モードに入った）。全点を収める画へ。
    /// 档は `syncStack()` が面倒を見るのでここでは触らない。
    /// 深リンクの no-fly 変体（c/z が来ている）ときは `suppressNextWorkFit` が立っているので、
    /// このフィットだけ 1 回黙る——訪問記録（`rememberVisit`）はそれでも取る。
    private func didOpenWork(_ selection: WorkSelection?) {
        guard let selection else {
            // 作品モードを出たら追従も畳む（次に開いた作品が古い指令を拾わないように）。
            stopWorkFitFollowing()
            return
        }
        store.rememberVisit(bangumiID: selection.id)
        if suppressNextWorkFit {
            suppressNextWorkFit = false
            // 深リンクが c/z を指定している＝画角は呼び出し側が決めている。档の上下で奪わない。
            stopWorkFitFollowing()
            return
        }
        refitWork(selection.id)
    }

    private func stopWorkFitFollowing() {
        workFitTask?.cancel()
        workFitTask = nil
        workFitFollowsSheet = false
        lastWorkFitCardTop = nil
    }

    /// 作品の枠が丸ごと収まる画へ寄せ直す。初回 `didOpenWork`・地標カードから戻ったとき・
    /// 一段式身份条の「全部点位」・档を動かしたとき（`scheduleWorkRefit`）から呼ぶ。
    ///
    /// 収める相手は**圧暗レイヤーが実際に描いている多角形**（`WorkRegionOverlay.hull`）。
    /// 以前は点群をそのまま `fitRect` に渡していたが、あちらは離群点を切り捨てるので
    /// 浜松〜上信越に散る作品（ゆるキャン△ SEASON 3 など）では枠の外側が画面に入らなかった
    /// ——**枠と镜头が別の点集合を見ていた**のが原因（実機で確認）。
    ///
    /// カードに譲る帯は指定しない：`MapCanvas` が可視カードの上縁を実測して使う（署名・浮控と
    /// 同じ物差し）。設計稿の比率で見積もっていた版は、档を畳んでも帯が縮まなかった。
    private func refitWork(_ id: Int) {
        let coordinates = (store.pointsByBangumi[id] ?? []).map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        workFitFollowsSheet = true
        lastWorkFitCardTop = cardFrame?.minY
        if let hull = WorkRegionOverlay.hull(for: coordinates) {
            command = .fitWork(hull, trimsOutliers: false)
        } else {
            // 判定範囲外（海外点を含む）の作品は圧暗レイヤーも出ないので、従来の点群フィット。
            command = .fitWork(coordinates)
        }
    }

    /// 档が動いたら、作品の枠を新しい可視域へ置き直す（「畳んだら中央へゆっくり収まる」）。
    ///
    /// **カードが動き終わってから測る**のが肝：`PresentationDetent` は吸着した瞬間に変わるが、
    /// 可視カード（`cardFrame`）はそこからバネで動くので、すぐ測ると前の档の帯でフィットする。
    ///
    /// 帯がほとんど変わっていないときは動かさない（`lastWorkFitCardTop` と比較）——
    /// 作品カードを開いた直後は「首页の两段式 → 作品の两段式」で十数 pt しか違わないので、
    /// これが無いと入場のフライトが着地寸前に上書きされて二度動く。
    private func scheduleWorkRefit() {
        guard workFitFollowsSheet, let work = router.workCard else { return }
        workFitTask?.cancel()
        workFitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            guard
                !Task.isCancelled,
                workFitFollowsSheet,
                router.workCard?.id == work.id,
                top.layer == .work,
                // 三段式はカードが地図をほぼ占める（浮控も退いている）。枠を詰め込む意味が無い。
                detent != maxDetent(.work),
                let cardTop = cardFrame?.minY,
                abs(cardTop - (lastWorkFitCardTop ?? 0)) > Self.workRefitThreshold
            else { return }
            refitWork(work.id)
        }
    }

    /// この pt 以上カードの上縁が動いたときだけ枠を置き直す。
    private static let workRefitThreshold: CGFloat = 24

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
        withAnimation(.anitabiSpring) {
            detent = initialDetent(.home)
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
