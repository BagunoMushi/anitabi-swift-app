//
//  MarqueeText.swift
//  anitabi
//
//  1 行しか無い所で長い標題を**省略せずに**見せる横スクロール。収まるときは一切動かさず、
//  溢れるときだけ 1 周流して頭へ戻った所で止める（回し続けない）。**レイアウトは普通の 1 行
//  `Text` と同じにする**のが肝で、流す中身は overlay に置いて枠の外へはみ出させる。
//

import SwiftUI

struct MarqueeText: View {

    let text: String
    let font: Font
    var color: Color = .anitabiInk
    /// 1 秒あたりに流す量（pt）。速すぎると読めず、遅すぎると止まって見える。
    var speed: CGFloat = 30
    /// 流し始めるまでの間。まず頭を読ませてから動かす。
    var startDelay: Double = 1.2

    /// 1 周目の末尾と 2 周目の頭の間隔。
    private var gap: CGFloat { SheetMetrics.scaled(28) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 実高を測るためだけの不可視の複製（`compactHeightProbe`）では流さない ——
    /// 見えない所で永久アニメーションを回し続けないため。
    @Environment(\.isMarqueeEnabled) private var isMarqueeEnabled

    /// 文字列の理想幅（＝省略しないときの幅）。
    @State private var textWidth: CGFloat = 0
    /// 行が実際にくれた幅。
    @State private var availableWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var scrolls: Bool {
        availableWidth > 0 && textWidth > availableWidth + 0.5 && !reduceMotion && isMarqueeEnabled
    }

    var body: some View {
        // 枠を作るのはこの `Text`。**`fixedSize` を付けない**＝普通の 1 行テキストと同じで
        // いくらでも縮むので、隣の釦の幅を奪わない。中身は下の overlay が描くので透明にしておく。
        Text(text)
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .leading) { scroller }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            // 幅・文字が動いている間は**流し始めない**。`task(id:)` は変化のたびに
            // 前の待ちを取り消すので、条が落ち着いてから `startDelay` 後に一度だけ始まる。
            // （拖动の途中で始めてしまうと、確定前の幅で流れて標題が枠の外へ出る＝字が消える）
            .task(id: "\(text)|\(textWidth)|\(availableWidth)") { await runMarquee() }
            .accessibilityLabel(text)
    }

    /// 実際に見える中身。枠より広くなってよい（`clipped()` が切る）。
    /// 溢れるときは同じ文字列をもう 1 つ後ろに置く —— 1 周流し終えた位置で
    /// 2 つ目が 1 つ目の居た所にぴったり来るので、止めた瞬間が「頭に戻った」画になる。
    private var scroller: some View {
        HStack(spacing: gap) {
            label
                // 理想幅はここで測る（`fixedSize` 済みなので省略前の幅が出る）。
                .background {
                    GeometryReader { proxy in
                        Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                            textWidth = $0
                        }
                    }
                }
            if scrolls {
                label
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: offset)
        .accessibilityHidden(true)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 頭出し → 少し待つ → 1 周流す。待っている間に幅か文字が変われば `task` ごと取り消される。
    private func runMarquee() async {
        // 頭出しは**アニメーションさせない**：sheet の拖动やバネの中で `offset` を動かすと、
        // 標題がその場でスライドして見える（＝一瞬消える）。
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }

        guard scrolls else { return }
        try? await Task.sleep(for: .seconds(startDelay))
        guard !Task.isCancelled else { return }

        // 1 周だけ流して止める。1 周＝「文字列 ＋ 間隔」ぶんなので、止まった位置では
        // 2 つ目の頭が枠の左端に来ている＝頭に戻って静止した画になる。
        let distance = textWidth + gap
        withAnimation(.linear(duration: distance / speed)) { offset = -distance }
    }
}

// MARK: - 流すかどうかの切り替え

private struct MarqueeEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isMarqueeEnabled: Bool {
        get { self[MarqueeEnabledKey.self] }
        set { self[MarqueeEnabledKey.self] = newValue }
    }
}
