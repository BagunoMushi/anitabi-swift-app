//
//  DroppedPinSheet.swift
//  anitabi
//
//  長押しで落とした針のカード。設計稿 1e / 2d をそのまま写す。Web 版「空白クリック」の
//  原生化——単クリック（タップ）は従来どおり選択解除に残すので、これは**長押し専用**の入口。
//
//  設計稿 2d の三段（この 1 枚だけ全屏档を持たない）：
//  - 一段式 = 反查した地名 ＋ 経緯度。まず針が落ちた場所が合っているか確かめる。
//  - 两段式 = ＋ 導航／在此添加地标（禁止時は理由も添える）。
//  - 三段式 = ＋ 針にいちばん近い巡礼点 3 件。
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
    /// いま何段目か。一段式では身份条より下を描かない（設計稿 2d 一段式）。
    var stage: SheetStage = .medium
    /// 「最近の巡礼点」行から選んだ経路。RootView 側で針を消してから密度 flyTo する。
    var onSelectPoint: (ScenePoint) -> Void
    var onClose: () -> Void

    /// sheet の中身は底部安全区を無効にしてあるので、列の末尾だけ自分で足し戻す。
    @Environment(\.sheetBottomInset) private var sheetBottomInset

    @State private var placeName: String?
    @State private var geocodeFailed = false
    @State private var nearestPoints: [NearbyPoint] = []
    @State private var safariItem: SafariItem?

    private static let preciseAddZoom = 16.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // この頭部は全档で同じ形なので、迷你条の枠（上下の余白込み）をそのまま
                // 中/大档でも使う —— 一段式の実高もこれ 1 つで測れる。
                cardHeader
                    .compactContentHeight(.droppedPin)

                // 一段式では身份条より下を**描かない**。sheet の中身は底部安全区の下にも
                // 描かれるので、高さを身份条ぴったりにしても次の節がホームインジケータ帯に覗く。
                // 判定は生の sheet 高さ由来（RootView）なので、拖动に即座に追従する。
                VStack(alignment: .leading, spacing: SheetMetrics.sectionSpacing) {
                    actionRow
                    if currentZoom < Self.preciseAddZoom {
                        Text("放大地图后可精确添加")
                            .font(SheetFont.meta)
                            .foregroundStyle(Color.anitabiInkTertiary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    if !nearestPoints.isEmpty {
                        nearestSection
                    }
                }
                // 一段式では中身を**レイアウトからも外す**（高さ 0 に畳む）。opacity だけで
                // 隠していた版は、見えないまま場所を要求し続ける —— sheet の高さが足りないぶんを
                // SwiftUI が身份条の余白から削るので、カードごとに 3〜10pt 潰れて
                // 「首页の検索だけ上、他の 2 枚は下」という食い違いになっていた（実測）。
                .frame(height: stage == .compact ? 0 : nil, alignment: .top)
                .clipped()
                .allowsHitTesting(stage != .compact)
            }
            .scenePadding(.horizontal)
            .padding(.bottom, SheetMetrics.scrollBottomPadding + sheetBottomInset)
        }
        .sheet(item: $safariItem) { item in SafariSheet(url: item.url) }
        .task {
            let name = await reverseGeocode()
            placeName = name
            geocodeFailed = name == nil
        }
        .task { nearestPoints = await computeNearest() }
    }

    // MARK: 1. 頭部（設計稿 2d：地名 ＋ 等幅の座標 ＋ 共有 ◯ ＋ ✕）

    /// 反查が済むまでは標題そのものが座標なので、そのときだけ副題を伏せて同じ字の二度書きを避ける。
    private var cardHeader: some View {
        // 設計稿 2d は三段すべて 16px/900 —— 落針カードだけは档で標題の字が変わらない。
        // だから最小档の実高もそのまま測れる（作品／地標カードのような複製は要らない）。
        CardHeader(title: titleText, titleFont: SheetFont.titleCompactPoint, onClose: onClose) {
            ShareLink(item: shareCoordinateText) {
                CardCircleLabel(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享坐标")
        } subtitle: {
            if titleText != coordinateText {
                Text(coordinateText)
                    .font(SheetFont.mono)
                    .foregroundStyle(Color.anitabiInkSecondary)
            }
        }
        // 迷你条の行高は 4 枚のカードで共通（`compactBarRow`）。この頭部は全档で同じ形なので、
        // 中/大档でもこの下限が効く（他カードの两段式の頭部も同じくらいの背丈になる）。
        .compactBarRow()
    }

    /// 反查が済むまでは座標をそのまま見出しに使う（「加载中先显坐标」）。失败したら「已选位置」。
    private var titleText: String {
        if let placeName { return placeName }
        if geocodeFailed { return String(localized: "已选位置") }
        return coordinateText
    }

    private var coordinateText: String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: 2. 動作排（設計稿 2d：2 枚で等分。禁止側は白 35% ＋ 墨 35%）

    /// Google 导航を主（実心）にする——常に押せる導線を主にし、条件付きで禁止になり得る
    /// 「在此添加地标」は次と同格に留める。座標の共有は頭部の丸釦。
    private var actionRow: some View {
        HStack(spacing: SheetMetrics.itemSpacing) {
            Button {
                open(AnitabiWebLink.googleMaps(lat: coordinate.latitude, lng: coordinate.longitude))
            } label: {
                Text("Google 导航")
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .primary, fullWidth: true, fillsRowHeight: true))

            Button {
                safariItem = SafariItem(url: AnitabiWebLink.createPoint(at: coordinate))
            } label: {
                Text("在此添加地标")
            }
            .buttonStyle(AnitabiCapsuleStyle(kind: .secondary, fullWidth: true, fillsRowHeight: true))
            .disabled(currentZoom < Self.preciseAddZoom)
        }
    }

    // MARK: 3. 最近的巡礼点（設計稿 2d 三段式）

    private var nearestSection: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.headerSpacing) {
            SheetSectionHeader("离这里最近的巡礼点")
            SheetListCard {
                ForEach(Array(nearestPoints.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        SheetHairline(leadingInset: NearbyPointRow.textInset)
                    }
                    Button { onSelectPoint(item.point) } label: {
                        NearbyPointRow(store: store, item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
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
