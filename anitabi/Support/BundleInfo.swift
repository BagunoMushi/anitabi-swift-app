//
//  BundleInfo.swift
//  anitabi
//
//  アプリ自身の表示名・アイコン・バージョン。`WelcomeView`・`AboutSheet`・
//  `AppIdentityPill` から参照される共通の道具。
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

    /// `localizedInfoDictionary` を先に見る —— `infoDictionary` だけだと常に Base（zh-Hans）の
    /// 値になり、英語／日本語表示でも中国語名が出てしまう。
    var displayName: String? {
        return (localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (infoDictionary?["CFBundleDisplayName"] as? String)
    }

    var versionString: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
