//
//  PointMarkerView.swift
//  anitabi
//
//  地標の標注。主題点 ⇄ 劇照サムネイル ⇄ 選択気球を**同じビューの中で**切り替える（形態ごとに
//  クラスを分けると、ズームを跨いだ瞬間に全標注が remove/add されて画面が瞬く）。座標のアンカーも
//  形態で変わるので、`centerOffset` と `center` を同時に動かして辻褄を合わせる（`applyGeometry`）。
//

import MapKit
import UIKit

final class PointMarkerView: MKAnnotationView {
    static let reuseIdentifier = "anitabi.point"

    /// 9pt の点は指では狙えない。当たり判定だけ広げる（衝突判定には frame が使われるので無関係）。
    private static let touchSlop: CGFloat = 10

    private let dotBody = DotMarkerBody()
    /// サムネイル標と気球は使う点だけ作る（600 個ぶん先に作ると無駄が大きい）。
    private var photoBody: PhotoMarkerBody?
    private var balloonBody: BalloonMarkerBody?

    private var form: PointMarkerForm = .dot
    /// Web `circle-radius` ×2 ＝ 色が付いている部分の直径。
    private var dotCore: CGFloat = 8
    /// Web `circle-stroke-width`。Mapbox と同じく**外側**に足す白描边。
    private var dotStroke: CGFloat = 1.5
    private var photoStyle: PhotoMarkerBody.Style = .bubble
    private var imageURL: URL?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        canShowCallout = false
        addSubview(dotBody)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
        imageURL = nil
        form = .dot
        photoBody?.isHidden = true
        balloonBody?.isHidden = true
        dotBody.isHidden = false
        dotBody.transform = .identity
        dotBody.alpha = 1
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -Self.touchSlop, dy: -Self.touchSlop).contains(point)
    }

    // MARK: 構成

    func configure(with annotation: ScenePointAnnotation, zoom: Double, animated: Bool) {
        dotCore = CGFloat(MapMarkerMetrics.dotRadius(zoom: zoom)) * 2
        dotStroke = CGFloat(MapMarkerMetrics.dotStrokeWidth(zoom: zoom))
        photoStyle = Self.photoStyle(zoom: zoom)
        dotBody.apply(
            core: dotCore,
            stroke: dotStroke,
            color: annotation.themeColor,
            innerOutline: annotation.needsInnerOutline
        )
        setForm(annotation.form, annotation: annotation, animated: animated)
    }

    /// ズームだけが変わったときの軽い更新（形態はそのまま）。
    /// 主題点の寸法だけでなく、劇照の絵（小泡 ⇄ 大カード）も z18 で入れ替わる。
    func updateZoom(_ zoom: Double, animated: Bool) {
        let core = CGFloat(MapMarkerMetrics.dotRadius(zoom: zoom)) * 2
        let stroke = CGFloat(MapMarkerMetrics.dotStrokeWidth(zoom: zoom))
        let style = Self.photoStyle(zoom: zoom)
        let dotChanged = abs(core - dotCore) > 0.3 || abs(stroke - dotStroke) > 0.15
        let styleChanged = style != photoStyle
        guard dotChanged || styleChanged else { return }

        dotCore = core
        dotStroke = stroke
        photoStyle = style
        if dotChanged { dotBody.resize(core: core, stroke: stroke) }

        switch form {
        case .dot where dotChanged:
            let side = core + stroke * 2
            let apply = { self.applyGeometry(size: CGSize(width: side, height: side), offset: .zero) }
            if animated {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState], animations: apply)
            } else {
                apply()
            }
        case .photo where styleChanged:
            guard let annotation = annotation as? ScenePointAnnotation else { return }
            let apply = { self.applyPhotoGeometry(annotation: annotation) }
            if animated {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState], animations: apply)
            } else {
                apply()
            }
        default:
            break
        }
    }

    /// 劇照をどちらの絵で描くか。Web で層が入れ替わる境目（`points-image` は z>18 のみ、
    /// `bangumi-points-theme` は `maxzoom: 18`）と同じ 18 で切り替える。
    private static func photoStyle(zoom: Double) -> PhotoMarkerBody.Style {
        zoom > MapRevealLadder.photoCardZoom ? .card : .bubble
    }

    // MARK: 形態

    private func setForm(_ next: PointMarkerForm, annotation: ScenePointAnnotation, animated: Bool) {
        let previous = form
        form = next

        switch next {
        case .dot:
            let side = dotCore + dotStroke * 2
            applyGeometry(size: CGSize(width: side, height: side), offset: .zero)
            collisionMode = .circle
            displayPriority = annotation.displayPriority
            zPriority = .min
            show(dotBody, hiding: [photoBody, balloonBody], changed: previous != next, animated: animated)

        case .photo:
            applyPhotoGeometry(annotation: annotation)
            collisionMode = .rectangle
            displayPriority = annotation.displayPriority
            zPriority = .defaultUnselected
            let body = photoBody ?? {
                let created = PhotoMarkerBody()
                photoBody = created
                return created
            }()
            loadImage(for: annotation) { [weak body] in body?.setImage($0) }
            show(body, hiding: [dotBody, balloonBody], changed: previous != next, animated: animated)

        case .balloon:
            applyGeometry(size: BalloonMarkerBody.size, offset: BalloonMarkerBody.centerOffset)
            // 選択中の標注は何があっても消えてはいけない。
            collisionMode = .none
            displayPriority = .required
            zPriority = .max
            let body = balloonBody ?? {
                let created = BalloonMarkerBody()
                balloonBody = created
                return created
            }()
            body.apply(color: annotation.themeColor, dimSymbol: annotation.needsInnerOutline)
            loadImage(for: annotation) { [weak body] in body?.setImage($0) }
            show(body, hiding: [dotBody, photoBody], changed: previous != next, animated: animated)
        }
    }

    private func show(_ body: UIView, hiding others: [UIView?], changed: Bool, animated: Bool) {
        if body.superview == nil { addSubview(body) }
        if let balloon = body as? BalloonMarkerBody {
            balloon.pinToBottomCenter(of: bounds)
        } else {
            body.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        body.isHidden = false

        guard animated, changed else {
            body.alpha = 1
            body.transform = .identity
            for case let other? in others where !other.isHidden {
                other.isHidden = true
                other.alpha = 1
                other.transform = .identity
            }
            return
        }

        for case let other? in others where !other.isHidden {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState]) {
                other.alpha = 0
                other.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            } completion: { _ in
                other.isHidden = true
                other.alpha = 1
                other.transform = .identity
            }
        }

        // 気球だけは Apple マップと同じく点から「生えて」くる（軸は尾の先端＝座標）。
        let isBalloon = form == .balloon
        body.alpha = isBalloon ? 0.6 : 0
        body.transform = CGAffineTransform(scaleX: isBalloon ? 0.4 : 0.6, y: isBalloon ? 0.4 : 0.6)
        UIView.animate(
            withDuration: isBalloon ? 0.32 : 0.22,
            delay: 0,
            usingSpringWithDamping: isBalloon ? 0.7 : 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            body.alpha = 1
            body.transform = .identity
        }
    }

    /// 劇照の絵を今のズームの様式に合わせる（枠色とサイズ、尾の先端＝座標）。
    private func applyPhotoGeometry(annotation: ScenePointAnnotation) {
        let body = photoBody ?? {
            let created = PhotoMarkerBody()
            photoBody = created
            return created
        }()
        body.apply(style: photoStyle, themeColor: annotation.themeColor)
        applyGeometry(size: body.bounds.size, offset: body.markerCenterOffset)
        body.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// `bounds` と `centerOffset` を同時に差し替える。`centerOffset` の変化ぶんは MapKit が
    /// 次に再配置するまで反映されないため、自分で `center` を動かして即座に辻褄を合わせる。
    private func applyGeometry(size: CGSize, offset: CGPoint) {
        let delta = CGPoint(x: offset.x - centerOffset.x, y: offset.y - centerOffset.y)
        bounds = CGRect(origin: .zero, size: size)
        centerOffset = offset
        center = CGPoint(x: center.x + delta.x, y: center.y + delta.y)
    }

    // MARK: 画像

    private func loadImage(for annotation: ScenePointAnnotation, apply: @escaping (UIImage?) -> Void) {
        guard let url = annotation.point.thumbnailURL else {
            imageURL = nil
            apply(nil)
            return
        }
        imageURL = url
        if let cached = MarkerImageCache.shared.cachedImage(for: url) {
            apply(cached)
            return
        }
        apply(nil)
        MarkerImageCache.shared.load(url) { [weak self] image in
            // 再利用で別の点になっているかもしれない。
            guard let self, self.imageURL == url else { return }
            apply(image)
        }
    }
}

