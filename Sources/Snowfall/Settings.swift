import Foundation

enum Intensity: Int, CaseIterable {
    case light, medium, heavy

    var title: String {
        switch self {
        case .light: return "Kam"
        case .medium: return "O'rtacha"
        case .heavy: return "Ko'p"
        }
    }

    /// Flakes spawned per second for every 1000 pt of screen width.
    var spawnRate: CGFloat {
        switch self {
        case .light: return 14
        case .medium: return 32
        case .heavy: return 65
        }
    }
}

enum Wind: Int, CaseIterable {
    case calm, breeze, strong

    var title: String {
        switch self {
        case .calm: return "Shamolsiz"
        case .breeze: return "Yengil shamol"
        case .strong: return "Kuchli shamol"
        }
    }

    /// Typical sideways drift in pt/s.
    var speed: CGFloat {
        switch self {
        case .calm: return 0
        case .breeze: return 18
        case .strong: return 55
        }
    }
}

/// User preferences, kept in UserDefaults so they survive restarts.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let isSnowing = "isSnowing"
        static let intensity = "intensity"
        static let wind = "wind"
        static let aboveWindows = "aboveWindows"
        static let pileOnWindows = "pileOnWindows"
        static let showSnowplow = "showSnowplow"
    }

    private init() {
        defaults.register(defaults: [
            Key.isSnowing: true,
            Key.intensity: Intensity.medium.rawValue,
            Key.wind: Wind.breeze.rawValue,
            Key.aboveWindows: true,
            Key.pileOnWindows: true,
            Key.showSnowplow: true,
        ])
    }

    var isSnowing: Bool {
        get { defaults.bool(forKey: Key.isSnowing) }
        set { defaults.set(newValue, forKey: Key.isSnowing) }
    }

    var intensity: Intensity {
        get { Intensity(rawValue: defaults.integer(forKey: Key.intensity)) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.intensity) }
    }

    var wind: Wind {
        get { Wind(rawValue: defaults.integer(forKey: Key.wind)) ?? .breeze }
        set { defaults.set(newValue.rawValue, forKey: Key.wind) }
    }

    /// true: snow falls over every window; false: only on the desktop, behind windows.
    var aboveWindows: Bool {
        get { defaults.bool(forKey: Key.aboveWindows) }
        set { defaults.set(newValue, forKey: Key.aboveWindows) }
    }

    /// The little snowplow truck on the Dock.
    var showSnowplow: Bool {
        get { defaults.bool(forKey: Key.showSnowplow) }
        set { defaults.set(newValue, forKey: Key.showSnowplow) }
    }

    /// Snow also piles up on top of open windows.
    var pileOnWindows: Bool {
        get { defaults.bool(forKey: Key.pileOnWindows) }
        set { defaults.set(newValue, forKey: Key.pileOnWindows) }
    }
}
