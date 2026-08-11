//
//  SheetDesign.swift
//  anitabi
//
//  シート共通の寸法トークンと共有部品。
//
//  ============================================================================
//  出所：設計稿「圣地巡礼卡片组件」（claude.ai/design · 2026-08-09）
//  ============================================================================
//
//  ここに書いてある数値は**すべて設計稿の px**（`width: 390px` のモック上の値）で、
//  実機では `DesignScale` が「画面の短辺 / 390 × 17/14」倍して使う。
//  つまり比率だけが設計稿で、絶対値は端末幅に比例する（iPhone 17 Pro で ≒1.25 倍）。
//  設計稿の px をそのまま置いた版は、広い端末で字と部品が相対的に縮んで見えるので捨てた。
//  以前ここに置いていた「Apple マップ実測値」規格（行高 69・節見出し 20pt・動作排タイル 51pt）も
//  設計稿の比率に**置き換えてある**（拡大後の行名は 17.5pt で、実測 17pt とほぼ一致する）。
//
//  外枠だけは系统の sheet のまま（同指示：「外边框跟随现在的系统 sheet」）。
//  設計稿の「左右下 8pt 浮かせた角丸 30pt のカード」は採らず、角丸・抓手・呈现は
//  `UISheetPresentationController` に任せて、写すのは**中身**だけにしてある。
//
//  字は SF Rounded（設計稿の Zen Maru Gothic に最も近い系统書体）。`SheetFont` が
//  設計稿の px を**そのまま基準サイズ**にして `UIFontMetrics` で Dynamic Type に載せるので、
//  既定字級では設計稿の値ぴったりになる。根の `.fontDesign(.rounded)` は
//  系统が自前で組む字（Menu・ContentUnavailableView など）を揃えるためだけに残してある。
//

import SwiftUI
import UIKit

// MARK: - 档（常駐 sheet の高さ）

/// 常駐 sheet に載る 4 種類の内容それぞれの档。設計稿 t2「三段式下拉阶段」の
/// 小 / 中 / 大 をそのまま写す。
///
/// **1 枚しか sheet を出さない**呈现モデル（`RootView` 参照）なので、この 4 組は
/// 「同時に生きている 4 枚の設定」ではなく「1 枚が内容に応じて着替える 4 着」である。
/// 着替えのとき、档の集合（`detents`）と選択中の档は必ず同じトランザクションで入れ替える。
enum SheetLayout {

    // MARK: 最小档（設計稿「一段式」）

    /// 一段式の高さは**定数で置かない**。各カードが自分の身份条の実高を測って
    /// `compactContentHeight` preference で上げてくるので、届くまでの 1 フレームだけこの見積もりを使う。
    ///
    /// 定数で決め打ちしていた版は Dynamic Type・言語・系统抓手の厚みで必ずズレた。
    /// 設計稿の「一段式 ＝ 身份条がちょうど残る高さ」を守るには実測しかない。
    ///
    /// 見積もりは**4 枚とも同じ**：身份条の組み立て（上インセット ＋ 行高）を全カードで
    /// 揃えてあるので（`SheetMetrics.compactRowHeight`）、層ごとに違う値を持つ理由が無い。
    /// 既定の字級ではこの値が実測とも一致する。
    static var compactContentFallback: CGFloat {
        SheetMetrics.topInset + SheetMetrics.compactRowHeight
    }

    /// 設計稿のカードは身份条の下が **14px しかない**（`padding: 8px 14px 14px`）。
    ///
    /// iOS 26 の `.height(h)` の実体（iPhone 17 Pro / iOS 26.5 実測）：
    ///
    ///     h ≳ 120 …… 通常の浮きカード。可視高さ ＝ h ＋ 底部安全区(34)、下端は画面下 −8、
    ///                左右 8pt 内側（全体が 386/402 ≒ 0.96 倍で描かれる）。
    ///                中身の届く範囲は普通は h まで（下の 34 は home インジケータ帯）——
    ///                `.ignoresSafeArea(.container, edges: .bottom)` を**呈现修饰の内側**に
    ///                付けたときだけ下端まで広がる（RootView 参照）。
    ///     h ≲ 80  …… **迷你条**（Apple マップの収起検索条と同じ浮き玉）。左右 ≒28pt 内側・
    ///                画面下 −28 に浮き、**底部安全区は足されない**＝中身の届く範囲 ≒ h。
    ///     その間 …… 両者の連続モーフ（比率も余白も補間される）。ここに档を置くと
    ///                中身が画面の外へ切れる（実測）ので、**置かない**。
    ///
    /// 一段式は迷你条ゾーンに置く：カードが報せてくる身份条の実高（`compactBarRow` が
    /// 上下の余白まで含めて組み立てたもの）を**そのまま**頼む。
    /// ここで余白を足し引きしないこと —— 条の見た目は身份条の側だけで決まる。
    static func minHeight(_ content: CGFloat) -> CGFloat {
        max(content, 1)
    }

    /// 中档・大档の比率を設計稿どおりの**見た目**にするための浮きぶん。
    static let floatingGap: CGFloat = 8

    // MARK: 中档・大档（設計稿のモックのカード高さ ÷ 枠 720px）

    // 設計稿 t2 の各 mock は `left:8px;right:8px;bottom:8px` のカードに **height を明示**している。
    // その高さを枠（720px）で割った比率が、そのまま「その档で見せると決めた範囲」：
    //
    //     卡     两段式          三段式
    //     首页   414 → 57.5%    664 → 92.2%
    //     作品   400 → 55.6%    664 → 92.2%
    //     地标   382 → 53.1%    664 → 92.2%
    //     落针   160 → 22.2%    356 → 49.4%
    //
    // 一段式だけは height 無し（＝中身の高さ）なので、こちらも実測で作る（`minDetent`）。
    // 首页・作品の二段式だけは、この表の値をさらに `secondaryShrink` 倍して使う（下記）。

    /// 二段目を設計稿より低くする係数（同指示 2026-08-10：「二级需要缩短 20%」）。
    /// 設計稿の 414/400px は地図に残る帯が狭く、二段目でも点の散らばりが見えない。
    /// 中身が足りないカードは元から `fittedHeight` で詰まるので、これが効くのは
    /// **中身がスクロールするカード（首页・作品）だけ** —— そこが対象そのもの。
    static let secondaryShrink: CGFloat = 0.75

    static let homeFraction = 0.575 * secondaryShrink
    static let workFraction = 0.556 * secondaryShrink
    /// 地標カードだけ設計稿のまま（同指示：「剧照不要缩减」）。このカードは一段／二段しか
    /// 持たない（`hasExpandedStage`）ので二段目が上限＝ここを削ると剧照が切れる。
    static let pointFraction = 0.531
    /// 落針カードの 2 段目は設計稿でいちばん浅い（頭部 ＋ 動作排 ＋ 注記でぴったり）。
    /// ここを深くすると、中身が足りずカードの下がまるごと空く。
    static let droppedPinFraction = 0.222

    /// 三段式。**`.large` は使わない** —— 設計稿は 664/720 ＝ 92.2% で、上に地図を一截残す
    /// 設計になっている（`.large` は画面をほぼ埋めてその余白を潰してしまう）。
    static let largeFraction = 0.922
    /// 落針カードだけ 3 段目も浅い（最近点 3 行まで出せば終わり。設計稿 2d「落针卡不需要全屏」）。
    static let droppedPinLargeFraction = 0.494

    /// 比率 → 档の高さ。**`.fraction()` は使わない** —— あれの分母は「`.large` の高さ」（実測 789pt）で
    /// 画面高（874pt）ではないので、設計稿の「画面に対する比率」を入れると約 10% 縮む。
    /// 画面高から絶対値を出して `.height()` で渡す（画面より高い値は系统が `.large` まで丸める）。
    static func height(_ fraction: CGFloat, screenHeight: CGFloat) -> CGFloat {
        fraction * screenHeight + floatingGap
    }

