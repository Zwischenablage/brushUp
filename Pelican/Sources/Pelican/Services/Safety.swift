import Foundation

enum SafetyVerdict: Equatable {
    case allowed
    /// Deletable, but the user should confirm first.
    case caution(String)
    /// Never deletable from Pelican.
    case blocked(String)

    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .allowed: return nil
        case .caution(let message), .blocked(let message): return message
        }
    }
}

/// Hard-coded guardrails so a stray click can never take out the OS or a whole home folder.
enum Safety {
    static let home = NSHomeDirectory()

    private static let blockedExact: Set<String> = {
        var paths: Set<String> = ["/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/private",
                                  "/usr", "/bin", "/sbin", "/etc", "/var", "/tmp", "/opt", "/cores", "/usr/local",
                                  "/opt/homebrew", "/private/var", "/private/tmp", "/private/etc"]
        for folder in ["", "/Library", "/Desktop", "/Documents", "/Downloads", "/Movies", "/Music", "/Pictures",
                       "/Public", "/Applications", "/Library/Application Support", "/Library/Caches",
                       "/Library/Containers", "/Library/Preferences", "/Library/Mobile Documents"] {
            paths.insert(home + folder)
        }
        return paths
    }()

    private static let blockedPrefixes: [(prefix: String, reason: String)] = [
        ("/System/", "Part of macOS (protected by System Integrity Protection)"),
        ("/bin/", "Core Unix tools required by macOS"),
        ("/sbin/", "Core Unix tools required by macOS"),
        ("/usr/bin/", "Core Unix tools required by macOS"),
        ("/usr/sbin/", "Core Unix tools required by macOS"),
        ("/usr/lib/", "System libraries required by macOS"),
        ("/usr/libexec/", "System helpers required by macOS"),
        ("/usr/share/", "System resources required by macOS"),
        ("/usr/standalone/", "Boot resources required by macOS"),
        ("/private/var/db/", "System databases required by macOS"),
        ("/private/var/vm/", "Virtual memory swap — managed by macOS"),
        ("/Library/Apple/", "Apple-managed system components"),
        ("/private/etc/", "System configuration"),
        ("/dev/", "Device nodes"),
        (home + "/Library/Keychains", "Keychains hold your saved passwords and certificates"),
    ]

    private static let cautionPrefixes: [(prefix: String, reason: String)] = [
        (home + "/Library/Application Support/MobileSync/Backup", "iPhone / iPad backups — they cannot be recreated"),
        (home + "/Library/Mobile Documents", "iCloud Drive data — deleting removes it from all your devices"),
        (home + "/Library/Mail", "Your Mail data"),
        (home + "/Library/Messages", "Your Messages history"),
        (home + "/Library/Containers", "Sandboxed app data — the app may lose settings or documents"),
        (home + "/Library/Group Containers", "Shared app data — apps may lose settings or documents"),
        (home + "/Library/Application Support", "App data — may contain settings, libraries or documents"),
        (home + "/Pictures/Photos Library.photoslibrary", "Your Photos library"),
        (home + "/Documents", "Your documents"),
        (home + "/Desktop", "Files on your Desktop"),
        ("/Applications/", "An installed application"),
        ("/Library/", "System-wide data shared by all users"),
        ("/private/", "Low-level system data"),
    ]

    static func verdict(for path: String) -> SafetyVerdict {
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        if blockedExact.contains(path) {
            return .blocked("Top-level system or home folder")
        }
        if isVolumeRoot(path) {
            return .blocked("Root of a mounted volume")
        }
        for entry in blockedPrefixes where path == entry.prefix || path.hasPrefix(entry.prefix.hasSuffix("/") ? entry.prefix : entry.prefix + "/") {
            return .blocked(entry.reason)
        }
        for entry in cautionPrefixes where path == entry.prefix || path.hasPrefix(entry.prefix.hasSuffix("/") ? entry.prefix : entry.prefix + "/") {
            return .caution(entry.reason)
        }
        return .allowed
    }

    private static func isVolumeRoot(_ path: String) -> Bool {
        guard path.hasPrefix("/Volumes/") else { return false }
        return !path.dropFirst("/Volumes/".count).contains("/")
    }
}
