//
//  MapHomeView.swift
//  anitabi
//
//  首屏。全画面の地図 + Liquid Glass の浮動控件 + 三档の底部 sheet。
//  tab bar は持たない（iOS 26 の Apple マップと同じ構え）。
//

import CoreLocation
import MapKit
import SwiftUI

struct MapHomeView: View {
    @State private var store = AnitabiStore()
    @State private var locationProvider = LocationProvider()

    @State private var cameraPosition: MapCameraPosition = .region(Self.japanOverview)
    @State private var visibleRegion: MKCoordinateRegion = MapHomeView.japanOverview
    @State private var mapHeading: Double = 0

    @State private var annotations: [MapAnnotationItem] = []
    @State private var selectedPointID: String?
    @State private var focusedBangumiID: Int?
    @State private var isPhotoLayerVisible = true

    @State private var sheetDetent: PresentationDetent = SheetDetent.half.fraction
    @State private var isSheetPresented = true
    @State private var searchText = ""

    /// 「視野内 N 部作品 · M 点」カプセルを出すか。設計稿の Tweaks に対応する切り替え。
    private let showsStatusCapsule = true

    /// 日本全体。データが無い状態でもここから始める。
    static let japanOverview = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.5, longitude: 138.5),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)
    )

    var body: some View {
        GeometryReader { proxy in
            map
                .overlay(alignment: .topLeading) { statusCapsule }
                // 操作系は画面上端ではなく **sheet の上端に貼り付く**（Apple マップと同じ）。
                // 収起档では下、半开档では中ほど、全开档では隠れる。
                .overlay(alignment: .bottomTrailing) { controls(in: proxy) }
        }
        .ignoresSafeArea(.keyboard)
            .sheet(isPresented: $isSheetPresented) {
                sheet
            }
            .task {
                // 起動時にシステムの許可ダイアログは出さない（設計稿の「无定位权限」状態）。
                // 許可済みなら黙って再開し、未許可なら sheet 側の穏やかな引導カードに任せる。
                if locationProvider.isAuthorized { locationProvider.start() }
                await store.bootstrap()
                rebuildAnnotations()
            }
            .onChange(of: locationProvider.location) { _, new in
                guard let new else { return }
                // 初回だけ現在地へ寄せる。以降はユーザーの操作を邪魔しない。
                if focusedBangumiID == nil, store.nearby.isEmpty {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: new.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                            )
                        )
                    }
                }
                guard locationProvider.shouldRecomputeNearby(for: new) else { return }
                locationProvider.markNearbyRecomputed(at: new)
                Task { await store.recomputeNearby(around: new) }
            }
            .onChange(of: store.points.count) { _, _ in
                rebuildAnnotations()
                if let location = locationProvider.location {
                    Task { await store.recomputeNearby(around: location) }
                }
            }
            .onChange(of: isPhotoLayerVisible) { _, _ in rebuildAnnotations() }
    }

    // MARK: - 地図

    private var map: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            UserAnnotation()

            ForEach(annotations) { item in
                Annotation("", coordinate: item.coordinate, anchor: .center) {
                    annotationView(item)
                }
                .annotationTitles(.hidden)
            }
        }
        // POI を全部落として、地図上で最も彩度が高いレイヤーが「作品の点」になるようにする。
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { /* 既定のコントロールは出さない。操作系は自前のガラス控件に集約する */ }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            rebuildAnnotations()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { _ in
                // Apple マップと同じ：地図に触れたら sheet は収起档へ落ちる。
                guard sheetDetent != SheetDetent.collapsed.fraction else { return }
                withAnimation { sheetDetent = SheetDetent.collapsed.fraction }
            }
        )
    }

    @ViewBuilder
    private func annotationView(_ item: MapAnnotationItem) -> some View {
        switch item {
        case .work(let id, _, let name, let letter, let color, _):
            WorkPinView(name: name, letter: letter, color: color)
                .onTapGesture { focusWork(id: id) }

        case .cluster(_, let coordinate, _, _):
            ClusterPinView(
                count: {
                    if case .cluster(_, _, let count, _) = item { return count }
                    return 0
                }(),
                color: {
                    if case .cluster(_, _, _, let color) = item { return color }
                    return Palette.brand
                }()
            )
            .onTapGesture { zoomIn(to: coordinate) }

        case .point(let point, let color):
            ScenePinView(color: color, isSelected: selectedPointID == point.id)
                .onTapGesture { select(point) }

        case .photo(let point, let color):
            PhotoPinView(point: point, color: color)
                .onTapGesture { select(point) }
        }
    }

    // MARK: - 浮動控件

    @ViewBuilder
    private func controls(in proxy: GeometryProxy) -> some View {
        // 全开档では sheet が覆うので出さない。
        if sheetDetent != SheetDetent.expanded.fraction {
            MapFloatingControls(
                mapHeading: mapHeading,
                isLocationDenied: locationProvider.isDenied,
                isPhotoLayerVisible: isPhotoLayerVisible,
                onLocate: locateMe,
                onTogglePhotoLayer: { isPhotoLayerVisible.toggle() },
                onResetNorth: resetNorth
            )
            .padding(.trailing, Metrics.controlInset)
            .padding(.bottom, controlBottomInset(in: proxy))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sheetDetent)
        }
    }

    /// sheet の上端から 12pt 上に浮かせるための下余白。
    /// detent は画面全体（safe area 込み）に対する割合なので、そこから底の safe area を引く。
    private func controlBottomInset(in proxy: GeometryProxy) -> CGFloat {
        let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let detent = SheetDetent.matching(sheetDetent) ?? .half
        return max(detent.height(inScreen: screenHeight) - proxy.safeAreaInsets.bottom + 12, 12)
    }

    @ViewBuilder
    private var statusCapsule: some View {
        if showsStatusCapsule, !annotations.isEmpty {
            MapStatusCapsule(workCount: visibleWorkCount, pointCount: visiblePointCount)
                .padding(.leading, Metrics.controlInset)
                .padding(.top, 8)
        }
    }

    // MARK: - sheet

    private var sheet: some View {
        HomeSheetView(
            store: store,
            location: locationProvider.location,
            isLocationDenied: locationProvider.isDenied,
            isLocationUndetermined: locationProvider.authorizationStatus == .notDetermined,
            detent: $sheetDetent,
            searchText: $searchText,
            onSelectPoint: { select($0, moveCamera: true) },
            onSelectBangumi: { focusWork(id: $0.id) },
            onSelectCity: moveTo(city:),
            onRequestLocation: requestLocation,
            onRandomJump: randomJump
        )
        .presentationDetents(SheetDetent.presentationSet, selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        // 角丸は指定しない。iOS 26 の sheet は画面の角と同心（concentric）になる半径を
        // 自前で持っており、そこに数字を打ち込むと中の検索場・カードとの同心性が崩れる。
        // 設計稿の 24pt はこの仕組みを知らずに書かれた値なので採用しない。
        // 背景は指定しない —— iOS 26 の sheet が持つ Liquid Glass をそのまま使う。
        // 独自の材質を被せると地図が透けなくなり、ガラスの意味が消える。
        // 半开までは地図を直接触れる。全开のときだけ sheet が地図を占有する。
        .presentationBackgroundInteraction(.enabled(upThrough: SheetDetent.half.fraction))
        .interactiveDismissDisabled()
    }

    // MARK: - 標注の再構築

    private func rebuildAnnotations() {
        guard !store.points.isEmpty else {
            annotations = []
            return
        }
        var input = MapAnnotationBuilder.Input(
            points: store.points,
            region: visibleRegion,
            color: { store.color(forBangumi: $0) },
            workName: { store.name(forBangumi: $0) },
            workLetter: { store.bangumi(id: $0)?.badgeLetter ?? "?" },
            focusedBangumiID: focusedBangumiID
        )
        var built = MapAnnotationBuilder.build(input)

        // 劇照レイヤーを畳んでいるときは圓點に落とす。
        if !isPhotoLayerVisible {
            built = built.map { item in
                if case .photo(let point, let color) = item {
                    return .point(point, color: color)
                }
                return item
            }
        }
        annotations = built
        input.points = []  // クロージャに巨大配列を抱えたままにしない
    }

    private var visiblePointCount: Int {
        annotations.reduce(0) { total, item in
            switch item {
            case .cluster(_, _, let count, _): total + count
            case .work(_, _, _, _, _, let count): total + count
            case .point, .photo: total + 1
            }
        }
    }

    private var visibleWorkCount: Int {
        var ids = Set<Int>()
        for item in annotations {
            switch item {
            case .work(let id, _, _, _, _, _): ids.insert(id)
            case .point(let p, _), .photo(let p, _): ids.insert(p.bangumiID)
            case .cluster: break
            }
        }
        // 塊しか見えていない広域では作品数を数え切れないので、点数から概算しない。
        return ids.count
    }

    // MARK: - 操作

    private func select(_ point: ScenePoint, moveCamera: Bool = false) {
        selectedPointID = point.id
        store.rememberVisit(bangumiID: point.bangumiID)

        if moveCamera {
            withAnimation(.easeInOut(duration: 0.6)) {
                sheetDetent = SheetDetent.collapsed.fraction
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: point.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                    )
                )
            }
        }
        // 地標詳細は後続 brief。ここでは選択状態と镜头だけを扱う。
    }

    private func focusWork(id: Int) {
        guard let bangumi = store.bangumi(id: id) else { return }
        store.rememberVisit(bangumiID: id)
        searchText = ""

        let coordinates = bangumi.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }
        guard let region = MKCoordinateRegion(fitting: coordinates) else { return }

        withAnimation(.easeInOut(duration: 0.6)) {
            sheetDetent = SheetDetent.collapsed.fraction
            cameraPosition = .region(region)
        }
    }

    private func zoomIn(to coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.45)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: visibleRegion.span.latitudeDelta / 3.2,
                        longitudeDelta: visibleRegion.span.longitudeDelta / 3.2
                    )
                )
            )
        }
    }

    private func moveTo(city: CityTile) {
        let span = city.radius / 111_320 * 2
        withAnimation(.easeInOut(duration: 0.6)) {
            sheetDetent = SheetDetent.collapsed.fraction
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: city.center,
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                )
            )
        }
    }

    private func randomJump() {
        // Web 版と同じ条件：地標が十分にある作品から 1 つ引く。
        let candidates = store.bangumis.filter { $0.points.count > 3 }
        guard let pick = candidates.randomElement() else { return }
        focusWork(id: pick.id)
    }

    private func locateMe() {
        guard locationProvider.isAuthorized else {
            requestLocation()
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .userLocation(fallback: .region(Self.japanOverview))
            sheetDetent = SheetDetent.collapsed.fraction
        }
    }

    private func requestLocation() {
        if locationProvider.isDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            locationProvider.requestAuthorization()
        }
    }

    private func resetNorth() {
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .region(visibleRegion)
        }
    }
}

// MARK: - 範囲フィット

extension MKCoordinateRegion {
    /// 座標群がちょうど収まる領域。外れ値対策として上下 2% を捨てる
    /// （1 点だけ遠くにある作品で全国表示になってしまうのを防ぐ）。
    init?(fitting coordinates: [CLLocationCoordinate2D], insetRatio: Double = 0.02) {
        guard !coordinates.isEmpty else { return nil }

        let lats = coordinates.map(\.latitude).sorted()
        let lngs = coordinates.map(\.longitude).sorted()
        let drop = Int(Double(coordinates.count) * insetRatio)
        let lo = min(drop, max(0, lats.count - 1))
        let hi = max(lats.count - 1 - drop, lo)

        let minLat = lats[lo], maxLat = lats[hi]
        let minLng = lngs[lo], maxLng = lngs[hi]

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.004),
            longitudeDelta: max((maxLng - minLng) * 1.4, 0.004)
        )
        self.init(center: center, span: span)
    }
}

#Preview {
    MapHomeView()
}
