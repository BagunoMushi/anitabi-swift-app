//
//  BundleInfo.swift
//  anitabi
//
//  `Views/OnboardingView.swift`（旧 UIOnboarding 版、阶段 9 で削除）から搬出。
//  Bundle 拡張だけを独立させる —— WelcomeView・AppIdentityPill 双方から参照される
//  共通の道具なので、どちらのファイルにも属さない `Support/` に置く。
//

import UIKit

extension Bundle {
    var appIcon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? Dictionary<String, Any>,
           let primary = icons["CFBundlePrimaryIcon"] as? Dictionary<String, Any>,
           let files = primary["CFBundleIconFiles"] as? Array<String>,
           let icon = files.last {
            return .init(named: icon)
        } else {
            return nil
        }
    }

    var displayName: String? {
        // localizedInfoDictionary は InfoPlist.strings のローカライズ済みの値を返す。
        // infoDictionary だけだと常に Base（zh-Hans）の値になり、英語/日本語表示でも中国語名が出てしまう。
        return (localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (infoDictionary?["CFBundleDisplayName"] as? String)
    }

    var versionString: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
