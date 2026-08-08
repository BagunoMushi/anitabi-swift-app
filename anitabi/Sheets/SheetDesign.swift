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

/// 作品カード・地標カード共通の閉じる釦。
struct CardCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CircularGlyphLabel(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}
