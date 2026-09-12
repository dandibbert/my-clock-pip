import XCTest
@testable import ClockCore

final class ClockCoreTests: XCTestCase {
    func testMillisecondsAndMidnight() {
        XCTAssertEqual(ClockDigits(epoch: 86_399.9994, secondsFromGMT: 0).main, "23:59:59")
        XCTAssertEqual(ClockDigits(epoch: 86_399.9994, secondsFromGMT: 0).fraction, ".999")
        XCTAssertEqual(ClockDigits(epoch: 86_400, secondsFromGMT: 0).main, "00:00:00")
    }
    func testTimezoneAndNegativeEpoch() {
        XCTAssertEqual(ClockDigits(epoch: 0, secondsFromGMT: 28_800).main, "08:00:00")
        XCTAssertEqual(ClockDigits(epoch: -0.001, secondsFromGMT: 0).fraction, ".999")
        XCTAssertEqual(ClockDigits(epoch: 0, secondsFromGMT: -18_000).main, "19:00:00")
    }
    func testCountdownDoesNotReachZeroEarly() {
        XCTAssertEqual(Countdown.milliseconds(target: 1, now: 0.9999), 1)
        XCTAssertEqual(Countdown.milliseconds(target: 1, now: 1), 0)
        XCTAssertEqual(Countdown.milliseconds(target: 1, now: 2), 0)
        XCTAssertEqual(Countdown.text(milliseconds: 3_661_234), "01:01:01.234")
        XCTAssertEqual(Countdown.text(milliseconds: 60_001), "01:00.001")
    }
    private let base = 1_800_000_000.0
    private func reply(at time: Double? = nil) -> ([UInt8], [UInt8], Double) {
        let t = time ?? base
        let request = SNTP.request(at: t)
        var response = [UInt8](repeating: 0, count: 48)
        response[0] = 0x24; response[1] = 2
        response.replaceSubrange(24..<32, with: request[40..<48])
        response.replaceSubrange(32..<40, with: SNTP.timestamp(t + 0.12))
        response.replaceSubrange(40..<48, with: SNTP.timestamp(t + 0.13))
        return (request, response, t)
    }
    private func parse(_ response: [UInt8], request: [UInt8], at time: Double? = nil) throws -> TimeSample {
        let t = time ?? base
        return try SNTP.parse(response, request: request, sent: t, received: t + 0.05, continuous: 50, host: "test")
    }
    func testFourTimestampCalculation() throws {
        let (q, r, _) = reply()
        let result = try parse(r, request: q)
        XCTAssertEqual(result.offset, 0.1, accuracy: 0.000001)
        XCTAssertEqual(result.delay, 0.04, accuracy: 0.000001)
        XCTAssertEqual(result.epochAtReceive, base + 0.15, accuracy: 0.000001)
    }
    func testNTP2036EraRollover() throws {
        let time = 2_100_000_000.0
        let (q, r, _) = reply(at: time)
        XCTAssertEqual(try parse(r, request: q, at: time).offset, 0.1, accuracy: 0.000001)
    }
    func testTruncatedPacket() {
        XCTAssertThrowsError(try parse([0x24], request: SNTP.request(at: base)))
    }
    func testInvalidOrigin() {
        let (q, response, _) = reply(); var r = response; r[24] ^= 1
        XCTAssertThrowsError(try parse(r, request: q))
    }
    func testKissOfDeathAndUnsynchronized() {
        let (q, response, _) = reply(); var r = response; r[1] = 0
        XCTAssertThrowsError(try parse(r, request: q))
        r = response; r[0] |= 0xC0
        XCTAssertThrowsError(try parse(r, request: q))
    }
    func testInvalidModeAndVersion() {
        let (q, response, _) = reply()
        for header: UInt8 in [0x23, 0x25, 0x14] {
            var r = response; r[0] = header
            XCTAssertThrowsError(try parse(r, request: q))
        }
    }
    func testMissingTimestampsAndExcessiveDelay() {
        let (q, response, _) = reply(); var r = response
        r.replaceSubrange(40..<48, with: [UInt8](repeating: 0, count: 8))
        XCTAssertThrowsError(try parse(r, request: q))
        XCTAssertThrowsError(try SNTP.parse(response, request: q, sent: base, received: base + 4, continuous: 50, host: "test"))
    }
    private func sample(_ host: String = "a", offset: Double = 0.1, delay: Double = 0.02) -> TimeSample {
        TimeSample(host: host, offset: offset, delay: delay, uncertainty: delay / 2, epochAtReceive: 100 + offset, continuousAtReceive: 10)
    }
    func testSelectRequiresIndependentAgreement() throws {
        XCTAssertThrowsError(try SNTP.select([sample()]))
        XCTAssertThrowsError(try SNTP.select([sample(), sample("b", offset: 2)]))
        XCTAssertThrowsError(try SNTP.select([sample(), sample()]))
        XCTAssertEqual(try SNTP.select([sample("a", delay: 0.08), sample("b"), sample("c", offset: 4)]).host, "b")
    }
    func testMonotonicAnchorIgnoresWallClockChange() {
        let clock = PreciseClock(); clock.calibrate(sample())
        XCTAssertEqual(clock.reading(network: true, system: 999, continuous: 11).epoch, 101.1, accuracy: 0.000001)
        XCTAssertEqual(clock.reading(network: true, offsetMilliseconds: -123, system: 999, continuous: 11).epoch, 100.977, accuracy: 0.000001)
    }
    func testExpiryAndDisabledNetworkFallback() {
        let clock = PreciseClock(); clock.calibrate(sample())
        XCTAssertFalse(clock.reading(network: true, system: 999, continuous: 910).network)
        XCTAssertEqual(clock.reading(network: false, system: 999, continuous: 11).epoch, 999)
        XCTAssertFalse(clock.reading(network: true, system: 999, continuous: 9).network)
        clock.reset()
        XCTAssertFalse(clock.reading(network: true, system: 999, continuous: 11).network)
    }
    func testNoCalibrationUsesSystem() {
        XCTAssertEqual(PreciseClock().reading(network: true, offsetMilliseconds: 234, system: 10).epoch, 10.234, accuracy: 0.000001)
    }
}
