//
//  LocationProvider.swift
//  anitabi
//
//  位置情報。使い道は「距我 x km」の表示・附近の再計算（50m 動いてから）・検索の並び順だけで、
//  経路の記録はしていない —— なので**百 m 級の粗い測位で足りる**。粗くすると CoreLocation は
//  GPS チップを常時焚かずに Wi-Fi／基地局測位へ落とせるので、実機の発熱・電池がまるで違う。
//  地図の青い現在地点は MKMapView が自前で測るのでここの精度とは無関係。
//

import CoreLocation
import Observation

@MainActor
@Observable
final class LocationProvider: NSObject {
    /// 未取得なら nil。UI 側は nil を「定位なし」状態として扱う。
    private(set) var location: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    /// 「附近」の再計算は移動量で間引く。連続更新のたびに 5 万点を走査しない。
    private var lastRecomputeLocation: CLLocation?
    static let recomputeThreshold: CLLocationDistance = 50

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // 精度は附近再計算の閾値（50m）に合わせる —— それより細かく届いても捨てるだけ。
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = Self.recomputeThreshold
        // 静止していたら配信ごと止めてもらう（動き出せば系统が起こしてくれる）。
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        default:
            break  // 拒否済み。設定アプリへの導線は呼び出し側が出す。
        }
    }

    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    /// 前回の再計算地点から十分動いたか。
    func shouldRecomputeNearby(for new: CLLocation) -> Bool {
        guard let last = lastRecomputeLocation else { return true }
        return new.distance(from: last) >= Self.recomputeThreshold
    }

    func markNearbyRecomputed(at location: CLLocation) {
        lastRecomputeLocation = location
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.location = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 位置が取れないことは通常運転（屋内・機内モードなど）。UI は「定位なし」状態で成立する。
    }
}
