import XCTest

final class LiveContainerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompatibilityModeEntersCleanClockStage() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--force-livecontainer"]
        app.launch()

        XCTAssertTrue(app.staticTexts["LiveContainer 兼容模式"].waitForExistence(timeout: 10))
        let button = app.buttons["lcDisplayButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.otherElements["lcDisplayStage"].waitForExistence(timeout: 5))
    }
}
