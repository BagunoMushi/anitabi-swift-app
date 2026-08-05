//
//  SubjectMatteRefiner.swift
//  anitabi
//
//  Created by 维安雨轩 on 2026/08/02.
//

import UIKit
import CoreImage

/// 把 Vision 的原始抠图收拾成能直接叠到实景上的样子。两步，解决两类完全不同的毛病：
///
/// 1. **alpha 线性拉伸** —— 治边缘。
///    发丝、半透明过渡处会留下一圈掺了原背景颜色的像素，alpha 偏低，落在 `alphaFloor` 以下被抹掉；
///    同时把落在 `alphaCeiling` 以上的一律拉成完全不透明，避免置信度中等的角色整体发白发虚。
///    上限刻意压得很低：一张剧照里主角 mask 是实的、配角往往整片只有 0.5 上下，
///    **只压不提的曲线会把配角削没**（真机验证过，会削成半透明发白）。
///
/// 2. **内部填洞** —— 治大块缺失。
///    Vision 偶尔会把角色身上一整块（衣服、肚子）误判成背景，留下一个洞。
///    这类洞的 alpha 本来就是 0，再怎么调阈值也变不出来，只能单独补。
///    只对**四面被角色围死**的洞生效；从腋下、衣摆缝隙通向画面外的缺失判不出来，
///    那种交给 `CutoutPainter` 手动补。
///
/// 刻意不用形态学腐蚀/闭运算：腐蚀按半径无差别啃掉一圈，而剧照只有 512×288、发丝才 1~2px，
/// 一腐蚀就没了；闭运算填洞则会把手臂与身体之间那种**本该透的缝**一起糊死。
enum SubjectMatteRefiner {

    /// alpha 低于此值的像素抹成全透明 —— 脏边就集中在这一档。
    private static let alphaFloor: CGFloat = 0.1

    /// alpha 高于此值的像素拉成完全不透明。
    private static let alphaCeiling: CGFloat = 0.3

    /// 判定「这个像素算背景」的 alpha 阈值（0~255），供填洞用。
    private static let holeAlphaThreshold: UInt8 = 128

    /// 填洞面积上限（占全图比例）。超过说明判断跑偏了（多半是整块背景被围住），宁可不补。
    private static let maxHoleAreaRatio = 0.25

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// - Parameters:
    ///   - cutout: `SubjectExtractor` 产出的原始抠图
    ///   - source: 与 `cutout` 同尺寸的原始剧照，填洞时从这里取颜色
    /// - Returns: 与输入**同尺寸同构图**的图像；失败时返回 `nil`，由调用方退回原图
    static func refined(_ cutout: UIImage, source: UIImage) -> UIImage? {
        guard let cutoutCG = cutout.cgImage else { return nil }

        let sourceCI = CIImage(cgImage: cutoutCG)
        let baseCG = context.createCGImage(stretchAlpha(of: sourceCI), from: sourceCI.extent) ?? cutoutCG

        let width = baseCG.width
        let height = baseCG.height
        guard width > 0, height > 0 else { return nil }

        guard var pixels = rgbaBytes(of: baseCG, width: width, height: height) else {
            return UIImage(cgImage: baseCG, scale: cutout.scale, orientation: .up)
        }

        // 填洞失败/无洞都不算错，直接用拉伸后的结果。
        if let holes = interiorHoles(in: pixels, width: width, height: height),
           let sourceCG = source.cgImage,
           let sourcePixels = rgbaBytes(of: sourceCG, width: width, height: height) {
            fill(&pixels, holes: holes, from: sourcePixels)
        }

        guard let filled = makeCGImage(from: pixels, width: width, height: height) else {
            return UIImage(cgImage: baseCG, scale: cutout.scale, orientation: .up)
        }
        return UIImage(cgImage: filled, scale: cutout.scale, orientation: .up)
    }

    // MARK: - alpha 拉伸