// MARK: - 主題点

/// Web `bangumi-point`（circle 層）等価物。Mapbox の circle は塗りの**外側**に描边を足すので、
/// ビューの一辺は `2r + 2×stroke` で、白描边は UIView の border（内側に描かれる）でそのまま作れる。
/// 影は付けない —— Web の circle 層にも無く、白描边だけで地図から浮く。
private final class DotMarkerBody: UIView {
    private let innerOutline = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.borderColor = UIColor.white.cgColor
        innerOutline.borderColor = UIColor.black.withAlphaComponent(0.22).cgColor
        innerOutline.borderWidth = 0.5
        innerOutline.isHidden = true
        layer.addSublayer(innerOutline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(core: CGFloat, stroke: CGFloat, color: UIColor, innerOutline hasOutline: Bool) {
        backgroundColor = color
        innerOutline.isHidden = !hasOutline
        resize(core: core, stroke: stroke)
    }

    /// - Parameters:
    ///   - core: 色が付いている部分の直径（Web の `circle-radius` ×2）。
    ///   - stroke: 白描边の太さ（Web の `circle-stroke-width`）。
    func resize(core: CGFloat, stroke: CGFloat) {
        let side = core + stroke * 2
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layer.cornerRadius = side / 2
        layer.borderWidth = stroke

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        innerOutline.frame = bounds.insetBy(dx: stroke, dy: stroke)
        innerOutline.cornerRadius = max(innerOutline.bounds.width, 0) / 2
        CATransaction.commit()
    }
}

// MARK: - 劇照サムネイル標

/// Web の劇照 2 層の等価物。ズームで**寸法だけ**を差し替える（ビューは作り直さない）。
/// 意匠は 2 段とも同じ「作品色の枠 ＋ 滴 ＋ 画像の内三角」—— Web の「大カード無枠／小泡有枠」の
/// 2 意匠混在は同画面でおかしいので採らない（寸法は `MapMarkerMetrics.PhotoPlate`）。
private final class PhotoMarkerBody: UIView {

