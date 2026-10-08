import Foundation
import HeadroomCore

/// How the menu bar item presents itself.
enum DisplayMode: String, CaseIterable {
    /// `AG 12  TTY 31  14.2G  +9` over animated rain.
    case full
    /// Only the `+9` segment.
    case compact
    /// Full text, no rain. Rain plays a short burst only when the level changes.
    case calm

    var title: String {
        switch self {
        case .full: return "Full"
        case .compact: return "Compact (+N only)"
        case .calm: return "Calm (no rain)"
        }
    }
}

/// UserDefaults-backed app settings. Main thread only.
///
/// Advanced knobs without UI can be set from a terminal, e.g.
/// `defaults write <bundle id> defaultPerAgentMB -int 400`.
final class AppSettings {
    static let reserveChoicesGB = [1, 2, 3, 4, 6, 8]

    private enum Key {
        static let reserveGB = "reserveGB"
        static let displayMode = "displayMode"
        static let rainEnabled = "rainEnabled"
        static let notifyOnDanger = "notifyOnDanger"
        static let defaultPerAgentMB = "defaultPerAgentMB"
        static let swapDangerRatio = "swapDangerRatio"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.reserveGB: 3,
            Key.displayMode: DisplayMode.full.rawValue,
            Key.rainEnabled: true,
            Key.notifyOnDanger: true,
        ])
    }

    /// Memory kept free for the OS and bursts, in GiB.
    var reserveGB: Int {
        get {
            let value = defaults.integer(forKey: Key.reserveGB)
            return value > 0 ? value : 3
        }
        set { defaults.set(max(1, newValue), forKey: Key.reserveGB) }
    }

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") ?? .full }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    var rainEnabled: Bool {
        get { defaults.bool(forKey: Key.rainEnabled) }
        set { defaults.set(newValue, forKey: Key.rainEnabled) }
    }

    var notifyOnDanger: Bool {
        get { defaults.bool(forKey: Key.notifyOnDanger) }
        set { defaults.set(newValue, forKey: Key.notifyOnDanger) }
    }

    /// The math settings handed to HeadroomCore / LiveProvider.
    var headroomSettings: HeadroomSettings {
        var s = HeadroomSettings()
        s.reserveBytes = UInt64(reserveGB) << 30
        if defaults.object(forKey: Key.defaultPerAgentMB) != nil {
            let mb = defaults.integer(forKey: Key.defaultPerAgentMB)
            if mb > 0 { s.defaultPerAgentBytes = UInt64(mb) << 20 }
        }
        if defaults.object(forKey: Key.swapDangerRatio) != nil {
            let ratio = defaults.double(forKey: Key.swapDangerRatio)
            if ratio > 0, ratio <= 1 { s.swapDangerRatio = ratio }
        }
        return s
    }
}
