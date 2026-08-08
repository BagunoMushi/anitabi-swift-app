//
//  MapControlStack.swift
//  anitabi
//
//  右上の浮控列（Apple マップ同位）。実測規格は `SheetDesign.swift` の表と同じ出所
//  （2026-08-09・Maestro dump）：玻璃钮 48×48・纵列合并成一整块・距屏边 16pt。
//
//  MKCompassButton はここでは**あえてガラス化しない**——系统の方位釦は iOS 26 で既に
//  自前の玻璃調シェルを持っており、その上に `.glassEffect` を重ねると「ガラスの上にガラス」
//  になって描画が破綻する（Liquid Glass の禁則）。同じ縦列には並べるが、union には参加させない。
//

import MapKit
import SwiftUI

/// 右上の浮控列本体。`mapView` が来るまで（`MapCanvas` が `onMapViewReady` を呼ぶまで）は
/// 呼び出し側が丸ごと出さない——指南針が `MKMapView` 無しには作れないため。
struct MapControlStack: View {
    let mapView: MKMapView
    let isLocationAuthorized: Bool
    @Binding var isLocationActive: Bool
    @Binding var baseStyle: MapBaseStyle
    @Binding var isPhotoLayerVisible: Bool
    var onLocationTap: () -> Void

    @Namespace private var glassNamespace
    private static let buttonSide: CGFloat = 48

    var body: some View {
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    locationButton
                    mapMenuButton
                }
            }
            // 系统コントロールなので独自のガラスは足さない（上のコメント参照）。
            // 幅を強制しない —— 自身の intrinsicContentSize（約 30pt）のまま、
            // 外側 VStack の既定中央寄せで 48pt 幅の列に自然に収まる。
            MapCompassButtonRepresentable(mapView: mapView)
                .fixedSize()
        }
    }

    // MARK: 定位钮

    private var locationButton: some View {
        Button(action: onLocationTap) {
            Image(systemName: isLocationActive ? "location.fill" : "location")
                .imageScale(.large)
                .foregroundStyle(isLocationActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary))
                .frame(width: Self.buttonSide, height: Self.buttonSide)
                // SF Symbol は自前の読み上げ文言（「現在地へ」等）を持っており、そのままだと
                // 下の `.accessibilityLabel` と二重に読まれる。子から隠して釦側の文言だけ残す。
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectUnion(id: "mapControls", namespace: glassNamespace)
        .accessibilityLabel(isLocationAuthorized ? "定位到我的位置" : "开启定位")
    }

    // MARK: 地图钮

    private var mapMenuButton: some View {
        Menu {
            Picker("底图", selection: $baseStyle) {
                Text("标准").tag(MapBaseStyle.standard)
                Text("卫星").tag(MapBaseStyle.hybrid)
            }
            Toggle(isOn: $isPhotoLayerVisible) {
                Label("剧照标注", systemImage: "photo.on.rectangle.angled")
            }
        } label: {
            Image(systemName: "square.2.layers.3d")
                .imageScale(.large)
                .frame(width: Self.buttonSide, height: Self.buttonSide)
                .accessibilityHidden(true)
        }
        // Menu は既定で中身を tint 色に塗るので、系统釦らしい中立色に戻す
        // （`HomeSheet` の「⋯」釦・`PointCardSheet` の「⋯」釦と同じ理由）。
        .tint(Color.primary)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectUnion(id: "mapControls", namespace: glassNamespace)
        .accessibilityLabel("地图设置")
    }
}

// MARK: - 系统方位釦

/// `MKCompassButton` の representable。回転時にだけ現れる／北へ戻すタップは
/// 系统が丸ごと持っているので、こちらは生成して繋ぐだけ。
struct MapCompassButtonRepresentable: UIViewRepresentable {
    let mapView: MKMapView

    func makeUIView(context: Context) -> MKCompassButton {
        let button = MKCompassButton(mapView: mapView)
        button.compassVisibility = .adaptive
        return button
    }

    func updateUIView(_ uiView: MKCompassButton, context: Context) {
        // `mapView` はカードの一生の間ずっと同じインスタンスなので、貼り替えは発生しない。
    }
}

// MARK: - 系统比例尺

/// `MKScaleView` の representable。ズーム操作中だけ系统が自動で出す（`.adaptive`）。
/// 左上・安全区から 16pt という配置は呼び出し側（RootView）が padding で決める。
struct MapScaleView: UIViewRepresentable {
    let mapView: MKMapView

    func makeUIView(context: Context) -> MKScaleView {
        let view = MKScaleView(mapView: mapView)
        view.scaleVisibility = .adaptive
        return view
    }

    func updateUIView(_ uiView: MKScaleView, context: Context) {}
}
