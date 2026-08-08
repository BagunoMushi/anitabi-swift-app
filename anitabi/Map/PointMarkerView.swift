//
//  PointMarkerView.swift
//  anitabi
//
//  地標の標注。主題点 ⇄ 劇照サムネイル ⇄ 選択気球を **同じビューの中で** 切り替える。
//  形態ごとにクラスを分けると、ズームを跨いだ瞬間に全標注が remove/add されて画面が瞬く。
//
//  座標のアンカーは形態で変わる（点＝中心、サムネイル／気球＝尾の先端）。
//  `centerOffset` を書き換えても MapKit が再配置するのは次のレイアウト時なので、
//  差分ぶんだけ `center` も自分でずらして即座に見た目を合わせる（`applyGeometry`）。
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
    private var diameter: CGFloat = 9
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
        diameter = Self.dotDiameter(zoom: zoom)
        dotBody.apply(
            diameter: diameter,
            color: annotation.themeColor,
            innerOutline: annotation.needsInnerOutline
        )
        setForm(annotation.form, annotation: annotation, animated: animated)
    }

    /// ズームだけが変わったときの軽い更新（形態はそのまま）。
    func updateZoom(_ zoom: Double, animated: Bool) {
        let next = Self.dotDiameter(zoom: zoom)
        guard abs(next - diameter) > 0.4 else { return }
        diameter = next
        dotBody.resize(diameter: next)
        guard form == .dot else { return }
        let apply = { self.applyGeometry(size: CGSize(width: next, height: next), offset: .zero) }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }

    /// z≤12 で 9pt、z≥17 で 18pt。間は線形 ―― 縮尺が上がるほど点が「地面の物」に見えてくる。
    static func dotDiameter(zoom: Double) -> CGFloat {
        let clamped = min(max(zoom, 12), 17)
        return 9 + CGFloat(clamped - 12) / 5 * 9
    }

    // MARK: 形態

    private func setForm(_ next: PointMarkerForm, annotation: ScenePointAnnotation, animated: Bool) {
        let previous = form
        form = next

        switch next {
        case .dot:
            applyGeometry(size: CGSize(width: diameter, height: diameter), offset: .zero)
            collisionMode = .circle
            displayPriority = annotation.displayPriority
            zPriority = .min
            show(dotBody, hiding: [photoBody, balloonBody], changed: previous != next, animated: animated)

        case .photo:
            applyGeometry(size: PhotoMarkerBody.size, offset: PhotoMarkerBody.centerOffset)
            collisionMode = .rectangle
            displayPriority = annotation.displayPriority
            zPriority = .defaultUnselected
            let body = photoBody ?? {
                let created = PhotoMarkerBody()
                photoBody = created
                return created
            }()
            body.placeholderColor = annotation.themeColor
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

private final class DotMarkerBody: UIView {
    private let innerOutline = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: 0.5)
        innerOutline.borderColor = UIColor.black.withAlphaComponent(0.22).cgColor
        innerOutline.borderWidth = 0.5
        innerOutline.isHidden = true
        layer.addSublayer(innerOutline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(diameter: CGFloat, color: UIColor, innerOutline hasOutline: Bool) {
        backgroundColor = color
        innerOutline.isHidden = !hasOutline
        resize(diameter: diameter)
    }

    func resize(diameter: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.cornerRadius = diameter / 2
        layer.borderWidth = diameter >= 14 ? 2 : 1.5
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath

        let inset = layer.borderWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        innerOutline.frame = bounds.insetBy(dx: inset, dy: inset)
        innerOutline.cornerRadius = max(innerOutline.bounds.width, 0) / 2
        CATransaction.commit()
    }
}

// MARK: - 劇照サムネイル標

private final class PhotoMarkerBody: UIView {
    /// 劇照 64×40 ＋ 白描边 2 ＋ 下縁の指針尾 8×6。
    static let size = CGSize(width: 68, height: 50)
    /// 尾の先端が座標。ビューの中心はそのぶん上に置く。
    static let centerOffset = CGPoint(x: 0, y: -size.height / 2)

    private let plate = CAShapeLayer()
    private let imageLayer = CALayer()
    private let placeholder = CAGradientLayer()

    var placeholderColor: UIColor = .anitabiNeutralTheme {
        didSet { applyPlaceholder() }
    }

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        isUserInteractionEnabled = false

        let path = Self.platePath()
        plate.path = path.cgPath
        plate.fillColor = UIColor.white.cgColor
        plate.shadowColor = UIColor.black.cgColor
        plate.shadowOpacity = 0.22
        plate.shadowRadius = 4
        plate.shadowOffset = CGSize(width: 0, height: 2)
        plate.shadowPath = path.cgPath
        plate.frame = bounds
        layer.addSublayer(plate)

        let photoRect = CGRect(x: 2, y: 2, width: 64, height: 40)
        placeholder.frame = photoRect
        placeholder.cornerRadius = 8
        placeholder.startPoint = CGPoint(x: 0, y: 0)
        placeholder.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(placeholder)

        imageLayer.frame = photoRect
        imageLayer.cornerRadius = 8
        imageLayer.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        layer.addSublayer(imageLayer)
        applyPlaceholder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image?.cgImage
        placeholder.isHidden = image != nil
        CATransaction.commit()
    }

    private func applyPlaceholder() {
        placeholder.colors = [
            placeholderColor.cgColor,
            placeholderColor.mixed(with: .black, amount: 0.28).cgColor,
        ]
    }

    /// 板と尾を 1 本のパスにする（別レイヤーにすると継ぎ目に白線が出る）。
    private static func platePath() -> UIBezierPath {
        let path = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: 68, height: 44),
            cornerRadius: 9
        )
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: 30, y: 42))
        tail.addLine(to: CGPoint(x: 38, y: 42))
        tail.addLine(to: CGPoint(x: 34, y: 50))
        tail.close()
        path.append(tail)
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