    static func detent(_ fraction: CGFloat, screenHeight: CGFloat) -> PresentationDetent {
        .height(height(fraction, screenHeight: screenHeight))
    }
}

/// いま何段目に居るか。設計稿 t2 で「档によって中身が変わる」のは 3 か所だけ
/// （作品カードの頭部・地標カードの頭部・地標カードの剧照の高さ）なので、
/// カード側にはこの 3 値だけを渡して、`PresentationDetent` の実体は持ち込まない。
enum SheetStage {
    /// 一段式（最小档）。身份条だけ見えている状態。
    case compact
    /// 两段式（初期档）。
    case medium
    /// 三段式（最大档）。
    case expanded
}

/// 呈现スタックの「深さ」。数が大きいほど上に乗る。
/// `Comparable` なのは「上へ開いた（＝初期档で出す）」のか「下へ戻った（＝覚えていた档を復元する）」のかを
/// 深さの大小だけで判定するため。
enum SheetLayer: Int, Comparable {
    case home = 0
    case work
    case point
    case droppedPin

    /// 実測が届くまでの見積もり（4 枚とも同じ組み立てなので層で変えない）。
    var minContentFallback: CGFloat { SheetLayout.compactContentFallback }

    /// 下スワイプで落ちきる档。ここより下へは行かない（＝下スワイプでは閉じない）。
    /// `measured` はカードが `compactContentHeight` で報せてきた身份条の実高。
    /// 下スワイプで落ちきる档。`measured` はカードが報せてきた身份条の実高。
    func minDetent(measured: CGFloat?) -> PresentationDetent {
        .height(SheetLayout.minHeight(measured ?? minContentFallback))
    }

    /// 両段式の比率（設計稿のカード高 ÷ 枠 720px）。
    var initialFraction: CGFloat {
        switch self {
        case .home: SheetLayout.homeFraction
        case .work: SheetLayout.workFraction
        case .point: SheetLayout.pointFraction
        case .droppedPin: SheetLayout.droppedPinFraction
        }
    }

    /// 三段式を持つか。**地標カードは持たない**（同指示 2026-08-09：「这个页面只允许一段二段」）——
    /// 中身が両段式にそのまま収まるので、三段目は下が空くだけだった。備考が長い点だけは
    /// 両段式の中で普通にスクロールする。
    var hasExpandedStage: Bool { self != .point }

    /// 三段式の比率。落針カードだけ浅い（設計稿 2d「落针卡不需要全屏」）。
    var maxFraction: CGFloat {
        self == .droppedPin ? SheetLayout.droppedPinLargeFraction : SheetLayout.largeFraction
    }

    /// 設計稿の比率は**上限**でしかない —— カードが「中身はここまで」と報せてきたら
    /// （`fittedContentHeight`）そこまで詰める。
    ///
    /// 詰めないと、比率は固定・中身は可変なので**同じカードでも下の空きが毎回変わる**：
    /// 地標カードの実測で、備考のある点はぴったり／無い点は两段式で 40〜100pt、
    /// 三段式では 300pt 以上が空いた。中身が比率より高い（＝スクロールする）カードでは何も起きない。
    private func fittedHeight(_ fraction: CGFloat, screenHeight: CGFloat, fitted: CGFloat?) -> CGFloat {
        let design = SheetLayout.height(fraction, screenHeight: screenHeight)
        guard let fitted, fitted > 1 else { return design }
        return min(design, fitted)
    }

    func initialHeight(screenHeight: CGFloat, fitted: SheetContentHeights? = nil) -> CGFloat {
        fittedHeight(initialFraction, screenHeight: screenHeight, fitted: fitted?.medium)
    }

    func maxHeight(screenHeight: CGFloat, fitted: SheetContentHeights? = nil) -> CGFloat {
        fittedHeight(maxFraction, screenHeight: screenHeight, fitted: fitted?.expanded)
    }

    /// 新しく開いたときの档。背景（地図）を直接触れる上限でもある。
    func initialDetent(screenHeight: CGFloat, fitted: SheetContentHeights? = nil) -> PresentationDetent {
        .height(initialHeight(screenHeight: screenHeight, fitted: fitted))
    }

    func maxDetent(screenHeight: CGFloat, fitted: SheetContentHeights? = nil) -> PresentationDetent {
        .height(maxHeight(screenHeight: screenHeight, fitted: fitted))
    }

    func detents(measured: CGFloat?, fitted: SheetContentHeights?, screenHeight: CGFloat) -> Set<PresentationDetent> {
        var detents: Set<PresentationDetent> = [
            minDetent(measured: measured),
            initialDetent(screenHeight: screenHeight, fitted: fitted),
        ]
        if hasExpandedStage {
            detents.insert(maxDetent(screenHeight: screenHeight, fitted: fitted))
        }
        return detents
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - 一段式の実高の受け渡し

/// カード側が「一段式でここまで見えていれば足りる」範囲の実高を報せる通路。
/// 層ごとに分けてあるのは、隠れている層も mount されたまま同じ preference を流すため。
struct CompactContentHeightKey: PreferenceKey {
    static let defaultValue: [SheetLayer: CGFloat] = [:]

    static func reduce(value: inout [SheetLayer: CGFloat], nextValue: () -> [SheetLayer: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 两段式・三段式それぞれの「中身の実高」。設計稿の比率は上限として残し、
/// 中身がそこまで無いカードは档をこの高さまで詰める（`SheetLayer.initialHeight` / `maxHeight`）。
struct SheetContentHeights: Equatable {
    var medium: CGFloat = 0
    var expanded: CGFloat = 0
}

/// 上の値を層ごとに上げてくる通路。
struct FittedContentHeightKey: PreferenceKey {
    static let defaultValue: [SheetLayer: SheetContentHeights] = [:]

    static func reduce(value: inout [SheetLayer: SheetContentHeights], nextValue: () -> [SheetLayer: SheetContentHeights]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 設計稿の一段式に相当する範囲（＝上余白込みの身份条）に付ける。
    /// その範囲の高さがそのまま最小档の中身になる。
    ///
    /// `fixedSize(vertical:)` が必須：これが無いと**潰れた後の高さ**を測ってしまう。
    /// sheet が中身より低いと SwiftUI はまず余白を削るので、
    /// 「潰れた高さを測る → もっと低い档を作る → もっと潰れる」で固まり、
    /// 標題が抓手と同じ行まで上がってくる（実機で確認）。
    /// 縦は常に**中身が要求する高さ**を取らせ、档をそれに合わせる。
    func compactContentHeight(_ layer: SheetLayer) -> some View {
        fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CompactContentHeightKey.self, value: [layer: proxy.size.height])
                }
            }
    }

    /// 一段式の身份条。**4 枚のカードとも必ずこれを通す** —— 行高も上下の余白もここで完結するので、
    /// 迷你条の高さ・幅・浮き方・中身の位置がカードによらず同じになる。
    /// 高さは `minHeight` なので、既定の字級では 4 枚とも同値・大きな字級では一緒に伸びる。
    func compactBarRow() -> some View {
        modifier(CompactBarRow())
    }

    /// 中身の実高を報せる（スクロールする列の**丸ごと**に付ける）。
    ///
    /// `expandedDelta` は「三段式で中身がどれだけ伸びるか」（地標カードなら剧照の 180→280 ぶん）。
    /// 档で変わるのはそこだけなので、**1 回の測定から両方の档の実高が出る** —— 三段式へ伸ばす前に
    /// その高さが分かるので、伸ばした後にもう一度縮む「二段階の動き」にならない。
    ///
    /// 一段式は頭部が別物（身份条）なので測っても意味が無い。そのときは何も報せず、
    /// 受け手（RootView）は直前の値をそのまま持ち続ける。
    func fittedContentHeight(_ layer: SheetLayer, stage: SheetStage, expandedDelta: CGFloat) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FittedContentHeightKey.self,
                    value: SheetContentHeights.measured(
                        proxy.size.height,
                        at: stage,
                        expandedDelta: expandedDelta
                    ).map { [layer: $0] } ?? [:]
                )
            }
        }
    }
}

