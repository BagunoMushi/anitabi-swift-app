//
//  AppRouter.swift
//  anitabi
//
//  ナビゲーション状態の唯一の持ち主。Web 版の履歴操作をそのまま型にしてある（`setBangumi`
//  → `focusWork`、`setPopup` → `selectPoint`、`back()` → `closePointCard`/`backToBrowse`）。
//  カメラ指令だけは経路で挙動が変わるので RootView が持つ（一覧から＝寄る／地図から＝動かない）。
//

import CoreLocation
import Observation
import SwiftUI

// MARK: - 呈现の単位

struct WorkSelection: Identifiable, Equatable {
    let id: Int
}

struct PointSelection: Identifiable, Equatable {
    let id: String
    let bangumiID: Int
}

/// 対比撮影（`SceneComparisonView`）の入口。
struct CameraSession: Identifiable {
    let id = UUID()
    /// 原寸のスクリーンショット URL（plan 変換を掛けない生の画像）
    let photoURL: URL
    let name: String
    let themeHex: String?
    /// "lat,lng" 形式。成片の右下に焼き込まれる。
    let location: String
}

struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String?
}

/// 長押しで落とす針（`DroppedPinSheet` が受ける）。
struct DroppedPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Router

@MainActor
@Observable
final class AppRouter {

    // MARK: 呈现スタック

    var workCard: WorkSelection?
    var pointCard: PointSelection?
    var cameraSession: CameraSession?
    var photoViewer: PhotoViewerItem?
    var droppedPin: DroppedPin?

    /// chips による複数作品フィルタ（Web の `bids`）。作品モードとは排他。
    var selectedWorkIDs: Set<Int> = []

    /// 地図が最後に静止した位置。視口 chips の集計と状態復元が読む。
    var cameraState: MapCameraState?

    /// 画面上部の一時通知。router 経由にしておけば、`@Bindable var router` を既に持っている
    /// カードから素通しで呼べる。
    let toast = ToastCenter()

    /// 「重看欢迎页」のフラグ。`RootView` が拾って `fullScreenCover` を開き、自分で戻す
    /// （`hasCompletedOnboarding` は変えない —— 既読のまま「もう一度見る」だけ）。
    var wantsWelcomeReplay = false

    // MARK: 地図への投影

    var focusedWorkID: Int? { workCard?.id }
    var selectedPointID: String? { pointCard?.id }

    // MARK: 遷移

    /// 作品モードへ入る（web `setBangumiNoFly`）。カメラ移動は呼び出し側の担当。
    /// 複数作品フィルタは畳む —— 作品モードと chips が同時に効くと
    /// 地図の「何を出すか」が二重定義になる。
    func focusWork(id: Int) {
        guard workCard?.id != id || pointCard != nil else { return }
        pointCard = nil
        // 既に同じ作品のカードが下に居るなら、そこへ戻るだけ（呈现も镜头も動かさない）。
        guard workCard?.id != id else { return }
        selectedWorkIDs = []
        workCard = WorkSelection(id: id)
    }

    /// 地標を選ぶ（web `setPopup`）。
    func selectPoint(_ point: ScenePoint) {
        pointCard = PointSelection(id: point.id, bangumiID: point.bangumiID)
    }

    /// 地標カードを閉じる（web `back()` 1 段）。上に作品カードが居ればそこへ戻る。
    func closePointCard() {
        pointCard = nil
    }

    /// 作品カードを閉じる。子の地標カードも一緒に落とす。
    func closeWorkCard() {
        pointCard = nil
        workCard = nil
    }

    /// Browse へ戻す（作品カードの✕・圧暗部タップ）。フィルタも全部解く。
    func backToBrowse() {
        pointCard = nil
        workCard = nil
        selectedWorkIDs = []
    }

    /// chips の切り替え。作品モード中は解除してから効かせる。
    func toggleWorkFilter(id: Int) {
        workCard = nil
        pointCard = nil
        if selectedWorkIDs.contains(id) {
            selectedWorkIDs.remove(id)
        } else {
            selectedWorkIDs.insert(id)
        }
    }

    func clearWorkFilter() {
        selectedWorkIDs = []
    }

    /// 長押しで針を落とす。地標／作品カードは先に畳む —— 長押しは「今のカードから離れて
    /// 新しい場所を見る」操作なので、針を閉じたら元のカードではなく Browse へ戻るのが素直。
    func dropPin(at coordinate: CLLocationCoordinate2D) {
        pointCard = nil
        workCard = nil
        droppedPin = DroppedPin(coordinate: coordinate)
    }
}
