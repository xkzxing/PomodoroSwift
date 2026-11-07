import CoreLocation
import XCTest
@testable import PomodoroSwift

@MainActor
final class TodaySkyLocationTests: XCTestCase {
    func testSavedPositionSurvivesRelaunchAndOnlyManualRequestsReplaceIt() {
        withDefaults { defaults in
            let manager = LocationManagerStub()
            manager.status = .authorizedAlways
            let first = TodaySkyLocation(defaults: defaults, makeManager: { manager }, isAppActive: { true })
            first.setEnabled(true, askForAuthorization: true)
            XCTAssertEqual(manager.positionRequests, 1)
            first.locationManager(manager, didUpdateLocations: [fix(40.73, -73.98)])
            first.resumePendingRequest()
            XCTAssertEqual(manager.positionRequests, 1)
            first.setEnabled(false, askForAuthorization: false)

            let next = TodaySkyLocation(defaults: defaults, makeManager: { manager }, isAppActive: { true })
            next.setEnabled(true, askForAuthorization: false)
            next.resumePendingRequest()
            XCTAssertEqual(manager.positionRequests, 1)
            XCTAssertEqual(next.coordinates, .init(latitude: 40.7, longitude: -74))

            next.updateLocation()
            XCTAssertEqual(manager.positionRequests, 2)
            next.locationManager(manager, didFailWithError: CLError(.locationUnknown))
            XCTAssertTrue(next.lastUpdateFailed)
            XCTAssertEqual(next.coordinates, .init(latitude: 40.7, longitude: -74))
            next.updateLocation()
            next.locationManager(manager, didUpdateLocations: [fix(47.61, -122.33)])
            XCTAssertFalse(next.lastUpdateFailed)
            XCTAssertEqual(next.coordinates, .init(latitude: 47.6, longitude: -122.3))
            manager.status = .denied
            next.locationManagerDidChangeAuthorization(manager)
            XCTAssertNil(next.coordinates)
            XCTAssertFalse(next.canUpdateLocation)
            manager.status = .authorizedAlways
            next.locationManagerDidChangeAuthorization(manager)
            XCTAssertNil(next.coordinates)
            XCTAssertEqual(manager.positionRequests, 3)
        }
    }

    func testInitialRequestWaitsForForegroundAndDisablingIgnoresLateResults() {
        withDefaults { defaults in
            let manager = LocationManagerStub()
            var isActive = false
            let location = TodaySkyLocation(defaults: defaults, makeManager: { manager }, isAppActive: { isActive })
            location.setEnabled(true, askForAuthorization: true)
            XCTAssertEqual(manager.authorizationRequests, 0)
            XCTAssertEqual(manager.positionRequests, 0)

            isActive = true
            location.resumePendingRequest()
            XCTAssertEqual(manager.authorizationRequests, 1)
            manager.status = .authorizedAlways
            location.locationManagerDidChangeAuthorization(manager)
            XCTAssertEqual(manager.positionRequests, 1)
            location.setEnabled(false, askForAuthorization: false)
            location.locationManager(manager, didUpdateLocations: [fix(40.73, -73.98)])
            XCTAssertEqual(manager.stopRequests, 1)
            XCTAssertNil(location.coordinates)
            location.setEnabled(true, askForAuthorization: true)
            XCTAssertEqual(manager.positionRequests, 1)
        }
    }

    func testBackgroundCanShareLocationWithoutInheritingTodaysPermissionPrompt() {
        withDefaults { defaults in
            let manager = LocationManagerStub()
            var isActive = false
            let location = TodaySkyLocation(defaults: defaults, makeManager: { manager }, isAppActive: { isActive })
            location.setEnabled(true, askForAuthorization: true)

            // The background stays enabled after the Today sky theme is turned off.
            location.setEnabled(true, askForAuthorization: false, permitsAuthorization: false)
            isActive = true
            location.resumePendingRequest()
            XCTAssertEqual(manager.authorizationRequests, 0)
            XCTAssertNil(location.coordinates)

            manager.status = .authorizedAlways
            location.locationManagerDidChangeAuthorization(manager)
            XCTAssertEqual(manager.positionRequests, 1)
            location.locationManager(manager, didUpdateLocations: [fix(40.73, -73.98)])
            XCTAssertEqual(location.coordinates, .init(latitude: 40.7, longitude: -74))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "TodaySkyLocationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    private func fix(_ latitude: Double, _ longitude: Double) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: longitude),
                   altitude: 0, horizontalAccuracy: 3_000, verticalAccuracy: -1, timestamp: .now)
    }
}

private final class LocationManagerStub: CLLocationManager {
    var status: CLAuthorizationStatus = .notDetermined
    var authorizationRequests = 0
    var positionRequests = 0
    var stopRequests = 0

    override var authorizationStatus: CLAuthorizationStatus { status }
    override func requestWhenInUseAuthorization() { authorizationRequests += 1 }
    override func requestLocation() { positionRequests += 1 }
    override func stopUpdatingLocation() { stopRequests += 1 }
}