extension SheetContentHeights {
    /// いま居る档で測った実高から、两段式・三段式ぶんの高さを両方組み立てる。
    static func measured(_ height: CGFloat, at stage: SheetStage, expandedDelta: CGFloat) -> Self? {
        guard stage != .compact, height > 1 else { return nil }
        let medium = stage == .expanded ? height - expandedDelta : height
        return Self(medium: medium, expanded: medium + expandedDelta)
    }
}

// MARK: - 寸法トークン

/// シート内で使う寸法。定数はここだけに置いて数を絞る。値は全部設計稿の px そのまま。
enum SheetMetrics {

    /// 設計稿の px → 実機の pt。**間隔とコントロールの寸法**はこちら ——
    /// 機種比に加えて Dynamic Type にも追従する（`@ScaledMetric` と同じ `UIFontMetrics`。
    /// 既定の字級では設計稿どおりで、字を大きくしたときだけ余白も一緒に育つ）。
    static func scaled(_ designPixels: CGFloat) -> CGFloat { DesignScale.dynamicValue(designPixels) }

    /// 設計稿の px → 実機の pt（**機種比だけ**）。角丸・線幅・画像の寸法など、
    /// 字級で育てては困る「形」の値に使う（角丸が字と一緒に膨らむと別のデザインになる）。
    static func shape(_ designPixels: CGFloat) -> CGFloat { DesignScale.value(designPixels) }

    // MARK: 余白（設計稿 `padding: 8px 14px 14px` ＋ 抓手 `margin: 4px auto 8px/10px`）

    // 版面余白（内容 ↔ カードの縁）はトークンを持たず **`.scenePadding(.horizontal)`** を使う。
    // HIG の Layout margins（iPhone 16pt）を系统から受け取る側に寄せた（同指示 2026-08-09：
    // 「边距也换成系统标准」）。設計稿の 14px を機種比で伸ばした値（17 Pro で 15.7）とは
    // 実測 0.3pt 差しか無く、系统 sheet・Apple マップと同じ縁になる方を採る。
    /// 迷你条の身份条の上下に置く**見た目の**余白（＝可視カードの縁から見た値）。
    /// 抓手の帯（`systemGrabberBottom`）の下と、カード下端の上に、同じ厚みでこれを置く。
    ///
    /// 可視カードと SwiftUI の中身の枠のズレは**定数で持たない** —— `SheetShapeReader` が
    /// UIKit 側の `presentedView` を実測して環境値（`compactBarInsets`）で配る。
    /// これより大きくできない：条の総高が iOS 26 の迷你条の上限（≒80。超えると
    /// 通常カードへモーフする）に当たる。
    static var compactBarGap: CGFloat { scaled(10) }
    /// 列の末尾の余白。設計稿のカードの `padding-bottom: 14px` と同値
    /// （ここを自前で 24 にしていたぶん、最後の要素の下が余計に空いていた）。
    static var scrollBottomPadding: CGFloat { scaled(14) }

    /// 系统が描く抓手の下端（可視カードの上端から）。実測 ≒10pt。
    ///
    /// **可視カードの上端＝中身の上端**（実測。`SheetLayout.minHeight` のメモ参照）。
    /// 以前ここに居た「浮起ぶん 28pt」は、可視カードが frame より 28pt 下に浮くという
    /// **誤った実測**への補正で、全档の頭部の上に余計な空白を作っていたので削除した。
    static let systemGrabberBottom: CGFloat = 10

    /// シート上縁 → 最初のコントロール（**全カード・全档で共通**）。設計稿の規則そのまま：
    /// **抓手の下端 ＋ 8px**（抓手 `margin: 4px auto 8px`）。
    ///
    /// 設計稿 2a は首页だけ 10px にしているが、その 2pt のために一段式の迷你条が
    /// 首页と他カードで別物の高さになる（＝幅も浮き方も変わる）ので**採らない**。
    static var topInset: CGFloat { systemGrabberBottom + scaled(8) }

    /// 一段式（迷你条）の身份条の行高。**4 枚のカードで必ずこの値に揃える。**
    ///
    /// iOS 26 の迷你条は档の高さで**幅も浮き方も変わる**（`SheetLayout.minHeight` のメモ）ので、
    /// カードごとに行高が違うと「作品カードだけ一回り小さい」「地標カードだけ中身が下寄り」に
    /// なる（実機で指摘された）。基準は設計稿 1a の検索欄と同じ 40px ——
    /// 他カードの身份条（標題＋副題・✕ の当たり判定 44）もこの中に収まる。
    static var compactRowHeight: CGFloat { max(controlHeight, minimumHitTarget) }

    /// 節と節の間。設計稿の `margin-top: 10px`。
    static var sectionSpacing: CGFloat { scaled(10) }
    /// 節見出し → 中身。設計稿の `margin: 10px 2px 6px` の 6。
    static var headerSpacing: CGFloat { scaled(6) }
    /// 節見出しの左右インデント。設計稿の `margin: … 2px …`。
    static var headerInset: CGFloat { scaled(2) }
    /// 横並びの既定の隙間。設計稿の `gap: 8px`。
    static var itemSpacing: CGFloat { scaled(8) }

    // MARK: 角丸（設計稿 1:1 を等比換算）

    /// 一覧カード。設計稿 `border-radius: 18px`。
    static var listCardRadius: CGFloat { shape(18) }
    /// 情報カード・行カード。設計稿 `16px`。
    static var groupCardRadius: CGFloat { shape(16) }
    /// grid タイル・備考ブロック。設計稿 `14px`。
    static var tileRadius: CGFloat { shape(14) }
    /// 礼儀警示条。設計稿 `12px`。
    static var warnRadius: CGFloat { shape(12) }
    /// 剧照大図。設計稿 `18px`。
    static var mediaRadius: CGFloat { shape(18) }
    /// 画像の上の徽章。設計稿 `8px`。
    static var mediaBadgeRadius: CGFloat { shape(8) }
    /// 検索結果の都市アイコン・小さな角丸。設計稿 `10px`。
    static var smallRadius: CGFloat { shape(10) }

    // MARK: 一覧行

    /// 一覧カード内側の水平余白。設計稿 `padding: 4px 12px`。
    static var listCardHorizontalPadding: CGFloat { scaled(12) }
    static var listCardVerticalPadding: CGFloat { scaled(4) }
    /// 行の上下余白。設計稿 `padding: 9px 0`。
    static var rowVerticalPadding: CGFloat { scaled(9) }
    /// 図 → 文字。設計稿 `gap: 10px`。
    static var thumbnailGap: CGFloat { scaled(10) }
    /// 標題 → 副題（行の中）。設計稿は 2px。
    static var rowTitleGap: CGFloat { scaled(2) }

    // MARK: 図の寸法（設計稿 1:1 を等比換算）

