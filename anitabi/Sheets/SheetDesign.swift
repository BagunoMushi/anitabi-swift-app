//
//  SheetDesign.swift
//  anitabi
//
//  シート共通の寸法トークンと共有部品。出所は設計稿「圣地巡礼卡片组件」（claude.ai/design）で、
//  数値は**すべて設計稿の px**（実機の pt へは `DesignScale` が換算する）。**写すのは中身だけ**
//  —— 角丸・抓手・呈现は `UISheetPresentationController` に任せ、外枠は系统の sheet のまま。
//

import SwiftUI
import UIKit

// MARK: - 档（常駐 sheet の高さ）

/// 常駐 sheet に載る 4 種類の内容それぞれの档（設計稿 t2 の 小 / 中 / 大）。**1 枚しか sheet を
/// 出さない**呈现モデルなので、この 4 組は「1 枚が内容に応じて着替える 4 着」——
/// 着替えのときは档の集合と選択中の档を必ず同じトランザクションで入れ替える。
enum SheetLayout {

    // MARK: 最小档（設計稿「一段式」）

    /// 一段式の高さは**定数で置かない** —— 各カードが身份条の実高を `compactContentHeight` で
    /// 上げてくるので、届くまでの 1 フレームだけこの見積もりを使う（定数だと Dynamic Type・
    /// 言語・抓手の厚みで必ずズレる）。身份条の組み立ては 4 枚で揃えてあるので値も 1 つ。
    static var compactContentFallback: CGFloat {
        SheetMetrics.topInset + SheetMetrics.compactRowHeight
    }

    /// 一段式は iOS 26 の**迷你条**（h ≲ 80）ゾーンに置く —— 通常の浮きカード（h ≳ 120）との間は
    /// 連続モーフで、そこに档を置くと中身が画面外へ切れる。迷你条には底部安全区が足されないので
    /// 中身の届く範囲 ≒ h。カードが報せてくる実高を**そのまま**頼み、余白を足し引きしないこと。
    static func minHeight(_ content: CGFloat) -> CGFloat {
        max(content, 1)
    }

    /// 中档・大档の比率を設計稿どおりの**見た目**にするための浮きぶん。
    static let floatingGap: CGFloat = 8

    // MARK: 中档・大档

    // 比率の出所は設計稿 t2 の各 mock が明示しているカード高さ ÷ 枠 720px
    // （首页 414・作品 400・地标 382・落针 160 / 三段式は 664・落针だけ 356）。

    /// 首页・作品の二段目を設計稿より低くする係数。設計稿のままでは地図に残る帯が狭く、
    /// 二段目でも点の散らばりが見えない。中身が足りないカードは元から `fittedHeight` で
    /// 詰まるので、これが効くのは中身がスクロールするこの 2 枚だけ。
    static let secondaryShrink: CGFloat = 0.75

    static let homeFraction = 0.575 * secondaryShrink
    static let workFraction = 0.556 * secondaryShrink
    /// 地標カードだけ設計稿のまま。このカードは二段目が上限（`hasExpandedStage`）なので、
    /// ここを削ると剧照が切れる。
    static let pointFraction = 0.531
    /// 落針カードの二段目は頭部 ＋ 動作排 ＋ 注記でぴったり。深くすると下がまるごと空く。
    static let droppedPinFraction = 0.222

    /// 三段式。**`.large` は使わない** —— 上に地図を一截残す設計なので、画面をほぼ埋める
    /// `.large` ではその余白が潰れる。
    static let largeFraction = 0.922
    /// 落針カードだけ三段目も浅い（最近点 3 行まで出せば終わり）。
    static let droppedPinLargeFraction = 0.494

    /// 比率 → 档の高さ。**`.fraction()` は使わない** —— あれの分母は画面高ではなく「`.large` の
    /// 高さ」なので、設計稿の「画面に対する比率」を入れると約 10% 縮む。
    static func height(_ fraction: CGFloat, screenHeight: CGFloat) -> CGFloat {
        fraction * screenHeight + floatingGap
    }

    static func detent(_ fraction: CGFloat, screenHeight: CGFloat) -> PresentationDetent {
        .height(height(fraction, screenHeight: screenHeight))
    }
}

