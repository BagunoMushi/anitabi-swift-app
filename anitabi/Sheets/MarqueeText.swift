//
//  MarqueeText.swift
//  anitabi
//
//  1 行しか無い所で長い標題を**省略せずに**見せる横スクロール（マーキー）。
//
//  一段式の身份条は高さが 1 行ぶんしか無く、そこで `…` に切ると
//  「ゆるキャン△ SEASON 3」のような作品名・駅名が判別できなくなる（実機で指摘）。
//  収まるときは**一切動かさない**（静止した `Text` と完全に同じ見え方）。
//  溢れるときだけ **1 周だけ**流す：同じ文字列を 2 つ並べて左へ流し、
//  2 つ目の頭が 1 つ目の居た位置に来たところで止める（＝見た目は頭に戻って静止）。
//  ぐるぐる回し続けない（読み終わった後も動くと気が散る）し、末尾でも止めない
//  ——どちらも同指示 2026-08-10。
//
//  **レイアウトは普通の 1 行 `Text` と同じにする**のが肝：
//  流す中身は `overlay` に置いて枠の外へはみ出させ、枠自体は縮む `Text` で作る。
//  中身を直に置いて `fixedSize` すると、行の幅を全文ぶん要求してしまい、
//  隣の釦（「全部点位」・✕）を行の外へ押し出す（実機で発生）。
//
//  「視差効果を減らす」がオンのときは動かさず、従来どおり尾を省略する（HIG の要請）。
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
    /// 実高を測るためだけの不可視の複製（`compactHeaderProbe`）では流さない ——
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