    /// 附近・落針の剧照サムネイル。設計稿 `54×40` / 角丸 10。
    static var sceneThumbnailSize: CGSize { DesignScale.size(width: 54, height: 40) }
    static var sceneThumbnailRadius: CGFloat { shape(10) }
    /// 作品カードの点行サムネイル。設計稿 `50×38` / 角丸 9。
    static var pointThumbnailSize: CGSize { DesignScale.size(width: 50, height: 38) }
    static var pointThumbnailRadius: CGFloat { shape(9) }
    /// 地標カード一段式の迷你剧照。**身份条の行高ちょうど**（設計稿 56×42 の 4:3 は保つ）。
    /// 行より高いとその条だけ背が伸びて、4 枚の迷你条が揃わなくなる（`compactRowHeight` 参照）。角丸 10。
    static var miniThumbnailSize: CGSize {
        let height = compactRowHeight
        return CGSize(width: (height * 4 / 3).rounded(), height: height)
    }
    /// 作品ブラウズ行の封面。設計稿 `38×52` / 角丸 7。
    static var coverSize: CGSize { DesignScale.size(width: 38, height: 52) }
    /// 検索結果行の封面。設計稿 `34×46`。
    static var searchCoverSize: CGSize { DesignScale.size(width: 34, height: 46) }
    /// 「最近查看」行の封面。設計稿 `30×40`。
    static var recentCoverSize: CGSize { DesignScale.size(width: 30, height: 40) }
    /// 作品カード情報カードの封面。設計稿 `44×60` / 角丸 8。
    static var infoCoverSize: CGSize { DesignScale.size(width: 44, height: 60) }
    static var coverRadius: CGFloat { shape(7) }
    static var infoCoverRadius: CGFloat { shape(8) }

    /// 剧照大図の高さ。設計稿 2c 两段式の 180。
    /// （三段式の 280 は使わない —— 地標カードは两段式までなので、伸びる先が無い。）
    static var mediaHeightMedium: CGFloat { shape(180) }

    // MARK: コントロール

    /// **同じ行に並ぶコントロールの背丈**（検索欄・丸釦・行末 chip）。設計稿は検索欄 40px・
    /// 丸釦 34px と別々に書いているが、並べると段違いに見えるので丸釦側に揃える（実機で指摘）。
    static var controlHeight: CGFloat { circleButtonDiameter }
    /// 検索欄の高さ。行に並ぶ他のコントロールと同じ（上を参照）。
    static var searchFieldHeight: CGFloat { controlHeight }
    /// 検索欄の内側の水平余白。設計稿 `padding: 10px 14px` の 14。
    static var searchFieldHorizontalPadding: CGFloat { scaled(14) }
    /// 検索欄の中の「✕」。設計稿 `width/height: 18px`。
    static var searchClearDiameter: CGFloat { scaled(18) }
    /// 分段控件の内側余白。設計稿 `padding: 5px 0`。
    static var segmentedVerticalPadding: CGFloat { scaled(5) }
    /// 分段控件の溝（滑块の外側）。設計稿 `padding: 3px`。
    /// 横並びのカプセル（`AnitabiCapsuleSize.rowChip`）はこの 2 つの和を縦余白に使って高さを揃える。
    static var segmentedTrackPadding: CGFloat { scaled(3) }
    /// カード頭部の丸釦（共有・✕・首页の ⋯）。設計稿 `34px`。**4 枚とも同じ寸法**にする
    /// —— 首页だけ検索欄と同じ 40px にしていた頃は、一段式で並べると首页の ⋯ だけ一回り大きかった。
    static var circleButtonDiameter: CGFloat { scaled(34) }

    /// 見た目 `visualSize` の部品を HIG の 44pt まで広げるときの片側の厚み。
    /// **当たり判定に関する算術はここ 1 か所だけ**（`expandedHitTarget` と
    /// `alignedToVisualEdge` が同じ値を使うので、両者がずれようがない）。
    static func hitTargetInset(visualSize: CGFloat) -> CGFloat {
        max(0, (minimumHitTarget - visualSize) / 2)
    }
    /// 頭部の丸釦 → 標題。設計稿 `gap: 8px`。
    static var circleButtonGap: CGFloat { scaled(8) }
    /// 標題 → 副題。設計稿 2c 两段式 `margin-top: 4px`。
    static var titleSubtitleGap: CGFloat { scaled(4) }
    /// 頭部 → その下の最初の節。設計稿 2b/2c の `margin-top: 10px`。
    static var headerBottomSpacing: CGFloat { scaled(10) }
    /// 動作排末尾の「⋯」だけ幅が固定。設計稿 `width: 44px`。
    static var moreTileWidth: CGFloat { scaled(44) }
    /// 礼儀警示条・貢献者の丸。設計稿 `18px` / `22px`。
    static var warnIconDiameter: CGFloat { scaled(18) }
    static var contributorAvatarDiameter: CGFloat { scaled(22) }
    /// 作品 chip の丸いカバー。設計稿 2a `18px`、1d の点カード内は 6〜7px の色点。
    static var chipCoverDiameter: CGFloat { scaled(18) }
    /// 主題色の色点。設計稿は行内 7px・chip 内 6px。
    static var dotSize: CGFloat { scaled(7) }
    static var smallDotSize: CGFloat { scaled(6) }
    /// 空状態・定位案内の丸。設計稿 1a/1b `34px` / `44px`。
    static var guidanceIconDiameter: CGFloat { scaled(34) }
    static var emptyStateIconDiameter: CGFloat { scaled(44) }

    /// 備考本文の行間。設計稿 `line-height: 1.7` の 12.5px ＝ 21.25（自然 ≒15 → 上乗せ 6）。
    static var noteLineSpacing: CGFloat { scaled(6) }
    /// 礼儀カード本文の行間。設計稿 1g は `line-height: 2` の 13px（上乗せ 10）。
    static var etiquetteLineSpacing: CGFloat { scaled(10) }

    /// 最小タップ領域（HIG）。**ここだけは設計稿ではなく HIG の絶対値**なので拡大しない。
    static let minimumHitTarget: CGFloat = 44
}

// MARK: - 字階（設計稿の px を 1:1 で持つ）

/// 設計稿に書かれた font-size / font-weight を持つ字階。**px は `DesignScale` で等比拡大される**
/// ので、ここに書いてある数値は「設計稿の値」であって実機の pt ではない。
///
/// **なぜ text style（`.footnote` 等）を直に使わないか**：設計稿の刻みは
/// 10.5 / 11 / 11.5 / 12 / 12.5 / 13 / 13.5 / 14 / 16 / 17 / 18 の 11 段で、
/// 系统 text style の 11/12/13/15/17/20 では半分が表現できない（14 が 15 に、13.5 が 13 に丸まる）。
/// そこで `UIFontMetrics` で**設計稿の px を基準サイズとして Dynamic Type に追従させる**——
/// 既定サイズではぴったり設計稿の値、拡大時は近い text style と同じ比率で伸びる。
///
/// `static var`（`let` ではない）なのは、`UIFontMetrics` が呼び出し時の
/// trait collection を読むため —— `let` にすると初回アクセス時の字級で固まってしまう。
enum SheetFont {

    /// 設計稿の px と weight から SF Rounded の Font を組む。
    /// `relativeTo` は Dynamic Type の伸び方を借りる text style。
    /// 組み上げた `Font` の使い回し。**キャッシュ必須**：ここは行ごと・`Text` ごとに呼ばれるので、
    /// 毎回 `UIFont` と `UIFontMetrics` を作ると 300 行の一覧で 1 フレームに千個以上作ることになり、
    /// スクロールも釦のタップも目に見えて重くなる（実機で確認）。
    /// 倍率か字級が変わったら丸ごと捨てる。
    private struct FontKey: Hashable {
        var size: CGFloat
        var weight: CGFloat
        var style: String
        var monospaced: Bool
    }

    private static var cache: [FontKey: Font] = [:]
    private static var cacheFactor: CGFloat = 0
    private static var cacheCategory: UIContentSizeCategory = .unspecified

