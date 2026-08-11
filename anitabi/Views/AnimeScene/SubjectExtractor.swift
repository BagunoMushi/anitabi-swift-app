//
//  SubjectExtractor.swift
//  anitabi
//
//  Created by 维安雨轩 on 2026/08/02.
//

import UIKit
import Vision

// MARK: - 抠图结果

/// 从剧照里抠出的主体（通常是角色）。
struct SubjectCutout {
    /// 去掉背景后的图像：**尺寸和构图与原图一致，角色留在原位**，只是背景变透明 —— 这样换图时
    /// 角色在屏幕上分毫不动，背景则透出实时相机画面用于对齐。这里留的是 Vision 的原始输出，
    /// 收边交给 `SubjectMatteRefiner`（强度要能实时调，得反复重算）。
    let image: UIImage

    /// 主体像素占原图的比例（0~1）。判断「抠得靠不靠谱」的主要信号：过小多半只抠到零碎的角落，
    /// 过大多半是没能把角色和背景分开、整张图被当成了前景。
    let coverage: CGFloat?

    /// Vision 实际看到的那张图（已归一化 + 降采样），**像素尺寸与 `image` 严格一致**。
    /// 填洞和手动修补要从这里取回原本的颜色。
    let source: UIImage

    /// 是否值得拿去叠加的粗判。覆盖率未知时不拦（宁可放过，不误杀）。
    var isPlausible: Bool {
        guard let coverage else { return true }
        return coverage > 0.02 && coverage < 0.85
    }
}

enum SubjectExtractionError: LocalizedError {
    case invalidImage
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片无法解析"
        case .renderFailed: return "抠图结果渲染失败"
        }
    }
}

// MARK: - Vision 实现

/// 剧照主体抠图，基于 `VNGenerateForegroundInstanceMaskRequest`（iOS 17+），也就是「照片」App
/// 长按图片抠主体的那套系统能力：零体积、零下载、走 ANE。它按真实照片训练，对二次元剧照会有
/// 边缘脏、大块缺失等问题，交给 `SubjectMatteRefiner` 和 `CutoutPainter` 收拾。
final class VisionSubjectExtractor {

    /// 送进 Vision 前的长边上限。原图直接跑既慢又费内存，而抠出来的角色只叠在取景框上，
    /// 这个分辨率绰绰有余。
    private static let analysisMaxDimension: CGFloat = 1536

    /// 统计 mask 时的采样上限（长边）。coverage 只是个比例，不需要逐像素精确。
    private static let samplingMaxDimension = 512

    /// Vision 单次推理占内存不小，串行跑避免多张图并发时峰值叠加。
    private static let queue = DispatchQueue(label: "cn.anitabi.subject-extractor", qos: .userInitiated)

    /// CIContext 创建开销大（要起 Metal），全 App 共用一个。
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    func extractSubject(from image: UIImage) async throws -> SubjectCutout? {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do {
                    continuation.resume(returning: try Self.performExtraction(on: image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func performExtraction(on image: UIImage) throws -> SubjectCutout? {
        // downscaled 内部两条分支都会归一化方向，cgImage 按像素裁剪前必须这么做。
        let source = image.downscaled(maxDimension: Self.analysisMaxDimension)
        guard let cgImage = source.cgImage else { throw SubjectExtractionError.invalidImage }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }
        let instances = observation.allInstances
        guard !instances.isEmpty else { return nil }

        // croppedToInstancesExtent: false —— 保留原图幅面，角色留在原位，只把背景挖成透明。
        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: instances,
            from: handler,
            croppedToInstancesExtent: false
        )
        guard let cutout = makeImage(from: maskedBuffer, scale: source.scale) else {
            throw SubjectExtractionError.renderFailed
        }

        let coverage = (try? observation.generateScaledMaskForImage(forInstances: instances, from: handler))
            .flatMap(averageValue(of:))

        return SubjectCutout(image: cutout, coverage: coverage, source: source)
    }

    // MARK: - 私有工具

    private static func makeImage(from buffer: CVPixelBuffer, scale: CGFloat) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// mask 的平均值 = 主体像素占比。按 `samplingMaxDimension` 抽样，不逐像素扫。
    /// Vision 没有承诺 mask 的像素格式，所以只认已知的两种，遇到别的返回 `nil`。
    private static func averageValue(of mask: CVPixelBuffer) -> CGFloat? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0 else { return nil }

        let step = max(1, Int((Double(max(width, height)) / Double(samplingMaxDimension)).rounded(.up)))
        var total = 0.0
        var samples = 0

        switch CVPixelBufferGetPixelFormatType(mask) {
        case kCVPixelFormatType_OneComponent8:
            for y in stride(from: 0, to: height, by: step) {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: 0, to: width, by: step) {
                    total += Double(row[x])
                    samples += 1
                }
            }
            total /= 255

        case kCVPixelFormatType_OneComponent32Float:
            for y in stride(from: 0, to: height, by: step) {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in stride(from: 0, to: width, by: step) {
                    total += Double(row[x])
                    samples += 1
                }
            }

        default:
            return nil
        }

        guard samples > 0 else { return nil }
        return CGFloat(total / Double(samples))
    }
}
