import XCTest

final class ClockUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch(); return app
    }
    func testHomeAndHelp() {
        let app = launch()
        XCTAssertTrue(app.buttons["pipButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["悬刻"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["使用说明"].tap()
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["pipButton"].exists)
    }
    func testEditTargetAndAdvancedSettings() {
        let app = launch()
        let edit = app.buttons["editTarget"]
        for _ in 0..<3 { if edit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 3)); edit.tap()
        XCTAssertTrue(app.buttons["saveTarget"].waitForExistence(timeout: 3))
        app.buttons["saveTarget"].tap()
        let advanced = app.buttons["advanced"]
        for _ in 0..<4 { if advanced.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(advanced.isHittable); advanced.tap()
        XCTAssertTrue(app.navigationBars["时间与精度"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
    }
}
