import Foundation
import HeadroomCore
import UserNotifications

/// Posts one notification when the level enters .danger, at most once per 10 minutes.
/// Authorization is requested lazily, the first time there is something to say.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let minInterval: TimeInterval = 10 * 60

    private var lastLevel: HeadroomLevel?
    private var lastPosted: Date?
    private var delegateInstalled = false

    /// UNUserNotificationCenter.current() raises an exception in a process without a bundle
    /// identifier (`swift run`), so notifications are skipped there.
    var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    func observe(_ snapshot: Snapshot, enabled: Bool) {
        let previous = lastLevel
        lastLevel = snapshot.level
        guard enabled, isSupported, snapshot.level == .danger, previous != .danger else { return }
        let now = Date()
        if let lastPosted, now.timeIntervalSince(lastPosted) < Self.minInterval { return }
        lastPosted = now
        post(title: "Headroom: no room for another agent", body: Self.body(for: snapshot))
    }

    static func body(for s: Snapshot) -> String {
        var text = "\(Format.bytes(s.memory.availableBytes)) free"
        if s.memory.swapTotalBytes > 0 {
            let pct = Int((Double(s.memory.swapUsedBytes) / Double(s.memory.swapTotalBytes) * 100).rounded())
            text += ", swap \(pct)% used"
        }
        return text + ". Close an agent before starting a new one."
    }

    private func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if !delegateInstalled {
            center.delegate = self
            delegateInstalled = true
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: "headroom.danger", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    // Show the banner even if Headroom happens to be the active app (e.g. while its menu is open).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