/// いま何段目に居るか。档で変わるのは頭部と剧照の高さだけなので、カード側にはこの 3 値を渡して
/// `PresentationDetent` の実体は持ち込まない。
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

    /// 下スワイプで落ちきる档（ここより下へは行かない＝下スワイプでは閉じない）。
    /// `measured` はカードが `compactContentHeight` で報せてきた身份条の実高。
    func minDetent(measured: CGFloat?) -> PresentationDetent {
        .height(SheetLayout.minHeight(measured ?? SheetLayout.compactContentFallback))
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

    /// 三段式を持つか。**地標カードは持たない** —— 中身が両段式にそのまま収まるので、
    /// 三段目は下が空くだけだった（備考が長い点は両段式の中でスクロールする）。
    var hasExpandedStage: Bool { self != .point }

    /// 三段式の比率。落針カードだけ浅い。
    var maxFraction: CGFloat {
        self == .droppedPin ? SheetLayout.droppedPinLargeFraction : SheetLayout.largeFraction
    }

    /// 設計稿の比率は**上限**でしかない —— カードが `fittedContentHeight` で「中身はここまで」と
    /// 報せてきたらそこまで詰める。詰めないと比率は固定・中身は可変なので、同じカードでも
    /// 剧照や備考の有無で下の空きが 40〜300pt ばらつく。
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
    /// 設計稿の一段式に相当する範囲（＝上余白込みの身份条）に付ける。その高さが最小档になる。
    /// `fixedSize(vertical:)` が必須 —— 無いと**潰れた後の高さ**を測ってしまい、
    /// 「潰れた高さを測る → もっと低い档を作る → もっと潰れる」で固まる。
    func compactContentHeight(_ layer: SheetLayer) -> some View {
        fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CompactContentHeightKey.self, value: [layer: proxy.size.height])
                }
            }
    }

    /// 一段式の実高を測るためだけの不可視の複製に付ける（レイアウトには効かせない）。
    /// 中/大档では頭部が別の形に変わるカード（作品・地標・首页）は、一段式の複製をこれで隠して測る。
    func compactHeightProbe(_ layer: SheetLayer) -> some View {
        environment(\.isMarqueeEnabled, false)
            .compactContentHeight(layer)
            .hidden()
            .frame(height: 0, alignment: .top)
    }

    /// 一段式では身份条より下を**レイアウトからも外す**（高さ 0 に畳む）—— opacity だけで隠すと
    /// 見えないまま場所を要求し続け、足りないぶんを SwiftUI が身份条の余白から削るので、
    /// カードごとに数 pt 潰れて縦位置が食い違う。
    func collapsedInCompactStage(_ stage: SheetStage) -> some View {
        let isCompact = stage == .compact
        return frame(height: isCompact ? 0 : nil, alignment: .top)
            .clipped()
            .allowsHitTesting(!isCompact)
    }

    /// スクロールする列の末尾。sheet の中身は底部安全区を無効にしてあるので自分で足し戻す。
    func sheetScrollBottomPadding(_ inset: CGFloat) -> some View {
        padding(.bottom, SheetMetrics.scrollBottomPadding + inset)
    }

    /// 一段式の身份条。**4 枚のカードとも必ずこれを通す** —— 行高も上下の余白もここで完結するので、
    /// 迷你条の高さ・幅・浮き方・中身の位置がカードによらず同じになる。
    /// 高さは `minHeight` なので、既定の字級では 4 枚とも同値・大きな字級では一緒に伸びる。
    func compactBarRow() -> some View {
        modifier(CompactBarRow())
    }

    /// 中身の実高を報せる（スクロールする列の**丸ごと**に付ける）。`expandedDelta` は三段式で
    /// 中身が伸びるぶんで、档で変わるのはそこだけなので**1 回の測定から両方の档の実高が出る**。
    /// 一段式は頭部が別物なので何も報せない（受け手は直前の値を持ち続ける）。
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

    // MARK: 余白

    // 版面余白（内容 ↔ カードの縁）はトークンを持たず **`.scenePadding(.horizontal)`** を使う ——
    // 設計稿の 14px を換算した値と実測 0.3pt 差しか無く、系统 sheet と同じ縁になる方を採る。

    /// 迷你条の身份条の上下に置く**見た目の**余白（＝可視カードの縁から見た値）。
    /// これより大きくはできない —— 条の総高が iOS 26 の迷你条の上限（≒80。超えると通常カードへ
    /// モーフする）に当たる。可視カードとのズレは `compactBarInsets` が実測値で配る。
    static var compactBarGap: CGFloat { scaled(10) }
    /// 列の末尾の余白。設計稿のカードの `padding-bottom: 14px` と同値。
    static var scrollBottomPadding: CGFloat { scaled(14) }

    /// 系统が描く抓手の下端（可視カードの上端から）。実測 ≒10pt。
    static let systemGrabberBottom: CGFloat = 10

    /// シート上縁 → 最初のコントロール（**全カード・全档で共通**）。設計稿の規則そのまま
    /// 「抓手の下端 ＋ 8px」。設計稿 2a は首页だけ 10px だが、その 2pt で一段式の迷你条が
    /// 首页と他カードで別物の高さ（＝幅も浮き方も違う）になるので採らない。
    static var topInset: CGFloat { systemGrabberBottom + scaled(8) }

    /// 一段式（迷你条）の身份条の行高。**4 枚のカードで必ずこの値に揃える** ——
    /// 迷你条は档の高さで幅も浮き方も変わるので、行高が違うと「作品カードだけ一回り小さい」に
    /// なる。基準は設計稿 1a の検索欄で、他カードの身份条も ✕ の当たり判定ごとこの中に収まる。
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
    /// 地標カード一段式の迷你剧照。**身份条の行高ちょうど**（設計稿の 4:3 は保つ）——
    /// 行より高いとその条だけ背が伸びて、4 枚の迷你条が揃わなくなる。
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

    /// 剧照大図の高さ。設計稿 2c 两段式の 180（地標カードは两段式までなので伸びる先が無い）。
    static var mediaHeightMedium: CGFloat { shape(180) }

    // MARK: コントロール

    /// **同じ行に並ぶコントロールの背丈**（検索欄・丸釦・行末 chip）。設計稿は検索欄 40px・
    /// 丸釦 34px と別々に書いているが、並べると段違いに見えるので丸釦側に揃える。
    static var controlHeight: CGFloat { circleButtonDiameter }
    /// 検索欄の内側の水平余白。設計稿 `padding: 10px 14px` の 14。
    static var searchFieldHorizontalPadding: CGFloat { scaled(14) }
    /// 検索欄の中の「✕」。設計稿 `width/height: 18px`。
    static var searchClearDiameter: CGFloat { scaled(18) }
    /// 分段控件の内側余白。設計稿 `padding: 5px 0`。
    static var segmentedVerticalPadding: CGFloat { scaled(5) }
    /// 分段控件の溝（滑块の外側）。設計稿 `padding: 3px`。横並びのカプセル
    /// （`AnitabiCapsuleSize.rowChip`）はこれと上の和を縦余白に使って高さを揃える。
    static var segmentedTrackPadding: CGFloat { scaled(3) }
    /// カード頭部の丸釦（共有・✕・首页の ⋯）。設計稿 `34px`。**4 枚とも同じ寸法**にする。
    static var circleButtonDiameter: CGFloat { scaled(34) }

    /// 見た目 `visualSize` の部品を HIG の 44pt まで広げるときの片側の厚み。
    /// **当たり判定の算術はここ 1 か所だけ** —— `expandedHitTarget` と `alignedToVisualEdge` が
    /// 同じ値を使うので両者がずれようがない。
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

    /// 備考本文の行間（設計稿 `line-height: 1.7` に対する上乗せ）。
    static var noteLineSpacing: CGFloat { scaled(6) }
    /// 礼儀カード本文の行間（設計稿 1g の `line-height: 2` に対する上乗せ）。
    static var etiquetteLineSpacing: CGFloat { scaled(10) }

    /// 最小タップ領域（HIG）。**ここだけは設計稿ではなく HIG の絶対値**なので拡大しない。
    static let minimumHitTarget: CGFloat = 44
}

