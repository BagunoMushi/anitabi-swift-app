//
//  WorkMarkerView.swift
//  anitabi
//
//  作品標（z4–13）。丸いカバー ＋ 作品名。
//  アイコンが無い作品は 12pt の主題点にする —— **頭文字プレースホルダーは作らない**。
//  意味を持たない 1 文字は地図の情報量を増やさず、ノイズとして先に目に入ってしまう。
//

import MapKit
import UIKit

final class WorkMarkerView: MKAnnotationView {
    static let reuseIdentifier = "anitabi.work"

    /// Web `bangumis` 層のアイコン寸法。スプライトの 60×60 セルを `pixelRatio: 2` で載せるので 30pt。
    private static let iconSize: CGFloat = MapMarkerMetrics.WorkMarker.iconSize
    private static let dotSize: CGFloat = 12
    /// Web は `text-anchor: "top"` ＋ `text-offset: [0, 0.8em]` ＝ 文字の上端がアイコン中心の
    /// 8.8pt 下（＝アイコン下端に 6.2pt 食い込む）。ここでは重ねずに詰めるだけにする
    /// ——MapKit のラベルは自前描画なので、食い込ませると白ハローがアイコンを削るため。
    private static let labelGap: CGFloat = 2
    private static let maxLabelWidth: CGFloat = 92
    /// 作品名は 10 文字で切る。地図上の文字列はここを超えると隣とぶつかって読めなくなる。
    private static let maxNameLength = 10

    private let badge = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private var bangumiID: Int?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        canShowCallout = false

        badge.isUserInteractionEnabled = false
        badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.borderWidth = 1.5
        badge.layer.shadowColor = UIColor.black.cgColor
        badge.layer.shadowOpacity = 0.18
        badge.layer.shadowRadius = 1.5
        badge.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        addSubview(badge)

        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        badge.addSubview(icon)

        label.numberOfLines = 1
        label.textAlignment = .center
        // 白ハローは影とストロークの二重掛け。地図の地色（薄緑〜灰）でも文字が浮く。
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        label.isUserInteractionEnabled = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        icon.image = nil
        bangumiID = nil
    }

    func configure(with annotation: WorkAnnotation) {
        bangumiID = annotation.bangumiID
        // 重なりは `MapEngine.declutter` が画面座標で解いてある。ここで MapKit にもう一度
        // 判定させると底図のラベルとの競合に負けて全滅するので、出すと決めた物は必ず出す。
        collisionMode = .none
        displayPriority = .required
        zPriority = .defaultUnselected

        // `hasIcon`（bangumi-icons.json の回填）は起動後に非同期で埋まるので当てにしない。
        // スプライトに無ければ nil が返るだけなので、直接引いた結果を正とする。
        applyBadge(image: BangumiIconSprite.shared.icon(for: annotation.bangumiID), color: annotation.themeColor)

        label.attributedText = Self.haloedTitle(
            Self.truncate(annotation.name),
            color: annotation.themeColor.labelColor()
        )
        layoutContent()
    }

    /// スプライトが後から届いたとき用。位置と当たり判定は変えずに絵だけ差し替える。
    func refreshIcon() {
        guard let bangumiID, let annotation = annotation as? WorkAnnotation else { return }
        guard let image = BangumiIconSprite.shared.icon(for: bangumiID) else { return }
        applyBadge(image: image, color: annotation.themeColor)
        layoutContent()
    }

    private func applyBadge(image: UIImage?, color: UIColor) {
        let side = image == nil ? Self.dotSize : Self.iconSize
        badge.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        badge.layer.cornerRadius = side / 2
        badge.backgroundColor = color
        badge.layer.borderWidth = 1.5
        badge.layer.shadowPath = UIBezierPath(ovalIn: badge.bounds).cgPath

        icon.image = image
        icon.isHidden = image == nil
        icon.frame = badge.bounds
        icon.layer.cornerRadius = side / 2
    }

    private func layoutContent() {
        let badgeSide = badge.bounds.width
        let labelSize = label.sizeThatFits(
            CGSize(width: Self.maxLabelWidth, height: .greatestFiniteMagnitude)
        )
        let labelWidth = min(labelSize.width + 2, Self.maxLabelWidth)
        let width = max(badgeSide, labelWidth)
        let height = badgeSide + Self.labelGap + labelSize.height

        // アイコンの中心が座標に載るよう、ラベルのぶんだけビューを下へずらす。
        let previousOffset = centerOffset
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        centerOffset = CGPoint(x: 0, y: height / 2 - badgeSide / 2)
        center = CGPoint(x: center.x, y: center.y + (centerOffset.y - previousOffset.y))

        badge.center = CGPoint(x: width / 2, y: badgeSide / 2)
        label.frame = CGRect(
            x: (width - labelWidth) / 2,
            y: badgeSide + Self.labelGap,
            width: labelWidth,
            height: labelSize.height
        )
    }

    private static func truncate(_ name: String) -> String {
        name.count <= maxNameLength ? name : String(name.prefix(maxNameLength)) + "…"
    }

    /// Web `bangumis` 層の `text-size: 11` ＋ `text-halo-color: #FFF` / `text-halo-width: 1`
    /// （`4b970b29.js:1447-1468`）。11pt は Dynamic Type の既定より小さいので、
    /// アクセシビリティ設定に追随できるよう `.caption2` を基準にスケールさせる。
    private static func haloedTitle(_ text: String, color: UIColor) -> NSAttributedString {
        let size = UIFontMetrics(forTextStyle: .caption2)
            .scaledValue(for: MapMarkerMetrics.WorkMarker.textSize)
        return NSAttributedString(
            string: text,
            attributes: [
                // Web は "DIN Pro Bold"。
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: color,
                // 負値＝縁取りしたうえで塗りつぶす。フォントサイズに対する百分率。
                // Web の halo-width: 1 を字画の太さで再現すると白い塊に見えるので、
                // 輪郭は薄くして明るさは影のハロー（白 shadow radius 2）で稼ぐ。
                .strokeColor: UIColor.white,
                .strokeWidth: -4,
            ]
        )
    }
}
