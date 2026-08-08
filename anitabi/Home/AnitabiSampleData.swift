//
//  AnitabiSampleData.swift
//  anitabi
//
//  DEBUG 専用のサンプルデータ。起動引数 `-anitabiUseSampleData` を付けると
//  ネットワークの代わりにこれを読む。プレビューと、オフライン環境での
//  レイアウト確認（附近・検索・都市・作品ブラウズ）に使う。
//

#if DEBUG

import CoreLocation
import Foundation

enum AnitabiSampleData {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-anitabiUseSampleData")
    }

    /// 吉祥寺〜東京都心を中心にした小さなデータセット。
    static func dataset() -> AnitabiDataset {
        var bangumis: [BangumiLite] = []
        var points: [ScenePoint] = []

        for work in works {
            var geos: [PointGeo] = []
            for scene in work.scenes {
                geos.append(
                    PointGeo(id: scene.id, lat: scene.lat, lng: scene.lng, priority: scene.priority)
                )
                points.append(
                    ScenePoint(
                        id: scene.id,
                        bangumiID: work.id,
                        lat: scene.lat,
                        lng: scene.lng,
                        priority: scene.priority,
                        name: scene.name,
                        nameCN: scene.nameCN,
                        image: nil,
                        ep: scene.ep
                    )
                )
            }
            bangumis.append(
                BangumiLite(
                    id: work.id,
                    cn: work.cn,
                    title: work.title,
                    city: "日本",
                    colorHex: work.color,
                    cover: nil,
                    cat: "TV",
                    center: CLLocationCoordinate2D(
                        latitude: work.scenes[0].lat,
                        longitude: work.scenes[0].lng
                    ),
                    zoom: 13,
                    points: geos
                )
            )
        }

        return AnitabiDataset(
            bangumis: bangumis,
            points: points,
            modified: Date().timeIntervalSince1970 * 1000,
            modifiedByBangumi: Dictionary(
                uniqueKeysWithValues: bangumis.enumerated().map {
                    ($0.element.id, Double(1_700_000_000 + $0.offset * 86_400))
                }
            ),
            hasDetails: true
        )
    }

    // MARK: - 素材

    private struct SampleScene {
        let id: String
        let name: String
        let nameCN: String
        let lat: Double
        let lng: Double
        let ep: String?
        var priority: Int = 400
    }

    private struct SampleWork {
        let id: Int
        let cn: String
        let title: String
        let color: String
        let scenes: [SampleScene]
    }

    private static let works: [SampleWork] = [
        SampleWork(
            id: 344870, cn: "莉可丽丝", title: "リコリス・リコイル", color: "#d1495b",
            scenes: [
                SampleScene(id: "lyco1", name: "吉祥寺駅 北口", nameCN: "吉祥寺站 北口", lat: 35.7036, lng: 139.5800, ep: "3", priority: 900),
                SampleScene(id: "lyco2", name: "錦糸公園", nameCN: "锦丝公园", lat: 35.6968, lng: 139.8145, ep: "1"),
                SampleScene(id: "lyco3", name: "亀戸天神社", nameCN: "龟户天神社", lat: 35.6996, lng: 139.8206, ep: "8"),
                SampleScene(id: "lyco4", name: "旧岩崎邸庭園", nameCN: "旧岩崎邸庭园", lat: 35.7086, lng: 139.7663, ep: "5"),
            ]
        ),
        SampleWork(
            id: 302286, cn: "孤独摇滚！", title: "ぼっち・ざ・ろっく！", color: "#e87ea1",
            scenes: [
                SampleScene(id: "boc1", name: "井の頭恩賜公園 ボート乗り場", nameCN: "井之头恩赐公园 划船处", lat: 35.6999, lng: 139.5732, ep: "1", priority: 850),
                SampleScene(id: "boc2", name: "下北沢駅", nameCN: "下北泽站", lat: 35.6613, lng: 139.6680, ep: "2"),
                SampleScene(id: "boc3", name: "SHELTER 下北沢", nameCN: "下北泽 SHELTER", lat: 35.6620, lng: 139.6672, ep: "4"),
            ]
        ),
        SampleWork(
            id: 207195, cn: "摇曳露营△", title: "ゆるキャン△", color: "#3fa9a5",
            scenes: [
                SampleScene(id: "yuru1", name: "吉祥寺 ハーモニカ横丁", nameCN: "吉祥寺 口琴横丁", lat: 35.7043, lng: 139.5792, ep: "5", priority: 700),
                SampleScene(id: "yuru2", name: "本栖湖 浩庵キャンプ場", nameCN: "本栖湖 浩庵露营场", lat: 35.4664, lng: 138.5906, ep: "1"),
                SampleScene(id: "yuru3", name: "麓キャンプ場", nameCN: "麓露营场", lat: 35.4029, lng: 138.6169, ep: "9"),
            ]
        ),
        SampleWork(
            id: 1424, cn: "轻音少女", title: "けいおん！", color: "#b0673f",
            scenes: [
                SampleScene(id: "kon1", name: "豊郷小学校旧校舎群", nameCN: "丰乡小学旧校舍群", lat: 35.2065, lng: 136.2296, ep: "1"),
                SampleScene(id: "kon2", name: "京都 修学旅行ルート", nameCN: "京都 修学旅行路线", lat: 35.0116, lng: 135.7681, ep: "13"),
            ]
        ),
        SampleWork(
            id: 265, cn: "吹响吧！上低音号", title: "響け！ユーフォニアム", color: "#c9a227",
            scenes: [
                SampleScene(id: "eup1", name: "宇治橋", nameCN: "宇治桥", lat: 34.8917, lng: 135.8074, ep: "1"),
                SampleScene(id: "eup2", name: "京阪 宇治駅", nameCN: "京阪 宇治站", lat: 34.8909, lng: 135.8069, ep: "3"),
            ]
        ),
    ]
}

#endif