    enum Style {
        case card, bubble

        var plate: MapMarkerMetrics.PhotoPlate {
            self == .card ? .card : .bubble
        }
    }

    private let frameLayer = CAShapeLayer()
    private let contentLayer = CALayer()
    private let contentMask = CAShapeLayer()
    private let placeholder = CAGradientLayer()
    private let imageLayer = CALayer()

    private var style: Style?
    private var themeColor: UIColor = .anitabiNeutralTheme

    /// 尾の先端が座標。ビューの中心はそのぶん上に置く。
    var markerCenterOffset: CGPoint {
        CGPoint(x: 0, y: -bounds.height / 2 - (style ?? .bubble).plate.anchorLift)
    }

    override init(frame: CGRect) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        frameLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(frameLayer)

        placeholder.startPoint = CGPoint(x: 0, y: 0)
        placeholder.endPoint = CGPoint(x: 1, y: 1)
        contentLayer.addSublayer(placeholder)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        contentLayer.addSublayer(imageLayer)

        contentLayer.mask = contentMask
        layer.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(style newStyle: Style, themeColor color: UIColor) {
        let colorChanged = color != themeColor
        themeColor = color
        guard newStyle != style || colorChanged else { return }
        style = newStyle

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layOut(newStyle.plate)
        placeholder.colors = [
            themeColor.cgColor,
            themeColor.mixed(with: .black, amount: 0.28).cgColor,
        ]
        CATransaction.commit()
    }

    func setImage(_ image: UIImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image?.cgImage
        placeholder.isHidden = image != nil
        CATransaction.commit()
    }

    // MARK: 様式

    /// 作品色の枠を敷き、その内側を画像（無ければ主題色グラデ）で塗る。
    /// 大カードと小泡は**同じ意匠**なので、違うのは渡す寸法だけ。
    private func layOut(_ plate: MapMarkerMetrics.PhotoPlate) {
        bounds = CGRect(origin: .zero, size: plate.totalSize)

        let body = CGRect(origin: .zero, size: plate.bodySize)
        frameLayer.isHidden = false
        frameLayer.frame = bounds
        frameLayer.fillColor = themeColor.cgColor
        frameLayer.path = Self.platePath(
            body: body,
            cornerRadius: plate.cornerRadius,
            tail: plate.dripSize,
            tailTopOverlap: 0.5
        ).cgPath

        let inset = plate.borderWidth
        let inner = body.insetBy(dx: inset, dy: inset)
        contentLayer.frame = bounds
        placeholder.frame = inner
        imageLayer.frame = inner
        contentMask.frame = bounds
        contentMask.path = Self.platePath(
            body: inner,
            cornerRadius: plate.cornerRadius - inset,
            tail: plate.innerTailSize,
            tailTopOverlap: plate.innerTailOverlap - inset
        ).cgPath
    }

