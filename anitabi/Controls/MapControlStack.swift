//
//  MapControlStack.swift
//  anitabi
//
//  浮控列（Apple マップ同位）。実測規格は `SheetDesign.swift` の表と同じ出所
//  （2026-08-09・Maestro dump）：玻璃钮 48×48・纵列合并成一整块・距屏边 16pt。
//
//  置き場所は**右下・常駐カードの上縁**（Apple マップ実物 2026-08-10 対照）。左下の署名
//  （Apple ロゴ＋法的情報）と同じく、カードの上縁に貼り付いて拖动に追従する —— 地図の中身は
//  見ない。位置決めそのものは呼び出し側（`RootView.mapControls`）が持つ。
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

/// 浮控列本体。`mapView` が来るまで（`MapCanvas` が `onMapViewReady` を呼ぶまで）は
/// 呼び出し側が丸ごと出さない——指南針が `MKMapView` 無しには作れないため。
struct MapControlStack: View {
    let mapView: MKMapView
    let isLocationAuthorized: Bool
    @Binding var isLocationActive: Bool
    @Binding var baseStyle: MapBaseStyle
    @Binding var isPhotoLayerVisible: Bool
    var onLocationTap: () -> Void

    /// 玻璃钮 1 つぶんの辺。左下の「随机作品」釦（`MapRandomWorkButton`）も同じ値を使う——
    /// 別々に持つと片方だけ育って左右で大きさが違う釦が並ぶ。
    static let buttonSide: CGFloat = 48
    /// 2 钮の境目（Apple マップ実測：幅 28pt のヘアライン）。`overlay` で載せるので
    /// カプセルの総高 96pt には影響しない。
    private static let separatorWidth: CGFloat = 28

    var body: some View {
        VStack(spacing: 8) {
            // 方位釦は**カプセルの上**。この列はカードの上縁に下端を合わせて置くので、
            // 下に付けると「回すと現れる／北へ戻すと消える」たびにカプセルが上下に跳ねる。
            // 上に伸ばせばカプセルはカードの縁に貼り付いたまま動かない。
            MapCompassButtonRepresentable(mapView: mapView)
                .fixedSize()

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

// MARK: - 随机作品釦（左下・Apple 署名の上）

/// 「随机作品」の単独釦。意匠は右下の定位钮と**まったく同じ**（48×48 の玻璃 ＋ 中立色の図标）で、
/// 置き場所だけ左下 —— 引いた作品へ镜头が飛ぶ＝地図の操作なので、一覧の中ではなく地図の上に居る。
///
/// 冷却中（連打防止・镜头が滑り終わるまで）は図标を副色へ落とす。`.buttonStyle(.plain)` は `disabled` でも
/// 自分では淡くならないので、色は自分で持つしかない。
struct MapRandomWorkButton: View {
    var isCoolingDown: Bool
    var action: () -> Void

    var body: some View {
        GlassContainerCompat {
            Button(action: action) {
                Image(systemName: "dice")
                    .imageScale(.large)
                    .foregroundStyle(isCoolingDown ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.primary))
                    .frame(width: MapControlStack.buttonSide, height: MapControlStack.buttonSide)
                    // 定位钮と同じ理由——字形の描线だけが的にならないよう当たり判定を矩形で明示する。
                    .contentShape(.rect)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .capsuleGlass(interactive: true)
            .disabled(isCoolingDown)
            .accessibilityLabel("随机作品")
        }
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
