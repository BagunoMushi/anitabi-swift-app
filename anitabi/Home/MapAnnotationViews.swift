//
//  MapAnnotationViews.swift
//  anitabi
//
//  設計稿「地图标注体系 · stylesheet」の実装。
//  作品テーマ色は色域不可控（白に近い色も濁った色も来る）ため、
//  可読性は **背景に依存せず** 描边 + 投影で担保する。
//

import SwiftUI

// MARK: - 地標圓點（中ズーム）

struct ScenePinView: View {
    let color: Color
    var isSelected: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(
                width: isSelected ? Metrics.selectedDotSize : Metrics.dotSize,
                height: isSelected ? Metrics.selectedDotSize : Metrics.dotSize
            )
            .overlay {
                // 白に近いテーマ色は白描边と同化するので、内側に薄い灰の輪郭を足す。
                if color.needsOutlineOnLightPin {
                    Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
                }
            }
            .overlay {
                if isSelected {
                    // 選中態：品牌绿のリング。地図上で緑が出るのは選択と操作フィードバックだけ。
                    Circle().strokeBorder(Palette.brand, lineWidth: 3)
                        .padding(-3)
                }
            }
            .background {
                Circle()
                    .fill(Palette.pinStroke)
                    .padding(isSelected ? -3.5 : -Metrics.dotStroke)
            }
            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 聚合（cluster）

struct ClusterPinView: View {
    let count: Int
    let color: Color

    private var label: String {
        count >= 1000 ? "\(count / 1000)k+" : "\(count)"
    }

    var body: some View {
        Text(label)
            .font(.rounded(13, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, count >= 100 ? 7 : 0)
            .frame(minWidth: Metrics.clusterSize, minHeight: Metrics.clusterSize)
            .background(color, in: .capsule)
            .overlay {
                Capsule().strokeBorder(Palette.pinStroke, lineWidth: Metrics.dotStroke)
            }
            .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
    }
}

// MARK: - 作品聚合標注（低ズーム）

struct WorkPinView: View {
    let name: String
    let letter: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(letter)
                .font(.rounded(11, .heavy))
                .foregroundStyle(.white)
                .frame(width: Metrics.bangumiPinSize, height: Metrics.bangumiPinSize)
                .background(color, in: .circle)
                .overlay {
                    Circle().strokeBorder(Palette.pinStroke, lineWidth: Metrics.dotStroke)
                }
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)

            Text(name)
                .font(.rounded(11, .heavy))
                .lineLimit(1)
                .foregroundStyle(Palette.title)
                // 地図の上に直接載る文字なので halo で抜く（底図の明暗に依存しない）。
                .shadow(color: Palette.pinStroke, radius: 2)
                .shadow(color: Palette.pinStroke, radius: 2)
                .fixedSize()
        }
    }
}

// MARK: - 劇照圖標（高ズーム）

struct PhotoPinView: View {
    let point: ScenePoint
    let color: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 元画像は最大 512×288 しかないため拡大はしない。この 56×42 なら十分足りる。
            AsyncImage(url: point.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                color
            }
            .frame(width: Metrics.photoPin.width, height: Metrics.photoPin.height)
            .clipShape(.rect(cornerRadius: 10))

            if let episode = point.episodeBadge {
                EpisodeBadge(text: episode)
                    .padding(2)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.pinStroke, lineWidth: Metrics.dotStroke)
        }
        .shadow(color: .black.opacity(0.28), radius: 4, y: 3)
    }
}

// MARK: - 共通パーツ

struct EpisodeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.rounded(9, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.black.opacity(0.55), in: .rect(cornerRadius: 4))
    }
}

/// スクリーンショットのサムネイル。読み込めないときは作品テーマ色のグラデーションで代替する
/// （設計稿のプレースホルダーと同じ見た目になる）。
struct SceneThumbnail: View {
    let point: ScenePoint
    let color: Color
    let size: CGSize

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: point.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    LinearGradient(
                        colors: [color, color.mix(with: .black, by: 0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            // 親カードの角から余白ぶんを引いた半径が入る（同心）。
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: 8)))

            if let episode = point.episodeBadge {
                EpisodeBadge(text: episode).padding(3)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 作品カバー。取得できない場合はテーマ色 + 頭文字（設計稿と同じ表現）。
struct BangumiCover: View {
    let bangumi: BangumiLite
    let size: CGSize

    var body: some View {
        AsyncImage(url: bangumi.coverURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    bangumi.themeGradient
                    Text(bangumi.badgeLetter)
                        .font(.rounded(min(size.width * 0.38, 15), .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(ConcentricRectangle(corners: .concentric(minimum: 7)))
    }
}
