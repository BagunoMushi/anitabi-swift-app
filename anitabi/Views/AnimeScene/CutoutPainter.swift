//
//  CutoutPainter.swift
//  anitabi
//
//  Created by 维安雨轩 on 2026/08/02.
//

import UIKit

/// 手动修补抠图：在角色被误判成背景的地方涂一笔，把原图那块补回来。之所以非要有手动这一步 ——
/// 缺失若**与画面外部相通**，自动填洞的 flood fill 会顺着缝走进去把它判成背景，而算法本来就无从
/// 知道那块该是身体还是背景。全程在像素缓冲区上操作，尺寸与原图一致，角色不位移。
final class CutoutPainter {

    /// 笔刷半径按**图像长边的比例**表示，这样和图像分辨率、和用户当前的缩放都无关。
    static let minRadiusRatio: CGFloat = 0.008
    static let maxRadiusRatio: CGFloat = 0.09
    /// 默认值：剧照只有 512×288，换算到屏幕上大约是一个指尖。
    static let defaultRadiusRatio: CGFloat = 0.035

    private let width: Int
    private let height: Int
    private let scale: CGFloat
    private let sourcePixels: [UInt8]
    private var pixels: [UInt8]

    /// 每一笔涂改前的像素备份（像素下标 → 原 RGBA），用于精确撤销。
    private var strokes: [[Int: (UInt8, UInt8, UInt8, UInt8)]] = []
    private var currentStroke: [Int: (UInt8, UInt8, UInt8, UInt8)] = [:]

    /// - Parameters:
    ///   - base: 当前显示的抠图成品（收边 + 自动填洞之后的）
    ///   - source: 与之同尺寸的原始剧照，补回来的颜色从这里取
    init?(base: UIImage, source: UIImage) {
        guard let baseCG = base.cgImage, let sourceCG = source.cgImage else { return nil }
        let width = baseCG.width
        let height = baseCG.height
        guard width > 0, height > 0,
              let basePixels = SubjectMatteRefiner.rgbaBytes(of: baseCG, width: width, height: height),
              let sourcePixels = SubjectMatteRefiner.rgbaBytes(of: sourceCG, width: width, height: height)
        else { return nil }

        self.width = width
        self.height = height
        self.scale = base.scale
        self.pixels = basePixels
        self.sourcePixels = sourcePixels
    }

    var canUndo: Bool { !strokes.isEmpty }

    func beginStroke() {
        currentStroke = [:]
    }

    /// 沿 `from` → `to` 涂一段。归一化坐标（0~1，左上原点），`radiusRatio` 占图像长边的比例。
    /// 手指拖得快时两帧之间会隔开一段距离，所以按笔刷半径插值补点，避免涂出断续的圆点。
    func paint(from start: CGPoint, to end: CGPoint, radiusRatio: CGFloat) {
        let clamped = min(max(radiusRatio, Self.minRadiusRatio), Self.maxRadiusRatio)
        let radius = CGFloat(max(width, height)) * clamped
        let p0 = CGPoint(x: start.x * CGFloat(width), y: start.y * CGFloat(height))
        let p1 = CGPoint(x: end.x * CGFloat(width), y: end.y * CGFloat(height))

        let distance = hypot(p1.x - p0.x, p1.y - p0.y)
        let steps = max(1, Int(distance / max(radius / 2, 1)))
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            stamp(at: CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t), radius: radius)
        }
    }

    func endStroke() {
        if !currentStroke.isEmpty { strokes.append(currentStroke) }
        currentStroke = [:]
    }

    func undo() {
        guard let stroke = strokes.popLast() else { return }
        for (index, rgba) in stroke {
            let offset = index * 4
            pixels[offset] = rgba.0
            pixels[offset + 1] = rgba.1
            pixels[offset + 2] = rgba.2
            pixels[offset + 3] = rgba.3
        }
    }

    func makeImage() -> UIImage? {
        SubjectMatteRefiner.makeCGImage(from: pixels, width: width, height: height)
            .map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }

    // MARK: - 私有

    /// 在一个圆内把像素替换成原图颜色并置为不透明。
    private func stamp(at center: CGPoint, radius: CGFloat) {
        let minX = max(0, Int((center.x - radius).rounded(.down)))
        let maxX = min(width - 1, Int((center.x + radius).rounded(.up)))
        let minY = max(0, Int((center.y - radius).rounded(.down)))
        let maxY = min(height - 1, Int((center.y + radius).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        let squaredRadius = radius * radius
        for y in minY...maxY {
            let dy = CGFloat(y) + 0.5 - center.y
            for x in minX...maxX {
                let dx = CGFloat(x) + 0.5 - center.x
                guard dx * dx + dy * dy <= squaredRadius else { continue }

                let index = y * width + x
                let offset = index * 4
                // 只在第一次碰到该像素时备份，同一笔里重复涂不会覆盖掉最初的状态
                if currentStroke[index] == nil {
                    currentStroke[index] = (pixels[offset], pixels[offset + 1],
                                            pixels[offset + 2], pixels[offset + 3])
                }
                pixels[offset] = sourcePixels[offset]
                pixels[offset + 1] = sourcePixels[offset + 1]
                pixels[offset + 2] = sourcePixels[offset + 2]
                pixels[offset + 3] = 255
            }
        }
    }
}
