//
//  SheetDesign.swift
//  anitabi
//
//  シート共通の寸法トークンと共有部品。
//
//  数値の出所は 2026-08-09 の実測 —— Maestro で Apple マップの階層を dump して frame を読み、
//  併せて SwiftUI 標準コントロールのレンダリング高さを自前ビルドで計測した値
//  （iPhone 17 Pro / iOS 26.5）。**ここ以外に寸法を書かない**のが原則で、
//  各シートは必ずこのトークンと部品を経由する。
//
//  自作規格を捨てた理由：以前の「等幅 50pt の大色面ボタン」「太めのカプセル」は
//  Apple マップの実物より chrome が約 19% 大きく、文字が約 15% 小さかった。
//  「ボタンが異様に大きい」という見え方はこの 2 つの合成なので、
//  収める側（chrome）と上げる側（文字）を同時に直す。
//

import SwiftUI

// MARK: - 寸法トークン

/// シート内で使う寸法。Ice Cubes の DesignSystem と同じく、定数はここだけに置いて数を絞る。
enum SheetMetrics {
    /// シート内容の水平余白。Apple マップの地点カードと同値。
    static let horizontalPadding: CGFloat = 15
    /// 節と節の間。
    static let sectionSpacing: CGFloat = 20
    /// 節見出し → 中身。
    static let headerSpacing: CGFloat = 10
    /// シート上縁 → 最初のコントロール。
    static let topInset: CGFloat = 15
    /// 検索欄の高さ（内文は 17pt `.body`）。右隣の丸釦も同じ辺の正方形にする。
    static let searchFieldHeight: CGFloat = 42
    /// 動作排タイルの総高（icon 上＋`.footnote` ラベル下）。
    static let actionTileHeight: CGFloat = 51
    /// 一覧行の上下余白。図＋2 行（17pt/15pt）で行高 69pt になる値。
    static let rowVerticalPadding: CGFloat = 14
    /// サムネイル → 文字。分隔線のインデントもこの値ぶん右へ寄せる。
    static let thumbnailGap: CGFloat = 12
    /// grid タイルの一辺。
    static let gridTileSide: CGFloat = 83
    /// 最小タップ領域（HIG）。見た目がこれ未満の丸釦は padding で当たりだけ広げる。
    static let minimumHitTarget: CGFloat = 44
    /// カード内の余白（グループカード・行カード共通）。
    static let cardPadding: CGFloat = 12

    // MARK: カード頭部（作品・地標・落針の 3 枚で共通）

    /// 頭部の丸釦（共有・✕）の**見た目**の直径。Apple マップの地点カードと同値。
    static let cardHeaderButtonDiameter: CGFloat = 42
    /// 見た目 42pt を当たり 44pt へ広げたぶん（片側 1pt）。
    /// 丸釦の**見た目の縁**を内容余白 15pt に合わせ直すのに使う。
    static let cardHeaderButtonHitInset: CGFloat = (minimumHitTarget - cardHeaderButtonDiameter) / 2
    /// 頭部の丸釦 → 標題。
    static let cardHeaderButtonGap: CGFloat = 8
    /// シート上縁 → 頭部の標題行。抓手と標題がぶつからないだけの息継ぎを取る
    /// （Apple マップ実測 26–30pt。`topInset` の 15pt では抓手に貼り付いて見える）。
    static let cardHeaderTopInset: CGFloat = 28
    /// 標題 → 副題。
    static let cardHeaderTitleGap: CGFloat = 3
    /// 頭部 → その下の最初の節（＝動作排）。節と節の 20pt より詰める。
    static let cardHeaderBottomSpacing: CGFloat = 15
}

extension View {
    /// 見た目を変えずに当たり判定を 44pt へ広げる（Ice Cubes の padding + contentShape 手法）。
    /// 行内に置くときは、広がったぶんを呼び出し側が負の padding で相殺する。
    func expandedHitTarget(visualSize: CGFloat) -> some View {
        let inset = max(0, (SheetMetrics.minimumHitTarget - visualSize) / 2)
        return padding(inset).contentShape(.rect)
    }
}

// MARK: - 節見出し

/// `.title3` semibold（20pt）の節見出し。右端に「更多」などの補助釦を置ける。
struct SheetSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SheetSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - 行カード

/// 行を並べる器。中身は行が自前で上下余白 14pt を持つので、器側の縦余白は詰める。
struct SheetListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, SheetMetrics.cardPadding)
        .padding(.vertical, 2)
        .background(Color(.secondarySystemGroupedBackground),
                    in: ConcentricRectangle(corners: .concentric(minimum: 16)))
    }
}

// MARK: - 動作排タイル

