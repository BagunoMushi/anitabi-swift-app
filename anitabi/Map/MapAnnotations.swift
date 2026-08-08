//
//  MapAnnotations.swift
//  anitabi
//
//  地図に載る 2 種類の標注モデル。表示に必要な値（テーマ色・優先度・形態）は
//  生成時に解決してここに固めておく ―― 標注ビューは再利用で使い回されるので、
//  ビュー側にデータ由来の状態を残さないため。
//

import CoreLocation
import MapKit
import UIKit

/// 地標の形態。同じビューの中で morph する（別クラスに分けるとズーム跨ぎで再生成が起きる）。
enum PointMarkerForm: Equatable {
    /// 主題点。
    case dot
    /// 劇照サムネイル標（尾の先端が座標）。
    case photo
    /// 選択中の気球。
    case balloon
}

final class ScenePointAnnotation: NSObject, MKAnnotation {
    let point: ScenePoint
    let coordinate: CLLocationCoordinate2D
    let themeColor: UIColor
    /// 白に近いテーマ色は白描边と同化するので内側にも細い暗線を入れる。
    let needsInnerOutline: Bool
    let displayPriority: MKFeatureDisplayPriority

    /// エンジンが決めた素の形態（`.dot` / `.photo`）。
    var plannedForm: PointMarkerForm = .dot
    /// 選択は素の形態と直交する（選択が解けたら元の形態へ戻る）。
    var isSelected = false

    /// 実際に描く形態。
    var form: PointMarkerForm { isSelected ? .balloon : plannedForm }

    var id: String { point.id }

    init(point: ScenePoint, themeColor: UIColor) {
        self.point = point
        self.coordinate = point.coordinate
        self.themeColor = themeColor
        self.needsInnerOutline = themeColor.needsDarkInnerOutline
        self.displayPriority = MKFeatureDisplayPriority(
            rawValue: MapRevealLadder.displayPriority(forPriority: point.priority)
        )
        super.init()
    }

    /// タイトルは返さない。標注の文字は自前で描く（MapKit の callout は使わない）。
    var title: String? { nil }
}

final class WorkAnnotation: NSObject, MKAnnotation {
    let bangumiID: Int
    let coordinate: CLLocationCoordinate2D
    let name: String
    let themeColor: UIColor
    let hasIcon: Bool

    init(seed: MapWorkSeed) {
        self.bangumiID = seed.id
        self.coordinate = seed.coordinate
        self.name = seed.name
        self.themeColor = seed.colorHex.flatMap { UIColor(cssHex: $0) } ?? .anitabiNeutralTheme
        self.hasIcon = seed.hasIcon
        // 表示優先度は持たない。作品標の間引きは `MapEngine.declutter` が画面座標で済ませており、
        // ここまで来た標注は必ず出す（MapKit に再判定させると底図ラベルに負けて消える）。
        super.init()
    }

    var title: String? { nil }
}
