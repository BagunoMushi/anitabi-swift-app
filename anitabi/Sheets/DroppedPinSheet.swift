//
//  DroppedPinSheet.swift
//  anitabi
//
//  長押しで落とした針のカード（設計稿 1e / 2d）。タップは選択解除なので**長押し専用**の入口で、
//  三段の中身は 地名＋経緯度 → ＋動作排 → ＋最近の巡礼点 3 件。地図上の針そのもの（系统赤マーカー・
//  落下演出）は `MapCanvas.droppedPinCoordinate` の役目。
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct DroppedPinSheet: View {

    let store: AnitabiStore
    let coordinate: CLLocationCoordinate2D
    /// 現在のズーム。「在此添加地标」を z<16 で禁止する判定に使う。
    let currentZoom: Double
    /// いま何段目か。一段式では身份条より下を描かない。
    var stage: SheetStage = .medium
    /// 「最近の巡礼点」行から選んだ経路。RootView 側で針を消してから寄せる。
    var onSelectPoint: (ScenePoint) -> Void
    var onClose: () -> Void

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
                .collapsedInCompactStage(stage)
            }
            .scenePadding(.horizontal)
            .sheetScrollBottomPadding(sheetBottomInset)
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

    /// 反查が済むまでは標題そのものが座標なので、そのときだけ副題を伏せて二度書きを避ける。
    private var cardHeader: some View {
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
        // 迷你条の行高は 4 枚のカードで共通（`compactBarRow`）。
        .compactBarRow()
    }

    /// 反查が済むまでは座標をそのまま見出しに使う。失敗したら「已选位置」。
    private var titleText: String {
        if let placeName { return placeName }
        if geocodeFailed { return String(localized: "已选位置") }
        return coordinateText
    }

    private var coordinateText: String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: 2. 動作排（設計稿 2d：2 枚で等分。禁止側は白 35% ＋ 墨 35%）

    /// Google 导航を主（実心）にする —— 常に押せる導線を主にし、条件付きで禁止になり得る
    /// 「在此添加地标」は次と同格に留める。
    private var actionRow: some View {
        HStack(spacing: SheetMetrics.itemSpacing) {
            Button {
                AnitabiWebLink.openExternally(
                    AnitabiWebLink.googleMaps(lat: coordinate.latitude, lng: coordinate.longitude)
                )
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

    // MARK: - データ

    /// iOS 26 は `MKReverseGeocodingRequest`、それ未満は `CLGeocoder`。失敗も空応答も等しく nil。
    /// 電波が弱い巡礼中は応答が返らないことも普通にあるので、5 秒でタイムアウトさせる。
    private func reverseGeocode() async -> String? {
        let coordinate = self.coordinate
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if #available(iOS 26, *) {
                    guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
                    guard let items = try? await request.mapItems else { return nil }
                    return items.first?.name
                } else {
                    return await Self.legacyReverseGeocode(location)
                }
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

    /// iOS 26 未満の反查。関数自体に非推奨を印しておくと、中で `CLGeocoder` を呼んでも
    /// 警告が出ない（同じ非推奨文脈からの呼び出しは黙る）。26 が最低適配になったら消せる。
    @available(iOS, deprecated: 26.0, message: "iOS 26 以降は MKReverseGeocodingRequest を使う")
    private static func legacyReverseGeocode(_ location: CLLocation) async -> String? {
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location) else { return nil }
        return placemarks.first?.name
    }

    /// 針の周りの巡礼点 3 件。距離の上限は掛けない —— 何も無い所へ落としても
    /// 「いちばん近い点」は出したい。
    private func computeNearest() async -> [NearbyPoint] {
        await AnitabiStore.nearestPoints(to: coordinate, in: store.points, limit: 3)
    }
}
