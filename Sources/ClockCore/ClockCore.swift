import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Includes device sleep on Apple platforms. Never accumulate timer intervals.
public enum ContinuousSeconds {
    #if canImport(Darwin)
    private static let scale: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    #endif
    public static var now: Double {
        #if canImport(Darwin)
        return Double(mach_continuous_time()) * scale
        #else
        return ProcessInfo.processInfo.systemUptime
        #endif
    }
}

public struct ClockDigits: Equatable {
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let milliseconds: Int
    public init(epoch: Double, secondsFromGMT: Int) {
        // Floor the total once, so second and millisecond fields cannot disagree.
        let total = Int64(floor(epoch * 1000)) + Int64(secondsFromGMT) * 1000
        let day = ((total % 86_400_000) + 86_400_000) % 86_400_000
        hours = Int(day / 3_600_000)
        minutes = Int((day / 60_000) % 60)
        seconds = Int((day / 1000) % 60)
        milliseconds = Int(day % 1000)
    }
    public var main: String { String(format: "%02d:%02d:%02d", hours, minutes, seconds) }
    public var fraction: String { String(format: ".%03d", milliseconds) }
}

public enum Countdown {
    /// Ceil before the deadline: never announce zero early.
    public static func milliseconds(target: Double, now: Double) -> Int64 {
        Int64(ceil(max(0, target - now) * 1000))
    }
    public static func text(milliseconds: Int64) -> String {
        let n = max(0, milliseconds)
        let hours = n / 3_600_000
        if hours > 0 {
            return String(format: "%02lld:%02lld:%02lld.%03lld", hours, n / 60_000 % 60, n / 1000 % 60, n % 1000)
        }
        return String(format: "%02lld:%02lld.%03lld", n / 60_000, n / 1000 % 60, n % 1000)
    }
}

public struct TimeSample: Sendable {
    public let host: String
    public let offset: Double
    public let delay: Double
    public let uncertainty: Double
    public let epochAtReceive: Double
    public let continuousAtReceive: Double
    public init(host: String, offset: Double, delay: Double, uncertainty: Double, epochAtReceive: Double, continuousAtReceive: Double) {
        self.host = host; self.offset = offset; self.delay = delay
        self.uncertainty = uncertainty; self.epochAtReceive = epochAtReceive
        self.continuousAtReceive = continuousAtReceive
    }
}

public enum TimeValidationError: Error, LocalizedError {
    case invalidPacket, unsynchronized, mismatchedOrigin, unreasonableDelay, inconsistentServers
    public var errorDescription: String? {
        switch self {
        case .invalidPacket: return "时间服务器返回了无效数据"
        case .unsynchronized: return "时间服务器未同步或暂不接受请求"
        case .mismatchedOrigin: return "时间响应与本次请求不匹配"
        case .unreasonableDelay: return "网络延迟过大，本次校时已舍弃"
        case .inconsistentServers: return "多个时间源差异过大，请稍后重试"
        }
    }
}

/// Minimal SNTP v4 codec. This is not an authenticated NTS implementation.
public enum SNTP {
    private static let epochOffset = 2_208_988_800.0
    private static let era = 4_294_967_296.0
    public static func timestamp(_ unix: Double) -> [UInt8] {
        let value = unix + epochOffset
        let seconds = UInt32(truncatingIfNeeded: UInt64(floor(value)))
        let fraction = UInt32(min(era - 1, max(0, (value - floor(value)) * era)))
        return bytes(seconds) + bytes(fraction)
    }
    private static func bytes(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
    }
    private static func word(_ data: [UInt8], _ index: Int) -> UInt32 {
        data[index..<index + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private static func decode(_ data: [UInt8], _ index: Int, near reference: Double) -> Double {
        let base = Double(word(data, index)) - epochOffset + Double(word(data, index + 4)) / era
        return base + ((reference - base) / era).rounded() * era
    }
    public static func request(at unix: Double) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 48)
        packet[0] = 0x23 // LI=0, version=4, client mode=3.
        packet.replaceSubrange(40..<48, with: timestamp(unix))
        return packet
    }
    public static func parse(_ packet: [UInt8], request: [UInt8], sent: Double, received: Double, continuous: Double, host: String) throws -> TimeSample {
        guard packet.count >= 48, request.count == 48,
              packet[0] & 7 == 4, [3, 4].contains(Int((packet[0] >> 3) & 7)) else {
            throw TimeValidationError.invalidPacket
        }
        guard packet[0] >> 6 != 3, (1...15).contains(packet[1]) else { throw TimeValidationError.unsynchronized }
        guard packet[24..<32].elementsEqual(request[40..<48]) else { throw TimeValidationError.mismatchedOrigin }
        guard packet[32..<40].contains(where: { $0 != 0 }), packet[40..<48].contains(where: { $0 != 0 }) else { throw TimeValidationError.invalidPacket }
        let t2 = decode(packet, 32, near: sent)
        let t3 = decode(packet, 40, near: sent)
        let delay = (received - sent) - (t3 - t2)
        let offset = ((t2 - sent) + (t3 - received)) / 2
        guard received >= sent, t3 >= t2, delay >= -0.002, delay < 2, abs(offset) < 86_400 else {
            throw TimeValidationError.unreasonableDelay
        }
        let dispersion = Double(word(packet, 8)) / 65_536
        let rootDelay = max(0, Double(Int32(bitPattern: word(packet, 4))) / 65_536)
        guard dispersion < 2, rootDelay < 2 else { throw TimeValidationError.unsynchronized }
        return TimeSample(host: host, offset: offset, delay: max(0, delay),
                          uncertainty: max(0.001, max(0, delay) / 2 + rootDelay / 2 + dispersion),
                          epochAtReceive: received + offset, continuousAtReceive: continuous)
    }
    /// Require two agreeing sources; a lone fast response is not enough.
    public static func select(_ samples: [TimeSample]) throws -> TimeSample {
        let agreeing = samples.filter { a in
            samples.contains { b in
                a.host != b.host && abs(a.offset - b.offset) <= max(0.05, a.uncertainty + b.uncertainty)
            }
        }
        guard let best = agreeing.min(by: { $0.uncertainty < $1.uncertainty }) else {
            throw TimeValidationError.inconsistentServers
        }
        return best
    }
}

public struct ClockReading {
    public let epoch: Double
    public let source: String
    public let network: Bool
    public let uncertainty: Double?
    public let age: Double?
}

public final class PreciseClock: @unchecked Sendable {
    public static let validity = 900.0
    private let lock = NSLock()
    private var sample: TimeSample?
    public init() {}
    public func calibrate(_ sample: TimeSample) { lock.lock(); self.sample = sample; lock.unlock() }
    public func reset() { lock.lock(); sample = nil; lock.unlock() }
    public func reading(network: Bool, offsetMilliseconds: Int = 0, system: Double = Date().timeIntervalSince1970,
                        continuous: Double = ContinuousSeconds.now) -> ClockReading {
        lock.lock(); let value = sample; lock.unlock()
        let offset = Double(offsetMilliseconds) / 1000
        if network, let value {
            let age = continuous - value.continuousAtReceive
            if age >= 0 && age < Self.validity {
                return ClockReading(epoch: value.epochAtReceive + age + offset, source: "网络校时", network: true,
                                    uncertainty: value.uncertainty + age * 0.00005, age: age)
            }
            return ClockReading(epoch: system + offset, source: "校时过期 · 设备时间", network: false, uncertainty: nil, age: nil)
        }
        return ClockReading(epoch: system + offset, source: "设备时间", network: false, uncertainty: nil, age: nil)
    }
}