// MARK: - 字階（設計稿の px を 1:1 で持つ）

/// 設計稿の font-size / weight をそのまま持つ字階（数値は設計稿の px で実機の pt ではない）。
/// text style を直に使わないのは、設計稿の 11 段の刻みが系统の 6 段では半分表現できないため。
/// `static var` なのは、`UIFontMetrics` が呼び出し時の trait collection を読むから。
enum SheetFont {

    /// 組み上げた `Font` のキャッシュ。**必須** —— ここは行ごと・`Text` ごとに呼ばれるので、
    /// 毎回 `UIFont` と `UIFontMetrics` を作ると 300 行の一覧で 1 フレームに千個以上作ることになり、
    /// スクロールも釦のタップも目に見えて重くなる。倍率か字級が変わったら丸ごと捨てる。
    private struct FontKey: Hashable {
        var size: CGFloat
        var weight: CGFloat
        var style: String
        var monospaced: Bool
    }

    private static var cache: [FontKey: Font] = [:]
    private static var cacheFactor: CGFloat = 0
    private static var cacheCategory: UIContentSizeCategory = .unspecified

    /// 設計稿の px と weight から SF Rounded の Font を組む。
    /// `relativeTo` は Dynamic Type の伸び方を借りる text style。
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

        // 設計稿の px を機種比で拡大してから、`UIFontMetrics` で Dynamic Type に載せる。
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

/// 一段式の身份条の枠。余白は**抓手の帯を除いた残りの中心**に来るよう上下へ同じ厚みで置く。
/// **総高は実測値に依存させない**のが鉄則 —— 連動させると「余白 → 条の高さ → 档 → カードの枠 →
/// 実測値」が輪になって毎フレーム回り続ける。実測値は総高の中の上下配分にだけ使う。
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

/// sheet の中身は底部安全区を無効にしてあるので、**スクロールする列の末尾だけ**は自分で
/// その厚みを足し戻す（`sheetScrollBottomPadding`）。RootView が実測値を流す。
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