    private static func design(
        _ size: CGFloat,
        _ weight: UIFont.Weight = .regular,
        relativeTo style: UIFont.TextStyle,
        monospaced: Bool = false
    ) -> Font {
        let factor = DesignScale.factor
        let category = UITraitCollection.current.preferredContentSizeCategory
        if factor != cacheFactor || category != cacheCategory {
            cache.removeAll(keepingCapacity: true)
            cacheFactor = factor
            cacheCategory = category
        }

        let key = FontKey(size: size, weight: weight.rawValue, style: style.rawValue, monospaced: monospaced)
        if let hit = cache[key] { return hit }

        // 設計稿の px を機種に合わせて等比拡大してから（`DesignScale`）、
        // さらに `UIFontMetrics` で Dynamic Type に載せる。
        let pointSize = size * factor
        let system = UIFont.systemFont(ofSize: pointSize, weight: weight)
        let descriptor = system.fontDescriptor.withDesign(monospaced ? .monospaced : .rounded)
            ?? system.fontDescriptor
        let base = UIFont(descriptor: descriptor, size: pointSize)
        let font = Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
        cache[key] = font
        return font
    }

    // MARK: 標題

    /// 18px/900 —— 中/大档のカード標題（設計稿 2b 两段式・三段式、2c 三段式）。
    static var titleLarge: Font { design(18, .heavy, relativeTo: .title3) }
    /// 17px/900 —— 作品カード一段式の身份条（設計稿 2b 一段式）。
    static var titleCompactWork: Font { design(17, .heavy, relativeTo: .headline) }
    /// 16px/900 —— 地標／落針カード一段式の身份条（設計稿 2c/2d 一段式）。
    static var titleCompactPoint: Font { design(16, .heavy, relativeTo: .headline) }
    /// 13px/900 —— 首页の節見出し（設計稿 2a `附近的巡礼点` など）。
    static var sectionTitle: Font { design(13, .heavy, relativeTo: .footnote) }
    /// 12.5px/900 —— 作品カードの组头（設計稿 2b `江之电沿线`）。
    static var groupTitle: Font { design(12.5, .heavy, relativeTo: .footnote) }
    /// 11px/900 —— 検索結果の仕分けラベル（設計稿 1b `城市 / 作品 / 地标`）。
    static var resultsLabel: Font { design(11, .heavy, relativeTo: .caption2) }

    // MARK: 一覧行

    /// 14px/700 —— 首页・検索・落針の行名（設計稿 2a `御成町商店街入口`）。
    static var rowTitle: Font { design(14, .bold, relativeTo: .subheadline) }
    /// 13.5px/700 —— 作品カードの点行名・「最近查看」の作品名（設計稿 2b）。
    static var rowTitleDense: Font { design(13.5, .bold, relativeTo: .subheadline) }
    /// 11.5px —— 行の副行（作品名・EP・折り）。
    static var rowMeta: Font { design(11.5, relativeTo: .caption1) }
    /// 11px —— 作品カード点行の副行（設計稿 2b は 11px）。
    static var rowMetaDense: Font { design(11, relativeTo: .caption2) }
    /// 12px/700 —— 行末の距離（設計稿 `320 m`）。
    static var distance: Font { design(12, .bold, relativeTo: .caption1) }

    // MARK: 本文・meta

    /// 12px —— カード副題（設計稿 1d の `EP03 · 08:12 · 距我 1.2 km`）。
    static var cardSubtitle: Font { design(12, relativeTo: .caption1) }
    /// 11px —— 節見出しの補助（`5km 内`）・都市の点数・貢献者行。
    static var meta: Font { design(11, relativeTo: .caption2) }
    /// 10.5px —— 出典行・版権脚注（設計稿の最小字）。
    static var micro: Font { design(10.5, relativeTo: .caption2) }
    /// 12.5px —— 備考本文（設計稿 `line-height: 1.7`。行間は `SheetMetrics.noteLineSpacing`）。
    static var note: Font { design(12.5, relativeTo: .footnote) }

    // MARK: コントロール

    /// 13px/700 —— 主動作カプセル（設計稿 `📷 做对比图` / `Google 导航`）。
    static var action: Font { design(13, .bold, relativeTo: .footnote) }
    /// 12px/700 —— 次動作カプセル（設計稿 `地图` / `街景`）。
    static var actionSecondary: Font { design(12, .bold, relativeTo: .caption1) }
    /// 12px —— chip の既定（設計稿 2a の作品 chips）。
    static var chip: Font { design(12, relativeTo: .caption1) }
    /// 12px/700 —— 選中 chip・分段控件の選中側・`全部点位`。
    static var chipStrong: Font { design(12, .bold, relativeTo: .caption1) }
    /// 11.5px/700 —— `继续` / `全部展开` / 外链カプセル。
    static var chipSmall: Font { design(11.5, .bold, relativeTo: .caption1) }
    /// 14px —— 検索欄の中身と placeholder（設計稿 2a）。
    static var searchField: Font { design(14, relativeTo: .subheadline) }
    /// 14px/700 —— 検索行の「取消」（設計稿 1b）。
    static var searchCancel: Font { design(14, .bold, relativeTo: .subheadline) }
    /// 10.5px/700 —— 作品 chip（設計稿 1d/2c の `夏日回响 ›`）。
    static var workChip: Font { design(10.5, .bold, relativeTo: .caption2) }

    // MARK: 等幅（設計稿 `font-family: ui-monospace`）

    /// 15px/600 —— 行末の `›`（設計稿 `font-size:15〜16px`）。
    static var chevron: Font { design(15, .semibold, relativeTo: .subheadline) }

    /// 11.5px 等幅 —— 落針カードの経緯度。
    static var mono: Font { design(11.5, relativeTo: .caption1, monospaced: true) }
    /// 10.5px/700 等幅 —— 画像の上の `EP03 08:12` 徽章。
    static var mediaBadge: Font { design(10.5, .bold, relativeTo: .caption2, monospaced: true) }
}

/// 一段式の身份条の枠。上下の余白を「**可視カードの縁からの見た目**」で決める。
///
/// 中身の枠（SwiftUI が見ている矩形）と可視カード（系统が描く浮きカプセル）は一致しない。
/// そのズレは `SheetShapeReader` が UIKit 側の `presentedView` を実測して環境値で配る
/// （iPhone 17 Pro / iOS 26.5 実測で上 5.8pt・下 4.4pt。機種や OS で変わるので定数にしない）。
///
/// 配り方は「抓手の下」と「カード下端の上」に同じ厚み（`compactBarGap`）：
/// カードの中心に置くと抓手と行がぶつかる（迷你条は 67pt しか無く、行だけで 45pt 使う）ので、
/// **抓手の帯を除いた残りの中心**に置く。行末の丸釦がカード右端の弧とほぼ同心になる。
/// **条の総高は実測値に依存させない**のが鉄則：高さを実測に連動させると
/// 「余白 → 条の高さ → 档 → カードの枠 → 実測値 → 余白」で輪になり、
/// レイアウトが毎フレーム回り続けて CPU 100%・操作不能になる（実際に固まらせた）。
/// 実測値は**固定の総高の中で上下の配分を変える**ためだけに使う。
private struct CompactBarRow: ViewModifier {
    @Environment(\.compactBarInsets) private var insets

    func body(content: Content) -> some View {
        // 上下の見た目を揃えるための移動量。総高（＝下の 2 つの padding の和）は動かさない。
        let shift = min(
            max((insets.top - insets.bottom) / 2, -SheetMetrics.compactBarGap),
            SheetMetrics.compactBarGap
        )
        return content
            .frame(minHeight: SheetMetrics.compactRowHeight)
            .padding(.top, SheetMetrics.systemGrabberBottom + SheetMetrics.compactBarGap + shift)
            .padding(.bottom, SheetMetrics.compactBarGap - shift)
    }
}

