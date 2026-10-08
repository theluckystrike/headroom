import Foundation
import ServiceManagement

/// Launch at login through SMAppService (macOS 13+).
/// Only works when running from a bundled Headroom.app; `swift run` has no bundle to register.
enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// The user turned the item off in System Settings > General > Login Items and must re-allow it there.
    static var requiresApproval: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
