import XCTest
@testable import MyClockPiP

final class LiveContainerRuntimeTests: XCTestCase {
    func testDetectsLiveContainerHomePath() {
        XCTAssertTrue(LiveContainerRuntime.detect(environment: ["LC_HOME_PATH": "/tmp/lc"], arguments: []))
    }

    func testDetectsLiveProcessHomePath() {
        XCTAssertTrue(LiveContainerRuntime.detect(environment: ["LP_HOME_PATH": "/tmp/lp"], arguments: []))
    }

    func testNormalInstallIsNotDetected() {
        XCTAssertFalse(LiveContainerRuntime.detect(environment: ["HOME": "/var/mobile"], arguments: []))
    }

    func testArgumentsCanForceAndDisableDetection() {
        XCTAssertTrue(LiveContainerRuntime.detect(environment: [:], arguments: ["--force-livecontainer"]))
        XCTAssertFalse(LiveContainerRuntime.detect(environment: ["LC_HOME_PATH": "/tmp/lc"], arguments: ["--disable-livecontainer"]))
    }
}
