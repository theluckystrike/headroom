import Foundation

public enum Format {
    private static let units = ["B", "K", "M", "G", "T", "P", "E"]

    /// Binary units with single-letter suffixes: "0B", "512B", "812M", "1.0G", "14.2G".
    /// One decimal below 100 of a unit, whole numbers from 100 up.
    public static func bytes(_ b: UInt64) -> String {
        if b < 1024 { return "\(b)B" }
        var unit = 0
        var value = Double(b)
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let tenths = (value * 10).rounded() / 10
        if tenths < 100 { return String(format: "%.1f", tenths) + units[unit] }
        let whole = value.rounded()
        if whole >= 1024, unit < units.count - 1 { return "1.0" + units[unit + 1] }
        return String(format: "%.0f", whole) + units[unit]
    }

    /// "AG 12 | TTY 31 | 14.2G free | +9"
    public static func line(_ s: Snapshot) -> String {
        "AG \(s.agents.count) | TTY \(s.terminals.sessions) | \(bytes(s.memory.availableBytes)) free | +\(s.headroomAgents)"
    }

    /// Pretty-printed JSON with sorted keys, stable across runs for the same snapshot.
    public static func json(_ s: Snapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(s), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
