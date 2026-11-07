import CoreLocation
import SwiftUI

@MainActor
final class MobileSkyLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinates: TodaySkyAstronomy.Coordinates?
    @Published private(set) var isLocating = false
    @Published private(set) var message: String?

    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private var requestStarted = false
    private static let storageKey = "mobile.skyCoordinates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.array(forKey: Self.storageKey) as? [Double], saved.count == 2,
           CLLocationCoordinate2DIsValid(.init(latitude: saved[0], longitude: saved[1])) {
            coordinates = .init(latitude: saved[0], longitude: saved[1])
        }
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    func update() {
        guard !isLocating else { return }
        isLocating = true
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: authorizationChanged()
        }
    }

    func useLocalTime() {
        manager.stopUpdatingLocation()
        isLocating = false
        requestStarted = false
        message = nil
        coordinates = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func authorizationChanged() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isLocating && !requestStarted {
                requestStarted = true
                manager.requestLocation()
            }
        case .denied, .restricted:
            useLocalTime()
            message = "如需按位置显示，可在系统设置中允许定位。"
        case .notDetermined: break
        @unknown default:
            isLocating = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            guard self.isLocating, self.requestStarted else { return }
            self.isLocating = false
            self.requestStarted = false
            guard let location, location.horizontalAccuracy >= 0,
                  CLLocationCoordinate2DIsValid(location.coordinate) else {
                self.message = "未能取得有效位置，可稍后重试。"
                return
            }
            let coordinates = TodaySkyAstronomy.Coordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.coordinates = coordinates
            self.defaults.set([coordinates.latitude, coordinates.longitude], forKey: Self.storageKey)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in
            guard self.isLocating, self.requestStarted else { return }
            self.isLocating = false
            self.requestStarted = false
            self.message = "暂时无法更新位置，可稍后重试。"
        }
    }
}
