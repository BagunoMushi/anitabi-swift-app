//
//  DroppedPinSheet.swift
//  anitabi
//
//  長押しで落とした針のカード。Web 版「空白クリック」の原生化——単クリック（タップ）は
//  従来どおり選択解除に残すので、これは**長押し専用**の新しい入口になる。
//
//  地図上の針そのもの（系统赤マーカー・落下演出）は `MapCanvas.droppedPinCoordinate` の役目。
//  ここは出てきた後のカードの中身だけを持つ。
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct DroppedPinSheet: View {

    let store: AnitabiStore
    let coordinate: CLLocationCoordinate2D
    /// 現在のズーム。「在此添加地标」を z<16 で禁止する判定に使う（RootView の
    /// `router.cameraState?.zoom` をそのまま渡す）。
    let currentZoom: Double
    /// 「最近の巡礼点」行から選んだ経路。RootView 側で針を消してから密度 flyTo する。
    var onSelectPoint: (ScenePoint) -> Void
    var onClose: () -> Void

    @State private var placeName: String?
    @State private var geocodeFailed = false
    @State private var nearestPoints: [NearbyPoint] = []
    @State private var safariItem: SafariItem?

    private static let preciseAddZoom = 16.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                    // 最小档 96pt がちょうど標題行だけ見える高さ（PointCardSheet と同じ数値の理由）。
                    .padding(.top, SheetMetrics.cardHeaderTopInset)
                    .padding(.bottom, SheetMetrics.cardHeaderBottomSpacing)

                VStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                    if !nearestPoints.isEmpty {
                        nearestSection
                    }
                    actionRow
                    if currentZoom < Self.preciseAddZoom {
                        Text("放大地图后可精确添加")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, SheetMetrics.horizontalPadding)
            .padding(.bottom, 24)
        }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
        .task {
            let name = await reverseGeocode()
            placeName = name
            geocodeFailed = name == nil
        }
        .task { nearestPoints = await computeNearest() }
    }

    // MARK: 1. 頭部（座標共有 ◯・地名・座標副題・✕）

    /// 作品カード・地標カードと同じ解剖（`CardHeader`）。
    /// 反查が済むまでは標題そのものが座標なので、そのときだけ副題を伏せて同じ字の二度書きを避ける。
    private var cardHeader: some View {
        CardHeader(title: titleText, onClose: onClose) {
            ShareLink(item: shareCoordinateText) {
                CardHeaderCircleLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享坐标")
        } subtitle: {
            if titleText != coordinateText {
                Text(coordinateText)
            }
        }
    }

    /// 反查が済むまでは座標をそのまま見出しに使う（「加载中先显坐标」）。失败したら「已选位置」。
    private var titleText: String {
        if let placeName { return placeName }
        if geocodeFailed { return String(localized: "已选位置") }
        return coordinateText
    }

    private var coordinateText: String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: 2. 最近的巡礼点

    private var nearestSection: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
            SheetSectionHeader("最近的巡礼点")
            SheetListCard {
                ForEach(Array(nearestPoints.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 64 + SheetMetrics.thumbnailGap)
                    }
                    Button { onSelectPoint(item.point) } label: {
                        NearbyPointRow(store: store, item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 3. 動作排

    /// Google 导航を主（tint 填充）にする——常に押せる導線を主にし、条件付きで
    /// 禁止になり得る「在此添加地标」は次と同格の `.tertiarySystemFill` に留める。
    /// 座標の共有は頭部の丸釦へ移したので、この行は 2 枚で幅を等分する。
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                open(AnitabiWebLink.googleMaps(lat: coordinate.latitude, lng: coordinate.longitude))
            } label: {
                ActionTileLabel(systemImage: "car.fill", title: "Google 导航")
            }
            .buttonStyle(ActionTileButtonStyle(prominent: true))

            Button {
                safariItem = SafariItem(url: AnitabiWebLink.createPoint(at: coordinate))
            } label: {
                ActionTileLabel(systemImage: "mappin.and.ellipse", title: "在此添加地标")
            }
            .buttonStyle(ActionTileButtonStyle())
            .disabled(currentZoom < Self.preciseAddZoom)
        }
    }

    private var shareCoordinateText: String {
        String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    // MARK: - データ

    /// iOS 26 の `MKReverseGeocodingRequest`（`CLGeocoder` は iOS 26 で非推奨）。
    /// 失敗も空応答も等しく nil（呼び出し側は両方「已选位置」に丸める）。
    /// 電波が弱い巡礼中は応答が返らないことも普通にあるので、5 秒でタイムアウトさせて
    /// 「加载中」のまま固まらないようにする（実測でも Simulator 上で応答が返らないことがあった）。
    private func reverseGeocode() async -> String? {
        let coordinate = self.coordinate
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
                guard let items = try? await request.mapItems else { return nil }
                return items.first?.name
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// `AnitabiStore.recomputeNearby` と同じ等距長方形近似——5 万点の線形走査なので
    /// バックグラウンドで行う。落針の座標は現在地ではないので store 側の関数は使えない。
    private func computeNearest() async -> [NearbyPoint] {
        let coordinate = self.coordinate
        let points = store.points
        return await Task.detached(priority: .userInitiated) {
            let latRad = coordinate.latitude * .pi / 180
            let metersPerLat = 111_320.0
            let metersPerLng = 111_320.0 * cos(latRad)

            var scored: [(ScenePoint, Double)] = []
            scored.reserveCapacity(min(points.count, 4096))
            for point in points {
                let dy = (point.lat - coordinate.latitude) * metersPerLat
                let dx = (point.lng - coordinate.longitude) * metersPerLng
                scored.append((point, (dx * dx + dy * dy).squareRoot()))
            }
            scored.sort { $0.1 < $1.1 }
            return scored.prefix(3).map { NearbyPoint(point: $0.0, distance: $0.1) }
        }.value
    }
}
