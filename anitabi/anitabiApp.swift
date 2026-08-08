//
//  anitabiApp.swift
//  anitabi
//
//  Created by 维安雨轩 on 2025/05/11.
//

import SwiftUI
import UIKit

// MARK: - 画面ごとの向き制御
/// 通常はポートレート＋横向きを許可（従来どおり）。対比拍摄画面のような特定画面が
/// 一時的に `orientationLock` を上書きし、離脱時に戻す。
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

@main
struct anitabiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // ネイティブ首屏（AnitabiDataLoader）が `URLSession.data(from:)` で取得する
        // g*.json / users.csv / bangumi-icons.json 用。専用ディスクキャッシュ
        // （`anitabi-data`）とは別に、URLSession レベルのキャッシュも底上げしておく。
        URLCache.shared = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            // ネイティブ再構築版の首屏。旧 WebView 版に戻したいときは `ContentView()` に差し替える
            // （ContentView.swift 以下の WebView 一式はそのまま残してある）。
            MapHomeView()
        }
    }
}
