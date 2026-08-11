//
//  MapControlStack.swift
//  anitabi
//
//  右上の浮控列（Apple マップ同位）。実測規格は `SheetDesign.swift` の表と同じ出所
//  （2026-08-09・Maestro dump）：玻璃钮 48×48・纵列合并成一整块・距屏边 16pt。
//
//  ガラスは**塊に 1 回だけ**掛ける（48×96 のカプセル 1 枚に図标を 2 つ載せる）。
//  釦ごとに `.glassEffect(in: .circle)` を掛けて `.glassEffectUnion` で束ねる書き方は
//  破綻する——系统は「両方の円を内包する 1 つの大円」を並集として起こしてしまい、
//  白い実円が出た上に図标がその枠外へ逃げる（2026-08-09 実測・region-fix3-close.png）。
//
//  MKCompassButton はここでは**あえてガラス化しない**——系统の方位釦は iOS 26 で既に
//  自前の玻璃調シェルを持っており、その上に `.glassEffect` を重ねると「ガラスの上にガラス」
//  になって描画が破綻する（Liquid Glass の禁則）。同じ縦列には並べるが、カプセルの外に置く。
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

    private static let buttonSide: CGFloat = 48
    /// 2 钮の境目（Apple マップ実測：幅 28pt のヘアライン）。`overlay` で載せるので
    /// カプセルの総高 96pt には影響しない。
    private static let separatorWidth: CGFloat = 28

    var body: some View {
        VStack(spacing: 8) {
            GlassContainerCompat {
                VStack(spacing: 0) {
                    locationButton
                    mapMenuButton
                }
                .capsuleGlass(interactive: true)
            }
            // 区切り線は `GlassEffectContainer` の**外**に重ねる。中に入れるとガラスの
            // 素材レイヤーに巻き込まれてぼけ、実質見えなくなる（実測：RGB 差 1）。
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: Self.separatorWidth, height: 0.5)
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
                // ガラスを塊側へ移したので、釦自身には背景が無い。字形の外側も押せるように
                // 当たり判定を 48×48 の矩形で明示する（無いと図标の描线だけが的になる）。
                .contentShape(.rect)
                // SF Symbol は自前の読み上げ文言（「現在地へ」等）を持っており、そのままだと
                // 下の `.accessibilityLabel` と二重に読まれる。子から隠して釦側の文言だけ残す。
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
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
                .contentShape(.rect)
                .accessibilityHidden(true)
        }
        // Menu は既定で中身を tint 色に塗るので、系统釦らしい中立色に戻す
        // （`HomeSheet` の「⋯」釦・`PointCardSheet` の「⋯」釦と同じ理由）。
        .tint(Color.primary)
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