    /// 本体（角丸矩形）と下縁の尾を 1 本のパスにする。別レイヤーに分けると継ぎ目に線が出る。
    private static func platePath(
        body: CGRect,
        cornerRadius: CGFloat,
        tail: CGSize,
        tailTopOverlap: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath(roundedRect: body, cornerRadius: max(cornerRadius, 0))
        let top = body.maxY - tailTopOverlap
        let tailPath = UIBezierPath()
        tailPath.move(to: CGPoint(x: body.midX - tail.width / 2, y: top))
        tailPath.addLine(to: CGPoint(x: body.midX + tail.width / 2, y: top))
        tailPath.addLine(to: CGPoint(x: body.midX, y: body.maxY + tail.height))
        tailPath.close()
        path.append(tailPath)
        return path
    }
}

// MARK: - 選択気球

private final class BalloonMarkerBody: UIView {
    /// 頭 32 ＋ 尾 10。
    static let size = CGSize(width: 32, height: 42)
    static let centerOffset = CGPoint(x: 0, y: -size.height / 2)

    private let shape = CAShapeLayer()
    private let thumbnail = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        isUserInteractionEnabled = false
        // 尾の先端＝座標を軸に弾ませる。
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)

        let path = Self.balloonPath()
        shape.path = path.cgPath
        shape.strokeColor = UIColor.white.cgColor
        shape.lineWidth = 1.5
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.22
        shape.shadowRadius = 4
        shape.shadowOffset = CGSize(width: 0, height: 2)
        shape.shadowPath = path.cgPath
        shape.frame = CGRect(origin: .zero, size: Self.size)
        layer.addSublayer(shape)

        thumbnail.frame = CGRect(x: 4, y: 4, width: 24, height: 24)
        thumbnail.layer.cornerRadius = 12
        thumbnail.layer.masksToBounds = true
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        addSubview(thumbnail)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(color: UIColor, dimSymbol: Bool) {
        shape.fillColor = color.cgColor
        // 白に近いテーマ色の上では白いシンボルが消える。
        thumbnail.tintColor = dimSymbol ? UIColor(white: 0.28, alpha: 1) : .white
    }

    func setImage(_ image: UIImage?) {
        thumbnail.image = image ?? UIImage(systemName: "photo.fill")
    }

    /// anchorPoint を動かしているぶん、親の中心ではなく「下端中央」に置き直す。
    func pinToBottomCenter(of rect: CGRect) {
        frame = CGRect(
            x: rect.midX - Self.size.width / 2,
            y: rect.maxY - Self.size.height,
            width: Self.size.width,
            height: Self.size.height
        )
    }

    private static func balloonPath() -> UIBezierPath {
        let radius: CGFloat = 16
        let center = CGPoint(x: 16, y: 16)
        let tip = CGPoint(x: 16, y: 42)
        // 先端から円へ引いた接線の接点。ここを外すと頭と尾の繋ぎ目に段差が出る。
        let beta = acos(radius / (tip.y - center.y))
        let rightTangent = CGFloat.pi / 2 - beta
        let leftTangent = CGFloat.pi / 2 + beta

        let path = UIBezierPath()
        // UIKit は y 下向きなので clockwise:false ＝ 画面上では上side を回る。
        path.addArc(
            withCenter: center,
            radius: radius,
            startAngle: rightTangent,
            endAngle: leftTangent,
            clockwise: false
        )
        path.addLine(to: tip)
        path.close()
        return path
    }
}

// MARK: - 標注画像の供給

/// 標注が使う h160 サムネイル専用の小さな取得口。地図は 1 フレームで数十枚を要求するので
/// 同時接続を絞り、デコードまで済ませてからメインに返す（スクロール中の hitch 対策）。
@MainActor
final class MarkerImageCache {
    static let shared = MarkerImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private var waiting: [URL: [(UIImage?) -> Void]] = [:]
    private let session: URLSession

    private init() {
        cache.countLimit = 400
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cached = cachedImage(for: url) {
            completion(cached)
            return
        }
        if waiting[url] != nil {
            waiting[url]?.append(completion)
            return
        }
        waiting[url] = [completion]

        Task { [session] in
            var image: UIImage?
            if
                let (data, response) = try? await session.data(from: url),
                let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let raw = UIImage(data: data)
            {
                image = await raw.byPreparingForDisplay() ?? raw
            }
            if let image { cache.setObject(image, forKey: url as NSURL) }
            for callback in waiting.removeValue(forKey: url) ?? [] { callback(image) }
        }
    }
}