    /// 当たり判定ぶん広げた部品を**行末**に置くときに付ける（UIKit の `alignmentRectInsets` 相当）。
    /// 無いと余白に揃うのが透明な当たり判定の縁になり、見た目の縁だけ内側へ引っ込む。
    /// **部品の側に付ける**のが肝 —— 呼び出し側が負の padding を書くと寸法変更でバラバラにずれる。
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
            // 横は設計稿より詰まる（`DesignScale` 参照）。見出しは尾省略＋縮小で必ず 1 行に収め、
            // 右端の補助を押し出さない。
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
    /// 検索結果の節だけ設計稿 1b の 16px を使うので、角丸は差し替えられるようにしておく。
    var radius: CGFloat = SheetMetrics.listCardRadius
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, SheetMetrics.listCardHorizontalPadding)
        .padding(.vertical, SheetMetrics.listCardVerticalPadding)
        .anitabiPanel(radius: radius)
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
    /// 分段控件と横並びになる chip（`全部折叠` など）。字は chip と同じで、縦余白だけ
    /// 「溝 ＋ 内側」に合わせる —— こうしないと隣の分段控件より低くなる。
    case rowChip
    /// 小さい chip。設計稿 `padding:6px 12px` ＋ 11.5px/700（`继续`・外链）。
    case smallChip
    /// 一段式の行末で丸釦と並ぶ chip（作品カードの「全部点位」）。
    /// **高さは隣の丸釦と同じ** —— 余白から作ると ✕ の隣で一段低く見える。
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

/// カプセルの「面」だけを切り出したもの。釦（`AnitabiCapsuleStyle`）と、ButtonStyle を通せない
/// `Menu` のラベルの**両方**がこれを使う。
struct AnitabiCapsuleFace<Content: View>: View {
    var kind: AnitabiCapsuleKind = .secondary
    var size: AnitabiCapsuleSize = .action
    /// 行幅いっぱいに伸ばす（設計稿の「查看全部点位」など）。
    var fullWidth = false
    /// **行の高さいっぱいに伸ばす**。横並びの釦を等高にする唯一の手段 —— 行の高さはいちばん
    /// 背の高い子で決まり、これを付けた子がその高さを受け取る。高さを字から作ってはいけない：
    /// 記号は同じ字級でも行高より背が低いので、「⋯」だけ低くなる。
    var fillsRowHeight = false
    @ViewBuilder var content: Content

    /// 禁止態は設計稿 `background:rgba(255,255,255,.35); color:rgba(19,46,26,.35)`。
    @Environment(\.isEnabled) private var isEnabled

    private var font: Font { size.font(secondary: kind != .primary) }

    var body: some View {
        content
            .font(font)
            .lineLimit(1)
            // 設計稿は中国語前提の字数。日本語・英語では収まらない語（街景 → ストリートビュー）が
            // あるので、切るより縮めて全部見せる。
            .minimumScaleFactor(0.6)
            .foregroundStyle(foreground)
            .padding(.vertical, size.verticalPadding)
            // 幅いっぱいに伸びる項目に左右余白は無い（設計稿の動作排は `padding: 10px 0`）——
            // 足すといちばん狭いスロットで字が入らなくなる。
            .padding(.horizontal, fullWidth ? 0 : size.horizontalPadding)
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

/// 設計稿の動作排は等分ではない（地標カードは `flex:1.4 / 1 / 1 / 幅 44 固定`）。SwiftUI に
/// flex-grow は無いので、その比率を持つ最小の `Layout` を自前で用意する。
/// 高さは行の中でいちばん高い子に揃える。
struct WeightedRow: Layout {
    var spacing: CGFloat = SheetMetrics.scaled(8)
    /// 各子の伸び率。**0 なら固有幅のまま**（設計稿の「⋯」タイル）。
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

/// 4 枚のカード共通の閉じる釦。**必ず行の右端に置く**部品なので、見た目の縁を余白に揃える
/// 補正もこの中で完結させる（呼び出し側は何も計算しない）。
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

/// 3 枚のカードで共通の頭部。設計稿は一貫して**左寄せの標題ブロック（標題＋副題）＋
/// 右端に丸釦 2 つ（共有・✕）**で、Apple マップ式の中央寄せ標題は採らない。
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

/// 設計稿の分段控件（墨 7% の溝 ＋ 白い滑块 ＋ 影）。系统の `.pickerStyle(.segmented)` は
/// この形（完全な丸・白い滑块）に寄せられないので自作する。
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
            .fill((bangumi?.themeColor ?? fallback).anitabiThemeGradient)
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
