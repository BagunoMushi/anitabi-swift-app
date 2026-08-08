//
//  MapEngineHarness.swift
//  anitabi
//
//  地図エンジン単体の検証台（`-mapEngineHarness` 付きで起動したときだけ根ビューになる）。
//  sheet も導航も無い状態で、揭示阶梯・形態 morph・選択気球だけを見るためのもの。
//  **製品コードからは参照されない**（DEBUG 限定）。
//

#if DEBUG

import CoreLocation
import MapKit
import SwiftUI

struct MapEngineHarness: View {
    @State private var store = AnitabiStore()
    @State private var dataset = MapDataset.empty
    @State private var camera = MapCameraState(
        region: MapCanvas.japanOverview,
        zoom: 0,
        heading: 0
    )
    @State private var pointCount = 0
    @State private var workCount = 0

    @State private var command: MapCameraCommand?
    @State private var selectedPointID: String?
    @State private var focusedWorkID: Int?
    @State private var isPhotoLayerVisible = true
    @State private var lastEvent = "—"

    var body: some View {
        ZStack(alignment: .top) {
            MapCanvas(
                dataset: dataset,
                command: command,
                focusedWorkID: focusedWorkID,
                selectedPointID: selectedPointID,
                isPhotoLayerVisible: isPhotoLayerVisible,
                onSelectPoint: { point in
                    selectedPointID = point.id
                    lastEvent = "point \(point.displayName.isEmpty ? point.id : point.displayName)"
                },
                onSelectWork: { id in
                    focusedWorkID = id
                    lastEvent = "work \(store.name(forBangumi: id))"
                    if let coordinates = store.pointsByBangumi[id]?.map(\.coordinate) {
                        command = .fitWork(coordinates, bottomInset: 0)
                    }
                },
                onTapDimRegion: {
                    focusedWorkID = nil
                    lastEvent = "dim tap → browse"
                },
                onTapBlank: {
                    selectedPointID = nil
                    lastEvent = "blank"
                },
                onLongPress: { coordinate in
                    lastEvent = String(format: "long %.4f,%.4f", coordinate.latitude, coordinate.longitude)
                },
                onCameraIdle: { camera = $0 },
                onAnnotationsChange: { points, works in
                    pointCount = points
                    workCount = works
                }
            )
            .ignoresSafeArea()

            hud
        }
        .task {
            await store.bootstrap()
            // 詳細（名前・劇照）は点数を変えずに後からマージされるので、bootstrap 完走後にもう一度。
            reloadDataset()
        }
        .onChange(of: store.points.count) { _, _ in reloadDataset() }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "z %.2f   pts %d   works %d", camera.zoom, pointCount, workCount))
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
            Text(String(format: "c %.4f, %.4f", camera.region.center.latitude, camera.region.center.longitude))
                .font(.system(.caption2, design: .monospaced))
            Text(lastEvent)
                .font(.caption2)
                .lineLimit(1)

            HStack(spacing: 8) {
                button("−") { nudgeZoom(-1) }
                button("+") { nudgeZoom(1) }
                button("JP") { command = .region(MapCanvas.japanOverview) }
                button("TYO") { jump(lat: 35.6812, lng: 139.7671, zoom: 12) }
                // 劇照付きの地標が最も密に固まっている所（実データで数えた生駒〜奈良）。
                button("PIC") { jump(lat: 34.9100, lng: 135.8160, zoom: 17) }
                button(isPhotoLayerVisible ? "IMG" : "img") { isPhotoLayerVisible.toggle() }
                if focusedWorkID != nil {
                    button("✕W") { focusedWorkID = nil }
                }
            }
        }
        // 幅を固定しないと数値の桁でボタン位置が動き、Maestro の座標タップが外れる。
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }

    /// `version` は単調増加させること。同じ値だとエンジンが索引の建て直しを省く。
    private func reloadDataset() {
        dataset = MapDataset(store: store, version: dataset.version + 1)
    }

    private func nudgeZoom(_ delta: Double) {
        command = MapCameraCommand(
            kind: .center(camera.region.center, zoom: camera.zoom + delta),
            animated: true
        )
    }

    private func jump(lat: Double, lng: Double, zoom: Double) {
        command = MapCameraCommand(
            kind: .center(CLLocationCoordinate2D(latitude: lat, longitude: lng), zoom: zoom),
            animated: true
        )
    }
}

#endif
