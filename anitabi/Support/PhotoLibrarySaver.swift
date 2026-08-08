//
//  PhotoLibrarySaver.swift
//  anitabi
//
//  写真ライブラリへの保存。`UIImageWriteToSavedPhotosAlbum` + セレクタ callback の置き換えで、
//  権限は **`.addOnly`**（追加専用）しか要求しない —— 対比图を書き出すだけなので、
//  ライブラリ全体の読み取り権限を求める理由が無い。
//

import Photos
import UIKit

enum PhotoLibrarySaver {

    enum SaveError: LocalizedError {
        /// 追加権限が無い（拒否済み・制限中）。呼び出し側は「設定へ」導線を出す。
        case notAuthorized
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                String(localized: "没有相册的添加权限，请在「设置」中允许后再试。")
            case .underlying(let error):
                error.localizedDescription
            }
        }

        /// 「前往设置」を出すべきか。書き込み失敗（容量不足など）では出さない。
        var isPermissionDenied: Bool {
            if case .notAuthorized = self { return true }
            return false
        }
    }

    /// 保存する。未決定なら許可ダイアログを出し、拒否されていれば `SaveError.notAuthorized`。
    static func save(_ image: UIImage) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        // `.limited` でも「追加」だけは通る（選択済みアセットの制限は読み取り側の話）。
        guard status == .authorized || status == .limited else {
            throw SaveError.notAuthorized
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            throw SaveError.underlying(error)
        }
    }
}