    /// `alpha' = clamp((alpha - alphaFloor) / (alphaCeiling - alphaFloor))`。
    ///
    /// 必须在**非预乘**空间做 —— 预乘状态下颜色里含着 alpha，单独改会把颜色一起改错。
    private static func stretchAlpha(of image: CIImage) -> CIImage {
        let floor = alphaFloor
        let slope = 1 / max(alphaCeiling - alphaFloor, 0.01)

        return image
            .applyingFilter("CIUnpremultiply")
            .applyingFilter("CIColorPolynomial", parameters: [
                // 系数依次是常数项、一次项、二次项、三次项
                "inputAlphaCoefficients": CIVector(x: -floor * slope, y: slope, z: 0, w: 0)
            ])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIPremultiply")
    }

    // MARK: - 内部填洞

    /// 从四条边界对「透明区域」做 flood fill，**连不到边界的透明像素就是内部洞**。
    ///
    /// 比形态学闭运算准得多：手臂与身体之间的缝隙通常向外敞口，会被 flood fill 走到，
    /// 因而不会被误填；而肚子上那种四面被角色围住的洞连不到边界，正好补上。
    ///
    /// - Returns: 洞的像素下标；没有洞（或洞大得离谱）时返回 `nil`
    private static func interiorHoles(in pixels: [UInt8], width: Int, height: Int) -> [Int]? {
        let count = width * height
        var reachedFromBorder = [Bool](repeating: false, count: count)
        var stack = [Int]()

        func seed(_ index: Int) {
            guard !reachedFromBorder[index], pixels[index * 4 + 3] < holeAlphaThreshold else { return }
            reachedFromBorder[index] = true
            stack.append(index)
        }

        for x in 0..<width {
            seed(x)                          // 上边
            seed((height - 1) * width + x)   // 下边
        }
        for y in 0..<height {
            seed(y * width)                  // 左边
            seed(y * width + width - 1)      // 右边
        }

        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            if x > 0 { seed(index - 1) }
            if x < width - 1 { seed(index + 1) }
            if y > 0 { seed(index - width) }
            if y < height - 1 { seed(index + width) }
        }

        // 按连通域逐个收集：面积上限**对单个洞生效**，一个大得离谱的洞只跳过它自己，
        // 不会连带把其他正常的小洞一起放弃。
        let maxComponentArea = Int(Double(count) * maxHoleAreaRatio)
        var visited = reachedFromBorder
        var holes = [Int]()
        var component = [Int]()

        for start in 0..<count where !visited[start] && pixels[start * 4 + 3] < holeAlphaThreshold {
            component.removeAll(keepingCapacity: true)
            visited[start] = true
            stack.append(start)

            func walk(_ index: Int) {
                guard !visited[index], pixels[index * 4 + 3] < holeAlphaThreshold else { return }
                visited[index] = true
                stack.append(index)
            }

            while let index = stack.popLast() {
                component.append(index)
                let x = index % width
                let y = index / width
                if x > 0 { walk(index - 1) }
                if x < width - 1 { walk(index + 1) }
                if y > 0 { walk(index - width) }
                if y < height - 1 { walk(index + width) }
            }

            if component.count <= maxComponentArea { holes.append(contentsOf: component) }
        }

        return holes.isEmpty ? nil : holes
    }

    /// 用原图颜色把洞补成完全不透明。源图不透明，故直接写入即是正确的预乘值。
    private static func fill(_ pixels: inout [UInt8], holes: [Int], from source: [UInt8]) {
        for index in holes {
            let offset = index * 4
            pixels[offset] = source[offset]
            pixels[offset + 1] = source[offset + 1]
            pixels[offset + 2] = source[offset + 2]
            pixels[offset + 3] = 255
        }
    }

    // MARK: - 位图往返
    // `CutoutPainter` 也用这两个，所以是 internal。

    static func rgbaBytes(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    static func makeCGImage(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = pixels
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }
}
