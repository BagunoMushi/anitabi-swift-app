//
//  HomeSheetRows.swift
//  anitabi
//
//  sheet の中に並ぶ部品。カード・行・タイルは全て実体（不透明）で、
//  ガラスは sheet の chrome 側だけが持つ。
//

import CoreLocation
import SwiftUI

// MARK: - 段標題

struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.homeSection)
            .foregroundStyle(Palette.sectionHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - カード土台

/// sheet の中身をまとめる器。**ガラスにはしない** ——
/// Liquid Glass はナビゲーション層専用で、リストやカードなどの内容には使わない。
/// ガラスはガラスをサンプリングできないので、ガラスの sheet の上に更にガラスを敷くと破綻する。
/// Apple マップの sheet 内カードも実体（不透明）で、これに倣う。
///
/// 角丸は数値ではなく `ConcentricRectangle`。sheet の角半径から左右の余白ぶんを引いた値が
/// 自動で入るので、sheet の角とカードの角の曲率が揃う（＝同心）。
struct HomeCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Palette.card, in: ConcentricRectangle(corners: .concentric(minimum: 16)))
    }
}

// MARK: - 上下文卡（继续上次）

struct ContinueCard: View {
    let bangumi: BangumiLite
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BangumiCover(bangumi: bangumi, size: CGSize(width: 40, height: 54))

                VStack(alignment: .leading, spacing: 1) {
                    Text("继续上次")
                        .font(.rounded(11.5, .bold))
                        .foregroundStyle(Palette.secondary)
                    Text(bangumi.displayName)
                        .font(.rounded(15, .heavy))
                        .foregroundStyle(Palette.title)
                        .lineLimit(1)
                    Text("\(bangumi.points.count) 个点位")
                        .font(.homeRowSubtitle)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Chevron()
            }
            .padding(Metrics.rowInset)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 附近の行

struct NearbyRow: View {
    let item: NearbyPoint
    let color: Color
    let workName: String
    let showsTrailingDistance: Bool
    let thumbSize: CGSize

    var body: some View {
        HStack(spacing: 12) {
            SceneThumbnail(point: item.point, color: color, size: thumbSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.point.displayName.isEmpty ? workName : item.point.displayName)
                    .font(.homeRowTitle)
                    .foregroundStyle(Palette.title)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(subtitle)
                        .font(.homeRowSubtitle)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsTrailingDistance {
                Text(DistanceFormatter.string(meters: item.distance))
                    .font(.rounded(12, .bold))
                    .foregroundStyle(Palette.quaternary)
            }
        }
        .padding(Metrics.rowInset)
        .contentShape(.rect)
    }

    private var subtitle: String {
        let work = workName.isEmpty ? "" : "《\(workName)》"
        return showsTrailingDistance
            ? work
            : "\(work) · \(DistanceFormatter.string(meters: item.distance))"
    }
}

// MARK: - 快捷入口

struct QuickAction: Identifiable {
    let id: String
    let systemImage: String
    let title: LocalizedStringKey
    let action: () -> Void
}

struct QuickActionsRow: View {
    let actions: [QuickAction]

    var body: some View {
        HStack(spacing: 22) {
            ForEach(actions) { item in
                Button(action: item.action) {
                    VStack(spacing: 5) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.brand)
                            .frame(width: Metrics.quickActionSize, height: Metrics.quickActionSize)
                            .background(Palette.brand.opacity(0.12), in: .circle)
                        Text(item.title)
                            .font(.rounded(11, .bold))
                            .foregroundStyle(Palette.sectionHeader)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 都市タイル

struct CityTileView: View {
    let city: CityTile
    /// 並び順。代表写真が入るまでは色で見分けるので、隣り合うタイルの色が被らないようにする。
    let index: Int
    let action: () -> Void

    /// 設計稿のタイル配色。写真素材が入ったらこの下に敷く土台になる。
    private static let gradients: [(UInt32, UInt32)] = [
        (0x7D8FA8, 0x55647C),
        (0xA8837D, 0x7C5A55),
        (0x7DA895, 0x557C6B),
        (0xA89B7D, 0x7C7055),
    ]

    var body: some View {
        let tint = Self.gradients[index % Self.gradients.count]

        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(hex: tint.0), Color(hex: tint.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [.black.opacity(0.66), .black.opacity(0.05)],
                    startPoint: .bottom,
                    endPoint: .top
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(city.name)
                        .font(.rounded(14, .heavy))
                        .foregroundStyle(.white)
                    Text("\(city.pointCount) 个点")
                        .font(.rounded(10.5, .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .padding(.leading, 13)
                .padding(.bottom, 6)
            }
            .frame(height: Metrics.cityTileHeight)
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 作品の行

struct WorkRow: View {
    let bangumi: BangumiLite
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BangumiCover(bangumi: bangumi, size: Metrics.coverSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bangumi.displayName)
                        .font(.rounded(14, .heavy))
                        .foregroundStyle(Palette.title)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.rounded(11.5, .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Chevron()
            }
            .padding(Metrics.rowInset)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        [bangumi.cat, bangumi.city, "\(bangumi.points.count) 个点"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - 引導カード

/// 定位が無いときに「附近」の代わりに出す。システムダイアログをいきなり出さない。
struct LocationPromptCard: View {
    let isDenied: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.brand)
                .frame(width: 38, height: 38)
                .background(Palette.brand.opacity(0.1), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text("开启定位，看看身边的巡礼点")
                    .font(.homeRowTitle)
                    .foregroundStyle(Palette.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("仅在使用期间 · 随时可关")
                    .font(.rounded(11.5, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Text(isDenied ? "去设置" : "去开启")
                    .font(.rounded(13, .heavy))
                    .foregroundStyle(Palette.brand)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Palette.brand.opacity(0.1), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}

/// 現在地の周りに点が無いときの空状態。
struct NoNearbyCard: View {
    let nearest: NearbyPoint
    let placeName: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 看板娘（朝日礼）のイラスト枠。素材が入るまでは記号で代替する。
            Image(systemName: "map")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.quaternary)
                .frame(width: 56, height: 56)
                .overlay {
                    Circle().strokeBorder(
                        Palette.quaternary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 4])
                    )
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("这附近还没有巡礼点")
                    .font(.homeRowTitle)
                    .foregroundStyle(Palette.title)
                Text("最近的在 \(placeName) · 约 \(DistanceFormatter.string(meters: nearest.distance))")
                    .font(.rounded(11.5, .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Text("带我去")
                    .font(.rounded(13, .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Palette.brand, in: .capsule)
                    .shadow(color: Palette.brand.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }
}

// MARK: - 小物

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.title.opacity(0.3))
    }
}

/// カード内の行間に敷く 0.5pt の分隔線（先頭はサムネイル幅ぶん字下げ）。
struct RowSeparator: View {
    var leading: CGFloat

    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .padding(.trailing, 12)
    }
}