/// 可視カードと中身の枠のズレ（`SheetShapeReader` の実測値）。
struct CompactBarInsets: Equatable {
    /// 可視カードの上端が中身の枠より下にあるぶん。
    var top: CGFloat = 0
    /// 可視カードの下端が身份条の下端より上にあるぶん。
    var bottom: CGFloat = 0
}

private struct CompactBarInsetsKey: EnvironmentKey {
    static let defaultValue = CompactBarInsets()
}

extension EnvironmentValues {
    var compactBarInsets: CompactBarInsets {
        get { self[CompactBarInsetsKey.self] }
        set { self[CompactBarInsetsKey.self] = newValue }
    }
}

// MARK: - 底部安全区の配布

/// sheet の中身は底部安全区を無効にしてある（`SheetLayout.minHeight` のコメント参照）ので、
/// **スクロールする列の末尾だけ**は自分でその厚みを足し戻す。RootView が実測値を流す。
private struct SheetBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var sheetBottomInset: CGFloat {
        get { self[SheetBottomInsetKey.self] }
        set { self[SheetBottomInsetKey.self] = newValue }
    }
}

extension View {
    /// 見た目を変えずに当たり判定を 44pt へ広げる（HIG）。
    func expandedHitTarget(visualSize: CGFloat) -> some View {
        padding(SheetMetrics.hitTargetInset(visualSize: visualSize)).contentShape(.rect)
    }

    /// 当たり判定ぶん広げた部品を**行末**に置くときに付ける。UIKit の `alignmentRectInsets`
    /// （Auto Layout は枠ではなく「見た目の矩形」で揃える）を SwiftUI で手当てするもの——
    /// これが無いと、余白に揃うのが透明な当たり判定の縁になり、見た目の縁だけ内側へ引っ込む。
    ///
    /// **部品の側に付ける**のが肝：呼び出し側が桁を数えて負の padding を書くと、
    /// 部品の寸法を変えたときに 4 枚のカードでバラバラにずれる（実際にずれていた）。
    func alignedToVisualEdge(_ edge: Edge.Set = .trailing, visualSize: CGFloat) -> some View {
        padding(edge, -SheetMetrics.hitTargetInset(visualSize: visualSize))
    }

    /// 設計稿の「白い薄膜の面」——`rgba(255,255,255,.5)` 地 ＋ `rgba(255,255,255,.85)` の 1px 縁。
    func anitabiPanel(
        radius: CGFloat,
        fill: Color = .anitabiSurface,
        stroke: Color = .anitabiSurfaceStroke
    ) -> some View {
        background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
    }
}

// MARK: - 節見出し

/// 設計稿の節見出し：13px weight 900 の墨 ＋ 右に補助（`5km 内`・「随机作品」など）。
struct SheetSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: SheetMetrics.itemSpacing) {
            // 横は設計稿より 15% 詰まる（`DesignScale` 参照）。見出しは尾省略＋わずかな縮小で
            // 必ず 1 行に収め、右端の補助（`5km 内`・「随机作品」）を押し出さない。
            Text(title)
                .font(SheetFont.sectionTitle)
                .foregroundStyle(Color.anitabiInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, SheetMetrics.headerInset)
    }
}

extension SheetSectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - 器

/// 行を並べる器。設計稿 `border-radius:18px; padding:4px 12px` の白い薄膜。
struct SheetListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, SheetMetrics.listCardHorizontalPadding)
        .padding(.vertical, SheetMetrics.listCardVerticalPadding)
        .anitabiPanel(radius: SheetMetrics.listCardRadius)
    }
}

/// 1 かたまりを収める器。設計稿の情報カード（`border-radius:16px; padding:10px`）。
struct SheetGroupCard<Content: View>: View {
    var padding: CGFloat = SheetMetrics.scaled(10)
    var radius: CGFloat = SheetMetrics.groupCardRadius
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SheetMetrics.itemSpacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .anitabiPanel(radius: radius)
    }
}

/// 行と行の間の細線。設計稿 `rgba(19,46,26,.08)` の 1px。系统 `Divider` は色が合わないので使わない。
struct SheetHairline: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.anitabiHairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

// MARK: - 釦（カプセル）

/// 設計稿のカプセル釦。主 = 深緑実心 ＋ 浅緑字、次 = 白い薄膜 ＋ 墨字、軟 = 墨 10% 地。
/// 寸法は主従で変えない（HIG）——変えるのは色だけ。
enum AnitabiCapsuleKind {
    /// 設計稿 `background:#132e1a; color:#eaffec`。
    case primary
    /// 設計稿 `background:rgba(255,255,255,.6); border:1px solid rgba(255,255,255,.9)`。
    case secondary
    /// 設計稿 `background:rgba(19,46,26,.08)`（「清除」chip など）。
    case soft
}

/// カプセルの大きさ 3 段。設計稿に出てくる余白／字級の組み合わせを 1:1 で持つ。
enum AnitabiCapsuleSize {
    /// 動作排。設計稿 `padding:10px 0` ＋ 13px/700（総高 ≒ 37）。次動作は 12px/700 に落ちるので
    /// `secondaryFont` で分ける（設計稿 2c：主 13px・次 12px）。
    case action
    /// 行内の主動作。設計稿 `padding:8px 14px` ＋ 12px/700（`全部点位`・総高 ≒ 32）。
    case inlineAction
    /// chip。設計稿 `padding:6px 10px` ＋ 12px（作品 chips・総高 ≒ 26）。
    case chip
    /// 分段控件と横並びになる chip（`全部折叠` など）。字は chip と同じ 12px のまま、
    /// 縦余白だけ「溝 3 ＋ 内側 5」に合わせる —— こうしないと隣の分段控件より 4pt 低くなる。
    case rowChip
    /// 小さい chip。設計稿 `padding:6px 12px` ＋ 11.5px/700（`继续`・外链）。
    case smallChip
    /// 一段式の行末で丸釦と並ぶ chip（作品カードの「全部点位」）。
    /// **高さは隣の丸釦と同じ**（横並びのコントロールは背丈を揃える）——
    /// 余白から高さを作ると 29pt にしかならず、38pt の ✕ の隣で一段低く見える。
    case barChip

    /// 高さを余白ではなく**寸法として**決めるサイズ。隣の部品と揃えたいときに使う。
    var fixedHeight: CGFloat? {
        self == .barChip ? SheetMetrics.controlHeight : nil
    }

    var verticalPadding: CGFloat {
        switch self {
        case .action: SheetMetrics.scaled(10)
        case .inlineAction: SheetMetrics.scaled(8)
        case .rowChip: SheetMetrics.segmentedVerticalPadding + SheetMetrics.segmentedTrackPadding
        case .chip, .smallChip: SheetMetrics.scaled(6)
        case .barChip: 0  // 高さは `fixedHeight` で決める
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .action: SheetMetrics.scaled(14)
        case .inlineAction: SheetMetrics.scaled(14)
        case .chip, .rowChip: SheetMetrics.scaled(10)
        case .smallChip, .barChip: SheetMetrics.scaled(12)
        }
    }

    func font(secondary: Bool) -> Font {
        switch self {
        case .action: secondary ? SheetFont.actionSecondary : SheetFont.action
        case .inlineAction: SheetFont.chipStrong
        case .chip, .rowChip: secondary ? SheetFont.chip : SheetFont.chipStrong
        case .smallChip, .barChip: SheetFont.chipSmall
        }
    }
}

