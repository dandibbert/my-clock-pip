import XCTest
import AVFoundation
@testable import MyClockPiP

final class RendererTests: XCTestCase {
    private func reading(_ epoch: Double) -> ClockReading {
        PreciseClock().reading(network: false, system: epoch)
    }
    func testAllLayoutsProduceCorrectPixelDimensions() throws {
        for layout in ClockLayout.allCases {
            let renderer = try FrameRenderer(layout: layout)
            var settings = ClockSettings(); settings.layout = layout
            let frame = try XCTUnwrap(renderer.makeFrame(settings: settings, reading: reading(1_800_000_000), paused: false))
            let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(frame))
            XCTAssertEqual(CVPixelBufferGetWidth(image), layout.width)
            XCTAssertEqual(CVPixelBufferGetHeight(image), layout.height)
            XCTAssertTrue(CMSampleBufferIsValid(frame))
        }
    }
    private func fingerprint(_ sample: CMSampleBuffer) throws -> UInt64 {
        let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to: UInt8.self)
        let count = CVPixelBufferGetBytesPerRow(image) * CVPixelBufferGetHeight(image)
        return stride(from: 0, to: count, by: 17).reduce(UInt64(0)) { ($0 &* 31) &+ UInt64(bytes[$1]) }
    }
    func testMillisecondsActuallyChangeRenderedPixels() throws {
        let renderer = try FrameRenderer(layout: .strip)
        let a = try XCTUnwrap(renderer.makeFrame(settings: ClockSettings(), reading: reading(1_800_000_000.123), paused: false))
        let b = try XCTUnwrap(renderer.makeFrame(settings: ClockSettings(), reading: reading(1_800_000_000.789), paused: false))
        XCTAssertNotEqual(try fingerprint(a), try fingerprint(b))
    }
    func testPausedFrameHidesTheTimestamp() throws {
        let renderer = try FrameRenderer(layout: .strip)
        let a = try XCTUnwrap(renderer.makeFrame(settings: ClockSettings(), reading: reading(1_800_000_000), paused: true))
        let b = try XCTUnwrap(renderer.makeFrame(settings: ClockSettings(), reading: reading(1_800_000_900), paused: true))
        XCTAssertEqual(try fingerprint(a), try fingerprint(b))
        let live = try XCTUnwrap(renderer.makeFrame(settings: ClockSettings(), reading: reading(1_800_000_000), paused: false))
        XCTAssertNotEqual(try fingerprint(a), try fingerprint(live))
    }
    func testCountdownAndEveryThemeRender() throws {
        let renderer = try FrameRenderer(layout: .strip)
        for theme in ClockTheme.allCases {
            for delta in [-10.0, 0, 0.001, 3, 3600] {
                try autoreleasepool {
                    var settings = ClockSettings(); settings.theme = theme; settings.countdownEnabled = true
                    settings.target = Date(timeIntervalSince1970: 1_800_000_000 + delta)
                    XCTAssertNotNil(try renderer.makeFrame(settings: settings, reading: reading(1_800_000_000), paused: false))
                }
            }
        }
    }
    func testPoolBackpressureIsBounded() throws {
        let renderer = try FrameRenderer(layout: .strip)
        var held: [CMSampleBuffer] = []
        for _ in 0..<6 {
            held.append(try XCTUnwrap(renderer.makeFrame(settings: ClockSettings(), reading: reading(10), paused: false)))
        }
        XCTAssertNil(try renderer.makeFrame(settings: ClockSettings(), reading: reading(11), paused: false))
        XCTAssertEqual(held.count, 6)
    }
}
