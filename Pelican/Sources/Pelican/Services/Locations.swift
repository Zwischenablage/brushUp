import AppKit
import Foundation

struct VolumeInfo: Identifiable, Hashable {
    let path: String
    let name: String
    let total: Int64
    let available: Int64
    let isInternal: Bool
    let isRemovable: Bool
    let isNetwork: Bool

    var id: String { path }
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var symbol: String {
        if isNetwork { return "network" }
        if isRemovable || !isInternal { return "externaldrive" }
        return "internaldrive"
    }
}

enum VolumeService {
    static func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
                                      .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.volumeIsBrowsable == false { continue }
            let path = url.path
            if path.hasPrefix("/System/Volumes/") { continue }
            let available = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            volumes.append(VolumeInfo(path: path,
                                      name: values.volumeName ?? FileManager.default.displayName(atPath: path),
                                      total: Int64(values.volumeTotalCapacity ?? 0),
                                      available: available,
                                      isInternal: values.volumeIsInternal ?? true,
                                      isRemovable: values.volumeIsRemovable ?? false,
                                      isNetwork: !(values.volumeIsLocal ?? true)))
        }
        return volumes.sorted { lhs, rhs in
            if lhs.path == "/" { return true }
            if rhs.path == "/" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func volume(containing path: String, in volumes: [VolumeInfo]) -> VolumeInfo? {
        volumes
            .filter { $0.path == "/" || path == $0.path || path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }
}

/// One-click entry points in the sidebar.
struct Shortcut: Identifiable, Hashable {
    let title: String
    let path: String
    let symbol: String

    var id: String { path }
}

enum Shortcuts {
    private static let home = NSHomeDirectory()

    private static func existing(_ items: [Shortcut]) -> [Shortcut] {
        items.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static let favorites: [Shortcut] = existing([
        Shortcut(title: "Home", path: home, symbol: "house"),
        Shortcut(title: "Desktop", path: home + "/Desktop", symbol: "menubar.dock.rectangle"),
        Shortcut(title: "Documents", path: home + "/Documents", symbol: "doc"),
        Shortcut(title: "Downloads", path: home + "/Downloads", symbol: "arrow.down.circle"),
        Shortcut(title: "Pictures", path: home + "/Pictures", symbol: "photo"),
        Shortcut(title: "Movies", path: home + "/Movies", symbol: "film"),
        Shortcut(title: "Applications", path: "/Applications", symbol: "square.grid.2x2"),
    ])

    static let library: [Shortcut] = existing([
        Shortcut(title: "Library Caches", path: home + "/Library/Caches", symbol: "shippingbox"),
        Shortcut(title: "System Caches", path: "/Library/Caches", symbol: "shippingbox.fill"),
        Shortcut(title: "Application Support", path: home + "/Library/Application Support", symbol: "folder"),
        Shortcut(title: "Containers", path: home + "/Library/Containers", symbol: "cube"),
        Shortcut(title: "Logs", path: home + "/Library/Logs", symbol: "doc.text.magnifyingglass"),
        Shortcut(title: "Trash", path: home + "/.Trash", symbol: "trash"),
    ])

    static let developer: [Shortcut] = existing([
        Shortcut(title: "Xcode DerivedData", path: home + "/Library/Developer/Xcode/DerivedData", symbol: "hammer"),
        Shortcut(title: "Xcode Archives", path: home + "/Library/Developer/Xcode/Archives", symbol: "archivebox"),
        Shortcut(title: "iOS DeviceSupport", path: home + "/Library/Developer/Xcode/iOS DeviceSupport", symbol: "iphone"),
        Shortcut(title: "Simulators", path: home + "/Library/Developer/CoreSimulator", symbol: "ipad.and.iphone"),
        Shortcut(title: "Docker", path: home + "/Library/Containers/com.docker.docker", symbol: "shippingbox.circle"),
        Shortcut(title: "Ollama Models", path: home + "/.ollama", symbol: "brain"),
        Shortcut(title: "Hugging Face", path: home + "/.cache/huggingface", symbol: "brain.head.profile"),
        Shortcut(title: "npm Cache", path: home + "/.npm", symbol: "cube.box"),
        Shortcut(title: "Gradle", path: home + "/.gradle", symbol: "cube.box.fill"),
        Shortcut(title: "Cargo", path: home + "/.cargo", symbol: "cube.transparent"),
        Shortcut(title: "Homebrew Cache", path: home + "/Library/Caches/Homebrew", symbol: "mug"),
    ])

    static var all: [Shortcut] { favorites + library + developer }
}

enum FullDiskAccess {
    /// The TCC database is only readable by processes that have Full Disk Access.
    static var isGranted: Bool {
        let probes = ["/Library/Application Support/com.apple.TCC/TCC.db",
                      NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"]
        for probe in probes where FileManager.default.fileExists(atPath: probe) {
            let fd = open(probe, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            return false
        }
        return false
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
