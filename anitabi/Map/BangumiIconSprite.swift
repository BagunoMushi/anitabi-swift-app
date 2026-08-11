//
//  BangumiIconSprite.swift
//  anitabi
//
//  作品標の丸アイコン。1 枚のスプライトに 60×60 セル・1 行 20 個で並び、`bangumi-icons.json` の
//  `ids` 配列の**並び順**がそのままセル番号になる。切り出しは `CGImage.cropping(to:)`（ピクセルを
//  複製しない）で、UIImage は要求された作品ぶんだけ作る —— 全部先に切ると 20MB 超。
//

import CryptoKit
import OSLog
import UIKit

private let log = Logger(subsystem: "cn.anitabi.app", category: "icons")

@MainActor
final class BangumiIconSprite {
    static let shared = BangumiIconSprite()

    /// スプライトの 1 行あたりのセル数（本家のシート生成規則）。
    private static let columns = 20

    private(set) var isReady = false
    /// 準備完了の通知先。地図側は既に載っている作品標を貼り替えるのに使う。
    var onReady: (() -> Void)?

    private var cellIndexByBangumiID: [Int: Int] = [:]
    private var sheet: CGImage?
    private var cellSize: CGFloat = 0
    private var cache: [Int: UIImage] = [:]
    private var isLoading = false

    private init() {}

    func prepare() {
        guard !isReady, !isLoading else { return }
        isLoading = true

        Task { [weak self] in
            guard let index = await AnitabiDataLoader.shared.loadIconIndex() else {
                await MainActor.run { self?.isLoading = false }
                return
            }
            let image = await Self.fetchSheet(url: index.spriteURL)
            await MainActor.run {
                guard let self else { return }
                self.isLoading = false
                guard let cgImage = image?.cgImage else {
                    log.warning("アイコンシートを読めませんでした")
                    return
                }
                self.sheet = cgImage
                self.cellSize = CGFloat(cgImage.width) / CGFloat(Self.columns)
                self.cellIndexByBangumiID = Dictionary(
                    uniqueKeysWithValues: index.ids.enumerated().map { ($0.element, $0.offset) }
                )
                self.isReady = true
                log.info("アイコンシート \(cgImage.width)×\(cgImage.height) / \(index.ids.count) 作品")
                self.onReady?()
            }
        }
    }

    /// 作品のアイコン。未取得・未収録なら nil（呼び出し側は主題点にフォールバックする。
    /// **頭文字プレースホルダーは作らない** ―― 意味を持たない文字は地図のノイズにしかならない）。
    func icon(for bangumiID: Int) -> UIImage? {
        if let cached = cache[bangumiID] { return cached }
        guard
            let sheet,
            cellSize > 0,
            let cellIndex = cellIndexByBangumiID[bangumiID]
        else { return nil }

        let rect = CGRect(
            x: CGFloat(cellIndex % Self.columns) * cellSize,
            y: CGFloat(cellIndex / Self.columns) * cellSize,
            width: cellSize,
            height: cellSize
        )
        guard
            rect.maxY <= CGFloat(sheet.height) + 0.5,
            let cropped = sheet.cropping(to: rect.integral)
        else { return nil }

        let scale = max(UITraitCollection.current.displayScale, 1)
        let image = UIImage(cgImage: cropped, scale: scale, orientation: .up)
        cache[bangumiID] = image
        return image
    }

    // MARK: シートの取得（ディスクキャッシュ付き）

    /// スプライトは数百 KB ある。オフライン起動でも作品標が丸アイコンのままであってほしいので、
    /// `URLCache` 任せにせず自前でファイルに落としておく。
    ///
    /// ファイル名には **URL の版（`bangumi-icons.webp?v=hl5ex`）を混ぜる**。固定名にすると
    /// 新しいシートが配信されても永久に旧シートを使い続け、更新後の `ids` の並びと噛み合わずに
    /// セルがずれる（新規作品が空白セルを切り出す）。版が変われば別ファイル＝取り直しになる。
    /// 版の出所である `bangumi-icons.json` は起動ごとに取り直しているので、これで最新に追従する。
    private static func fetchSheet(url: URL) async -> UIImage? {
        let dir = AnitabiDataLoader.cacheDirectory
        let cacheFile = dir?.appendingPathComponent("bangumi-icons-\(cacheKey(for: url)).img")

        if let cacheFile, let data = try? Data(contentsOf: cacheFile), let image = UIImage(data: data) {
            return image
        }
        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let image = UIImage(data: data)
        else {
            // 取れなければ手元にある旧版のシートで代替する。並びは多少ずれ得るが、
            // 作品標が全部主題点に落ちるよりはアイコンが出ている方がよい。
            log.warning("アイコンシートの取得に失敗（旧版で代替）：\(url.absoluteString)")
            return dir.flatMap(staleSheet(in:))
        }
        if let cacheFile {
            try? data.write(to: cacheFile, options: .atomic)
            if let dir { discardSheets(in: dir, keeping: cacheFile) }
        }
        return image
    }

    /// ファイル名用の短いキー。`hashValue` は起動ごとに変わるので使えない。
    /// **ホスト名は混ぜない** —— 配信ノードが `ww.anitabi.cn` から `w.junreimap.com` へ
    /// 切り替わっても中身は同じなので、同じ版なら再ダウンロードさせない。
    private static func cacheKey(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let version = components?.queryItems?.first { $0.name == "v" }?.value
        let seed = version ?? [url.path, url.query].compactMap { $0 }.joined(separator: "?")
        return SHA256.hash(data: Data(seed.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// 手元のシートキャッシュ全部（2.1 以前の固定名 `bangumi-icons.img` も拾う）。
    private static func sheetFiles(in dir: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        return files.filter {
            $0.pathExtension == "img" && $0.lastPathComponent.hasPrefix("bangumi-icons")
        }
    }

    private static func staleSheet(in dir: URL) -> UIImage? {
        for file in sheetFiles(in: dir) {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    /// 旧版のシートを片付ける（1 枚 500KB 前後なので溜めない）。
    private static func discardSheets(in dir: URL, keeping current: URL) {
        for file in sheetFiles(in: dir) where file.lastPathComponent != current.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
