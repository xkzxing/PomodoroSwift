import AppKit
import Combine
import CoreLocation

@MainActor
final class TodaySkyLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = TodaySkyLocation()

    @Published private(set) var coordinates: TodaySkyAstronomy.Coordinates?
    @Published private(set) var isLocating = false
    @Published private(set) var lastUpdateFailed = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var canUpdateLocation: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .notDetermined
    }

    private let makeManager: @MainActor () -> CLLocationManager
    private let isAppActive: @MainActor () -> Bool
    private let defaults: UserDefaults
    private let positionKey = "todaySkyCoarsePosition"
    private let initialRequestKey = "todaySkyInitialLocationRequested"
    private var manager: CLLocationManager?
    private var requestPending = false
    private var mayAskForAuthorization = false
    private var isAsking = false

    init(defaults: UserDefaults = .standard,
         makeManager: @escaping @MainActor () -> CLLocationManager = { CLLocationManager() },
         isAppActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }) {
        self.defaults = defaults
        self.makeManager = makeManager
        self.isAppActive = isAppActive
    }

    func setEnabled(_ enabled: Bool, askForAuthorization: Bool, permitsAuthorization: Bool = true) {
        guard enabled else {
            guard let manager else { return }
            manager.delegate = nil
            manager.stopUpdatingLocation()
            self.manager = nil
            coordinates = nil
            isLocating = false
            lastUpdateFailed = false
            requestPending = false
            mayAskForAuthorization = false
            isAsking = false
            return
        }
        if manager == nil {
            let manager = makeManager()
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            self.manager = manager
            requestPending = savedCoordinates == nil && !defaults.bool(forKey: initialRequestKey)
            manager.delegate = self
        }
        mayAskForAuthorization = permitsAuthorization && (mayAskForAuthorization || (requestPending && askForAuthorization))
        resumePendingRequest()
    }

    func updateLocation() {
        guard !isLocating else { return }
        requestPending = true
        mayAskForAuthorization = true
        resumePendingRequest()
    }

    func resumePendingRequest() {
        guard let manager else { return }
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways:
            if coordinates == nil { coordinates = savedCoordinates }
            guard requestPending, !isLocating, isAppActive() else { return }
            requestPending = false
            mayAskForAuthorization = false
            defaults.set(true, forKey: initialRequestKey)
            lastUpdateFailed = false
            isLocating = true
            manager.requestLocation()
        case .notDetermined:
            coordinates = nil
            guard requestPending, mayAskForAuthorization, !isAsking, isAppActive() else { return }
            mayAskForAuthorization = false
            isAsking = true
            manager.requestWhenInUseAuthorization()
        default:
            if isLocating { manager.stopUpdatingLocation() }
            isLocating = false
            lastUpdateFailed = false
            requestPending = false
            mayAskForAuthorization = false
            coordinates = nil
            defaults.removeObject(forKey: positionKey)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }
        if manager.authorizationStatus != .notDetermined { isAsking = false }
        resumePendingRequest()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager, isLocating, manager.authorizationStatus == .authorizedAlways else { return }
        isLocating = false
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate),
              abs(location.timestamp.timeIntervalSinceNow) < 3_600 else {
            lastUpdateFailed = true
            return
        }
        let coordinate = location.coordinate
        // Save only the rounded pair, together, so the theme can reuse it across launches.
        let rounded = TodaySkyAstronomy.Coordinates(latitude: (coordinate.latitude * 10).rounded() / 10,
                                                     longitude: (coordinate.longitude * 10).rounded() / 10)
        defaults.set([rounded.latitude, rounded.longitude], forKey: positionKey)
        coordinates = rounded
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager, isLocating else { return }
        isLocating = false
        lastUpdateFailed = true
    }

    private var savedCoordinates: TodaySkyAstronomy.Coordinates? {
        guard let pair = defaults.array(forKey: positionKey) as? [Double], pair.count == 2,
              CLLocationCoordinate2DIsValid(.init(latitude: pair[0], longitude: pair[1])) else { return nil }
        return .init(latitude: pair[0], longitude: pair[1])
    }
}
