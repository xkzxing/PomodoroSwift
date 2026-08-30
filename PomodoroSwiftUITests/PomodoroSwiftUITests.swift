import XCTest

final class PomodoroSwiftUITests: XCTestCase {
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        app.terminate()
    }
}
