import SwiftUI

struct ClockSettings: Codable, Equatable {
    var theme: ClockTheme = .mint
    var layout: ClockLayout = .strip
    var textScale = 1.0
    var framesPerSecond = 60
    var beijingTime = true
    var networkTime = true
    var offsetMilliseconds = 0
    var countdownEnabled = false
    var target = Date(timeIntervalSince1970: (floor(Date().timeIntervalSince1970 / 60) + 1) * 60)
    var keepAwake = true
    var timeZone: TimeZone { beijingTime ? TimeZone(identifier: "Asia/Shanghai")! : .autoupdatingCurrent }
    var zoneLabel: String { beijingTime ? "北京时间" : "本地时间" }
    static let storageKey = "clock.preferences.v1"
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        settings.textScale = min(1.12, max(0.75, settings.textScale))
        settings.framesPerSecond = [30, 60].contains(settings.framesPerSecond) ? settings.framesPerSecond : 60
        settings.offsetMilliseconds = min(5000, max(-5000, settings.offsetMilliseconds))
        return settings
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

enum ClockLayout: String, Codable, CaseIterable, Identifiable {
    case strip, card
    var id: String { rawValue }
    var title: String { self == .strip ? "横条" : "卡片" }
    var width: Int { 960 }
    var height: Int { self == .strip ? 400 : 540 }
    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }
}

enum ClockTheme: String, Codable, CaseIterable, Identifiable {
    case mint, ice, amber, white
    var id: String { rawValue }
    var title: String {
        switch self { case .mint: return "薄荷"; case .ice: return "冰蓝"; case .amber: return "琥珀"; case .white: return "纯白" }
    }
    var uiColor: UIColor {
        switch self {
        case .mint: return UIColor(red: 0.57, green: 0.98, blue: 0.76, alpha: 1)
        case .ice: return UIColor(red: 0.51, green: 0.79, blue: 1, alpha: 1)
        case .amber: return UIColor(red: 1, green: 0.77, blue: 0.40, alpha: 1)
        case .white: return UIColor(white: 0.97, alpha: 1)
        }
    }
    var color: Color { Color(uiColor: uiColor) }
}