/// カプセルの「面」だけを切り出したもの。釦（`AnitabiCapsuleStyle`）と、ButtonStyle を
/// 通せない `Menu` のラベルの**両方**がこれを使う。
struct AnitabiCapsuleFace<Content: View>: View {
    var kind: AnitabiCapsuleKind = .secondary
    var size: AnitabiCapsuleSize = .action
    /// 行幅いっぱいに伸ばす（設計稿の「查看全部点位」など）。
    var fullWidth = false
    /// **行の高さいっぱいに伸ばす**。横並びの釦を等高にするための唯一の手段：
    /// 行（`WeightedRow`／`HStack`）の高さはいちばん背の高い子で決まり、
    /// これを付けた子はその高さを受け取る（`Grid` の格子が行高を揃えるのと同じ仕組み）。
    ///
    /// 高さを字から作ろうとしてはいけない —— 設計稿は同じ動作排でも主 13px・次 12px と
    /// 字を変えており、記号（SF Symbol）は同じ字級でも行高より背が低い。
    /// 実際、この仕組みを使う前は「⋯」だけ 2pt 低かった。
    var fillsRowHeight = false
    @ViewBuilder var content: Content

    /// 禁止態は設計稿 `background:rgba(255,255,255,.35); color:rgba(19,46,26,.35)`。
    @Environment(\.isEnabled) private var isEnabled

    private var font: Font { size.font(secondary: kind != .primary) }

    var body: some View {
        content
            .font(font)
            .lineLimit(1)
            // 設計稿は中国語前提の字数で組まれている。日本語・英語では同じ枠に収まらない語
            // （街景 → ストリートビュー / Street View）があるので、切るより縮めて全部見せる。
            .minimumScaleFactor(0.6)
            .foregroundStyle(foreground)
            .padding(.vertical, size.verticalPadding)
            // 設計稿の動作排は `padding: 10px 0` ——幅いっぱいに伸びる項目に左右余白は無い。
            // 余白を足すと、いちばん狭いスロット（`flex:1`）で字が入らなくなる。
            .padding(.horizontal, fullWidth ? 0 : size.horizontalPadding)
            // 高さを寸法で決めるサイズ（`barChip`）はここで固定する。
            .frame(height: size.fixedHeight)
            .frame(
                maxWidth: fullWidth ? .infinity : nil,
                maxHeight: fillsRowHeight ? .infinity : nil
            )
            .background(background, in: .capsule)
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(Color.anitabiRaisedStroke, lineWidth: 1)
                }
            }
            .contentShape(.capsule)
    }

    private var foreground: Color {
        guard isEnabled else { return .anitabiInkFaint }
        switch kind {
        case .primary: return .anitabiOnAccent
        case .secondary, .soft: return .anitabiInk
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return isEnabled ? .anitabiAccentFill : .anitabiSoftFill
        case .secondary: return isEnabled ? .anitabiRaised : .anitabiSubtle
        case .soft: return .anitabiSoftFill
        }
    }
}

struct AnitabiCapsuleStyle: ButtonStyle {
    var kind: AnitabiCapsuleKind = .secondary
    var size: AnitabiCapsuleSize = .action
    /// 行幅いっぱいに伸ばす（設計稿の「查看全部点位」など）。
    var fullWidth = false
    /// 横並びの行に入れるときは true。行の高さに揃う（`AnitabiCapsuleFace.fillsRowHeight`）。
    var fillsRowHeight = false

    func makeBody(configuration: Configuration) -> some View {
        AnitabiCapsuleFace(
            kind: kind,
            size: size,
            fullWidth: fullWidth,
            fillsRowHeight: fillsRowHeight
        ) {
            configuration.label
        }
        .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

// MARK: - 重み付きの横並び

/// 設計稿の動作排は等分ではない —— 地標カードは `flex:1.4 / 1 / 1 / 幅 44 固定`（2c）。
/// SwiftUI に flex-grow は無いので、その比率を持つ最小の `Layout` を自前で用意する。
/// 高さは行の中でいちばん高い子に揃える（カプセルの高さが揃わないと設計稿の見え方にならない）。
struct WeightedRow: Layout {
    var spacing: CGFloat = SheetMetrics.scaled(8)
    /// 各子の伸び率。**0 なら固有幅のまま**（設計稿の「⋯」タイル＝幅 44 固定がこれ）。
    /// 要素数が子より少ない場合、足りないぶんは 1 として扱う。
    var weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let widths = resolvedWidths(total: width, subviews: subviews)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = resolvedWidths(total: bounds.width, subviews: subviews)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: widths[index], height: bounds.height)
            )
            x += widths[index] + spacing
        }
    }

    private func weight(_ index: Int) -> CGFloat {
        index < weights.count ? max(0, weights[index]) : 1
    }

    private func resolvedWidths(total: CGFloat, subviews: Subviews) -> [CGFloat] {
        var widths = [CGFloat](repeating: 0, count: subviews.count)
        var fixedTotal: CGFloat = 0
        var weightSum: CGFloat = 0

        for index in subviews.indices {
            let w = weight(index)
            if w == 0 {
                widths[index] = subviews[index].sizeThatFits(.unspecified).width
                fixedTotal += widths[index]
            } else {
                weightSum += w
            }
        }

        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let flexible = max(0, total - gaps - fixedTotal)
        guard weightSum > 0 else { return widths }
        for index in subviews.indices where weight(index) > 0 {
            widths[index] = flexible * weight(index) / weightSum
        }
        return widths
    }
}

// MARK: - 丸釦

/// カード頭部の丸釦（共有 ⤴ ・✕）。設計稿は 34pt で、共有は白い薄膜、✕ は墨 10% の地。
struct CardCircleLabel: View {
    let systemName: String
    /// ✕ 側は `soft`（墨 10%）、共有側は `raised`（白 60% ＋ 縁）。
    var kind: AnitabiCapsuleKind = .secondary

    var body: some View {
        Image(systemName: systemName)
            .font(SheetFont.action)
            .foregroundStyle(Color.anitabiInk)
            .frame(width: SheetMetrics.circleButtonDiameter, height: SheetMetrics.circleButtonDiameter)
            .background(kind == .soft ? Color.anitabiSoftFill : Color.anitabiRaised, in: .circle)
            .overlay {
                if kind == .secondary {
                    Circle().strokeBorder(Color.anitabiRaisedStroke, lineWidth: 1)
                }
            }
            .expandedHitTarget(visualSize: SheetMetrics.circleButtonDiameter)
    }
}

/// 4 枚のカード共通の閉じる釦。**必ず行の右端に置く**部品なので、
/// 見た目の縁を余白に揃える補正もこの中で完結させる（呼び出し側は何も計算しない）。
struct CardCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CardCircleLabel(systemName: "xmark", kind: .soft)
        }
        .buttonStyle(.plain)
        .alignedToVisualEdge(visualSize: SheetMetrics.circleButtonDiameter)
        .accessibilityLabel("关闭")
    }
}

// MARK: - カード頭部

/// 3 枚のカードで共通の頭部。設計稿 1c/1d/1e・2b/2c/2d の解剖をそのまま写す：
///
///     ┌──────────────────────────────┬──────┬──────┐
///     │ 標題（左寄せ・太）                │ ◯共有 │ ◯ ✕  │
///     │ 副題（chip ＋ meta・左寄せ・灰）    │      │      │
///     └──────────────────────────────┴──────┴──────┘
///
/// 以前ここに居た「標題を画面中央へ置く Apple マップ式」は設計稿に無いので捨てた。
/// 設計稿は一貫して**左寄せの標題ブロック ＋ 右端に丸釦 2 つ**。
struct CardHeader<Trailing: View, Subtitle: View>: View {
    let title: String
    /// 標題の字。設計稿はカードと档ごとに違う値を持つ（作品 18/17・地標 18/16・落針 16）ので
    /// 既定値を置かずに呼び出し側から必ず渡す。
    var titleFont: Font = SheetFont.titleLarge
    /// 一段式（最小档）では 1 行に丸める。
    var isCompact = false
    var onClose: () -> Void
    /// ✕ の左に並ぶ釦（共有 ⤴ など）。持たないカードは `EmptyView` を渡す。
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var subtitle: Subtitle

