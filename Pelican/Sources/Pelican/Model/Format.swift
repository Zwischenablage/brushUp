import Foundation

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB, .usePB]
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, value))
    }

    static func count<T: BinaryInteger>(_ value: T) -> String {
        countFormatter.string(from: NSNumber(value: Int64(value))) ?? "\(value)"
    }

    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "–" }
        return String(format: "%.1f%%", fraction * 100)
    }

    static func date(_ secondsSince1970: Double) -> String {
        guard secondsSince1970 > 0 else { return "—" }
        return dateFormatter.string(from: Date(timeIntervalSince1970: secondsSince1970))
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return dateFormatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// `00:00:07.21` style stopwatch string.
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, interval)
        let hours = Int(total) / 3600
        let minutes = (Int(total) / 60) % 60
        let seconds = total - Double(hours * 3600 + minutes * 60)
        return String(format: "%02d:%02d:%05.2f", hours, minutes, seconds)
    }

    /// Abbreviates the home directory as `~`.
    static func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static let staleThreshold: TimeInterval = 365 * 24 * 3600

    static func isStale(_ secondsSince1970: Double) -> Bool {
        secondsSince1970 > 0 && Date().timeIntervalSince1970 - secondsSince1970 > staleThreshold
    }
}