/// Apple マップの地点カード動作排と同じ等幅タイル（実測 総高 51pt）。
///
/// `.buttonSizing(.flexible)` ＋ VStack に任せると 65pt まで伸びてしまう（実測）ので、
/// 高さだけは `minHeight` で 51pt に固定する。`minHeight` にしてあるので
/// Dynamic Type を上げれば自然に伸びる（固定 `height` は使わない）。
struct ActionTileLabel: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// 動作排タイルの見た目と押下態。主・次は**色（style）で分ける**——寸法は変えない（HIG）。
struct ActionTileButtonStyle: ButtonStyle {
    var prominent = false
    /// `.disabled(true)` を読んで暗くする（例：DroppedPinSheet の「在此添加地标」は z<16 で禁止）。
    /// このスタイル自身は Configuration からは isEnabled が取れないため環境値を直接読む。
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(minHeight: SheetMetrics.actionTileHeight)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
            .background(
                prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)),
                in: .rect(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.4))
            .contentShape(.rect)
    }
}

// MARK: - 小さな丸釦

/// カード右上の丸釦（✕・⋯）。見た目 30pt・当たり 44pt。
/// 記号の字は px 直書きではなく `.footnote` 由来にして Dynamic Type に追従させる。
struct CircularGlyphLabel: View {
    let systemName: String
    var diameter: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: diameter, height: diameter)
            .background(Color(.tertiarySystemFill), in: .circle)
            .expandedHitTarget(visualSize: diameter)
    }
}

// MARK: - カード頭部

/// カード頭部の丸釦ラベル（見た目 42pt・当たり 44pt）。
/// 記号の字は px 直書きではなく `.body` 由来にして Dynamic Type に追従させる。
struct CardHeaderCircleLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: SheetMetrics.cardHeaderButtonDiameter,
                   height: SheetMetrics.cardHeaderButtonDiameter)
            .background(Color(.tertiarySystemFill), in: .circle)
            .expandedHitTarget(visualSize: SheetMetrics.cardHeaderButtonDiameter)
    }
}

/// 作品カード・地標カード・落針カード共通の閉じる釦（頭部の右スロット）。
struct CardCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CardHeaderCircleLabel(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}

/// 3 枚のカードで共通の頭部。Apple マップの地点カードの解剖をそのまま写す：
///
///     ┌ 15pt ─┬──────────────────────────┬─ 15pt ┐
///     │ ◯共有 │      標題（1 行・尾省略）      │  ◯✕  │
///     └───────┴──────────────────────────┴───────┘
///                     副題（中央寄せ・灰）
///
/// **標題を厳密に画面中央へ置く**ため、左右のスロット幅は必ず同じ 44pt にする
/// （左釦を持たないカードでも透明な 44pt を敷く）。`Spacer` で押し合う組み方だと
/// 標題の字数で中心がずれるので使わない。
///
/// 左釦の中身はカードごとに共有する対象が違う（作品の地図 URL／点の canonical URL／座標文字列）ので
/// 呼び出し側が `CardHeaderCircleLabel` を包んだ `ShareLink` を渡す。
struct CardHeader<Leading: View, Subtitle: View>: View {
    let title: String
    var onClose: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var subtitle: Subtitle

    var body: some View {
        VStack(spacing: SheetMetrics.cardHeaderTitleGap) {
            HStack(spacing: SheetMetrics.cardHeaderButtonGap) {
                slot { leading }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                slot { CardCloseButton(action: onClose) }
            }
            // 丸釦は当たり判定ぶん（片側 1pt）外へ膨らんでいる。見た目の縁を
            // 内容余白 15pt にきっちり合わせるため、そのぶんだけ左右を戻す。
            .padding(.horizontal, -SheetMetrics.cardHeaderButtonHitInset)

            subtitle
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// 左右どちらも同じ 44pt の枠に収める（中身が空でも幅が痩せないようにする）。
    private func slot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: SheetMetrics.minimumHitTarget, height: SheetMetrics.minimumHitTarget)
    }
}

extension CardHeader where Leading == Color {
    /// 左釦を出さないカード用。枠だけ確保して標題の中心をずらさない。
    init(title: String, onClose: @escaping () -> Void, @ViewBuilder subtitle: () -> Subtitle) {
        self.init(title: title, onClose: onClose, leading: { Color.clear }, subtitle: subtitle)
    }
}

extension CardHeader where Subtitle == EmptyView {
    /// 副題を持たないカード用。
    init(title: String, onClose: @escaping () -> Void, @ViewBuilder leading: () -> Leading) {
        self.init(title: title, onClose: onClose, leading: leading, subtitle: { EmptyView() })
    }
}