    var body: some View {
        HStack(alignment: .top, spacing: SheetMetrics.circleButtonGap) {
            VStack(alignment: .leading, spacing: SheetMetrics.titleSubtitleGap) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(Color.anitabiInk)
                    .lineLimit(isCompact ? 1 : 2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
            CardCloseButton(action: onClose)
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(
        title: String,
        titleFont: Font = SheetFont.titleLarge,
        isCompact: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder subtitle: () -> Subtitle
    ) {
        self.init(
            title: title,
            titleFont: titleFont,
            isCompact: isCompact,
            onClose: onClose,
            trailing: { EmptyView() },
            subtitle: subtitle
        )
    }
}

extension CardHeader where Subtitle == EmptyView {
    init(
        title: String,
        titleFont: Font = SheetFont.titleLarge,
        isCompact: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            titleFont: titleFont,
            isCompact: isCompact,
            onClose: onClose,
            trailing: trailing,
            subtitle: { EmptyView() }
        )
    }
}

// MARK: - 分段控件

/// 分段控件の 1 区画。タプルではなく型にしてあるのは `ForEach(id:)` に渡す識別子を明示するため。
struct AnitabiSegment<Value: Hashable>: Identifiable {
    let value: Value
    let title: LocalizedStringKey

    var id: Value { value }

    init(_ value: Value, _ title: LocalizedStringKey) {
        self.value = value
        self.title = title
    }
}

/// 設計稿の分段控件（`background:rgba(19,46,26,.07)` の溝 ＋ 白い滑块 ＋ 影）。
/// 系统の `.pickerStyle(.segmented)` はこの形（完全な丸・白い滑块・12px 字）に寄せられないので自作する。
struct AnitabiSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [AnitabiSegment<Value>]

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.anitabiSpring) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(isSelected ? SheetFont.chipStrong : SheetFont.chip)
                        .foregroundStyle(isSelected ? Color.anitabiInk : Color.anitabiInkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        // 設計稿 `padding:5px 0`。溝の 3pt と合わせて総高 ≒ 30。
                        .padding(.vertical, SheetMetrics.segmentedVerticalPadding)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.anitabiThumb)
                                    .shadow(color: .black.opacity(0.10), radius: SheetMetrics.scaled(2), y: SheetMetrics.scaled(1))
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SheetMetrics.segmentedTrackPadding)
        .background(Color.anitabiTrack, in: .capsule)
    }
}

// MARK: - 徽章

/// 画像の上に重ねる EP／タイムコード。設計稿 `rgba(19,46,26,.85)` 地 ＋ `#D4FFD5` の等幅字。
struct MediaBadge: View {
    let text: String
    var radius: CGFloat = SheetMetrics.mediaBadgeRadius

    var body: some View {
        Text(text)
            .font(SheetFont.mediaBadge)
            .foregroundStyle(Color.anitabiMediaBadgeText)
            .padding(.horizontal, SheetMetrics.scaled(8))
            .padding(.vertical, SheetMetrics.scaled(3))
            .background(Color.anitabiMediaBadge, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

/// 点行の「注意礼仪」徽章。設計稿 `rgba(217,164,65,.3)` 地 ＋ `#6b4a00` の 11px bold・角丸 4。
struct EtiquetteBadge: View {
    var body: some View {
        Text("注意礼仪")
            .font(SheetFont.meta.weight(.semibold))
            .foregroundStyle(Color.anitabiBadgeWarnInk)
            .padding(.horizontal, SheetMetrics.scaled(4))
            .padding(.vertical, SheetMetrics.scaled(1))
            .background(Color.anitabiBadgeWarnFill, in: .rect(cornerRadius: SheetMetrics.scaled(4), style: .continuous))
    }
}

/// 地標カードの礼儀警示条。設計稿 1d/2c：琥珀の地 ＋ 縁 ＋ 18pt の丸い `!` ＋ 右端に `›`。
struct EtiquetteBar: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SheetMetrics.itemSpacing) {
                Text(verbatim: "!")
                    .font(SheetFont.meta.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: SheetMetrics.warnIconDiameter, height: SheetMetrics.warnIconDiameter)
                    .background(Color.anitabiWarnIcon, in: .circle)
                Text("学校周边，请注意巡礼礼仪")
                    .font(SheetFont.chipSmall)
                    .foregroundStyle(Color.anitabiWarnInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(SheetFont.meta)
                    .foregroundStyle(Color.anitabiWarnInk.opacity(0.7))
            }
            .padding(.horizontal, SheetMetrics.scaled(10))
            .padding(.vertical, SheetMetrics.scaled(7))
            .background(Color.anitabiWarnFill, in: .rect(cornerRadius: SheetMetrics.warnRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SheetMetrics.warnRadius, style: .continuous)
                    .strokeBorder(Color.anitabiWarnStroke, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 行末の `›`。設計稿 `font-size:15〜16px; color:rgba(19,46,26,.4)`。
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(SheetFont.chevron)
            .foregroundStyle(Color.anitabiInkFaint)
    }
}

// MARK: - 図

/// 剧照サムネイル。無い／読み込み中は設計稿の斜線プレースホルダに相当する薄い墨の地。
struct SceneThumbnail: View {
    let url: URL?
    var size: CGSize = SheetMetrics.sceneThumbnailSize
    var radius: CGFloat = SheetMetrics.sceneThumbnailRadius
    /// 剧照が無いことを主題色で示す行（作品カードの点行）だけ渡す。
    var placeholder: LinearGradient?
    /// 既定は「滚动で見えた行だけ読む」。ScrollView の外に置く時だけ `.appearance`。
    var trigger: RemoteImageTrigger = .scrollVisibility

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(placeholder.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.anitabiMediaPlaceholder))
            .overlay {
                if let url {
                    RemoteImage(url: url, trigger: trigger) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(systemName: "photo")
                        .font(SheetFont.meta)
                        .foregroundStyle(Color.anitabiInkFaint)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

/// 作品カバー。無ければテーマ色グラデーションのまま（**文字は置かない**——硬約束）。
struct CoverThumbnail: View {
    let bangumi: BangumiLite
    var size: CGSize = SheetMetrics.coverSize
    var radius: CGFloat = SheetMetrics.coverRadius
    var trigger: RemoteImageTrigger = .scrollVisibility

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(bangumi.themeGradient)
            .overlay {
                if let url = bangumi.coverURL {
                    RemoteImage(url: url, trigger: trigger) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

/// 主題色の小さな色点。設計稿は 7〜8px。近白は内側に濃い描边（硬約束）。
struct ThemeDot: View {
    let color: Color
    var size: CGFloat = SheetMetrics.dotSize

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if UIColor(color).needsDarkInnerOutline {
                    Circle().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
                }
            }
    }
}

/// 作品 chip の丸いカバー。設計稿 1d の作品 chip・2a の chips で使う 16〜18pt。
struct WorkChipCover: View {
    let bangumi: BangumiLite?
    let fallback: Color
    var diameter: CGFloat = SheetMetrics.chipCoverDiameter
    var trigger: RemoteImageTrigger = .scrollVisibility

    var body: some View {
        Circle()
            .fill(bangumi?.themeGradient
                  ?? LinearGradient(colors: [fallback], startPoint: .top, endPoint: .bottom))
            .overlay {
                if let url = bangumi?.coverURL {
                    RemoteImage(url: url, trigger: trigger) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(.circle)
    }
}

// MARK: - 共通バネ

extension Animation {
    /// spec 全体で使う唯一のバネ設定。sheet 档・検索行の切り替えなど全アニメがこれに揃う。
    static let anitabiSpring = Animation.spring(response: 0.35, dampingFraction: 0.85)
}
