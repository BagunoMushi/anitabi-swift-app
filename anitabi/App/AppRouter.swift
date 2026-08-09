//
//  AppRouter.swift
//  anitabi
//
//  ============================================================================
//  AppRouter —— ナビゲーション状態の唯一の持ち主
//  ============================================================================
//
//  Web 版（anitabi.cn/map）の履歴操作をそのまま型にしたもの。対応はこう：
//
//  | Web | ここ |
//  |---|---|
//  | `setBangumi` / `setBangumiNoFly` | `focusWork(id:)` |
//  | `setPopup` | `selectPoint(_:)` |
//  | `back()`（1 段） | `closePointCard()` |
//  | `back()`（作品まで戻る・圧暗部タップ） | `backToBrowse()` |
//  | `bids`（複数作品フィルタ） | `selectedWorkIDs` |
//
//  地図（MapCanvas）と sheet は**自分では状態を持たない**。ここを読んで描き、
//  操作はここへ投げ返す。カメラ指令だけは「どの経路で選んだか」で挙動が変わるので
//  RootView が持つ（一覧から選ぶ＝寄る／地図で選ぶ＝動かない）。
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

/// 対比撮影の入口（阶段 6 で `SceneComparisonView` の既存 4 引数 init へ 1:1 で渡す）。
struct CameraSession: Identifiable {
    let id = UUID()
    /// 原寸のスクリーンショット URL（plan 変換を掛けない生の画像）
    let photoURL: URL
    let name: String
    let themeHex: String?
    /// "lat,lng" 形式。既存 init の引数形式に合わせてある。
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

/// 長押しで落とす針（阶段 7 で DroppedPinSheet が受ける）。
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
    var safariItem: SafariItem?
    var photoViewer: PhotoViewerItem?
    var droppedPin: DroppedPin?

    /// chips による複数作品フィルタ（Web の `bids`）。作品モードとは排他。
    var selectedWorkIDs: Set<Int> = []

    /// 地図が最後に静止した位置。視口 chips の集計と状態復元（阶段 8）が読む。
    var cameraState: MapCameraState?

    /// 画面上部の一時通知（阶段 7）。router 経由にしておけば、`@Bindable var router` を
    /// 既に持っている全カード（PointCardSheet 等）から素通しで呼べる。
    let toast = ToastCenter()

    /// HomeSheet の「⋯」メニュー「重看欢迎页」から立てるフラグ（阶段 8）。`RootView` が
    /// `.onChange` で拾って `fullScreenCover` を開き、自分で `false` に戻す
    /// （`hasCompletedOnboarding` は変えない——既読状態はそのまま、単なる「もう一度見る」）。
    var wantsWelcomeReplay = false

    // MARK: 地図への投影

    var focusedWorkID: Int? { workCard?.id }
    var selectedPointID: String? { pointCard?.id }
    /// カードが 1 枚も無い状態（＝Browse）。
    var isBrowsing: Bool { workCard == nil && pointCard == nil }

    // MARK: 遷移

    /// 作品モードへ入る（web `setBangumiNoFly`）。カメラ移動は呼び出し側の担当。
    /// 複数作品フィルタは畳む —— 作品モードと chips が同時に効くと
    /// 地図の「何を出すか」が二重定義になる。
    func focusWork(id: Int) {
        guard workCard?.id != id || pointCard != nil else { return }
        // 呈现が 1 枚の sheet の中身の差し替えになったので、dismiss + present の競合が無い。
        // 地標カードが乗っていても同じフレームで畳んで差し替えてよい
        // （旧・`pendingWork` に預けて `onDismiss` で受け取る 2 段構えは不要になった）。
        pointCard = nil
        // 既に同じ作品のカードが下に居るなら、そこへ戻るだけ（呈现も镜头も動かさない）。
        guard workCard?.id != id else { return }
        selectedWorkIDs = []
        workCard = WorkSelection(id: id)
    }

    /// 地標カードの作品 chip から作品カードへ。単 sheet では `focusWork` と同義だが、
    /// 「地標カードを畳んで作品へ渡す」という意図が呼び出し側で読めるよう名前は残す。
    func handOffToWork(id: Int) {
        focusWork(id: id)
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

    /// chips の切り替え（阶段 7）。作品モード中は解除してから効かせる。
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

    /// 長押しで針を落とす。地標／作品カードは先に畳む —— 地図の見える部分への長押しは
    /// 「今のカードから離れて新しい場所を見る」操作なので、針のカードを閉じたら
    /// 元のカードではなく Browse（＝検索 sheet）へ戻るのが素直
    /// （呈现側は 1 枚 sheet なので、重ねること自体は技術的には可能になった）。
    func dropPin(at coordinate: CLLocationCoordinate2D) {
        pointCard = nil
        workCard = nil
        droppedPin = DroppedPin(coordinate: coordinate)
    }
}
