import AppKit
import CoreServices
import Foundation

struct AppLeftover: Identifiable, Hashable {
    let path: String
    let label: String
    let size: Int64

    var id: String { path }
}

struct InstalledApp: Identifiable {
    let path: String
    let name: String
    let bundleID: String?
    let version: String?
    let lastUsed: Date?
    var size: Int64?
    var leftovers: [AppLeftover] = []

    var id: String { path }

    /// Apple apps live on the sealed system volume or are SIP protected.
    var isProtected: Bool {
        (bundleID?.hasPrefix("com.apple.") ?? false) || path.hasPrefix("/System/")
    }

    var leftoverSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { (size ?? 0) + leftoverSize }
}

/// Lists installed apps with their bundle size, last-opened date (from Spotlight)
/// and the support files they leave behind in ~/Library.
final class AppInventory: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published private(set) var sizedCount = 0
    @Published var lastError: String?

    private var generation = 0

    func reloadIfNeeded() {
        if apps.isEmpty && !isLoading { reload() }
    }

    func reload() {
        generation += 1
        let token = generation
        isLoading = true
        sizedCount = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let discovered = AppInventory.discoverApps()
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.apps = discovered
            }
            // Size each bundle in parallel; publish results as they come in.
            DispatchQueue.concurrentPerform(iterations: discovered.count) { index in
                let app = discovered[index]
                let size = DiskScanner.totals(of: app.path).physical
                let leftovers = AppInventory.leftovers(for: app)
                DispatchQueue.main.async {
                    guard token == self.generation,
                          let position = self.apps.firstIndex(where: { $0.path == app.path }) else { return }
                    self.apps[position].size = size
                    self.apps[position].leftovers = leftovers
                    self.sizedCount += 1
                }
            }
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.isLoading = false
            }
        }
    }

    /// Moves the app bundle and the chosen leftovers to the Trash.
    func uninstall(_ app: InstalledApp, leftovers: [AppLeftover]) {
        guard !app.isProtected else { return }
        var failures: [String] = []
        for path in [app.path] + leftovers.map(\.path) {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            } catch {
                failures.append("\((path as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }
        if FileManager.default.fileExists(atPath: app.path) {
            lastError = "Could not move \(app.name) to the Trash. Apps installed by an administrator may need to be removed in Finder.\n\n" + failures.joined(separator: "\n")
        } else {
            apps.removeAll { $0.path == app.path }
            if !failures.isEmpty { lastError = failures.joined(separator: "\n") }
        }
    }

    // MARK: Discovery

    private static func discoverApps() -> [InstalledApp] {
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        var found: [String] = []
        let fileManager = FileManager.default
        for root in roots {
            guard let names = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = root + "/" + name
                if name.hasSuffix(".app") {
                    found.append(path)
                } else if let nested = try? fileManager.contentsOfDirectory(atPath: path) {
                    // One level of grouping folders, e.g. /Applications/Utilities or vendor suites.
                    found.append(contentsOf: nested.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 })
                }
            }
        }
        return found.map(makeApp).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func makeApp(path: String) -> InstalledApp {
        let bundle = Bundle(path: path)
        let info = bundle?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return InstalledApp(path: path,
                            name: name,
                            bundleID: bundle?.bundleIdentifier,
                            version: info?["CFBundleShortVersionString"] as? String,
                            lastUsed: lastUsedDate(path: path))
    }

    private static func lastUsedDate(path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private static func leftovers(for app: InstalledApp) -> [AppLeftover] {
        guard !app.isProtected else { return [] }
        let library = NSHomeDirectory() + "/Library"
        let bundleName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
        var candidates: [(String, String)] = []
        if let id = app.bundleID {
            candidates += [
                (library + "/Application Support/" + id, "Application Support"),
                (library + "/Caches/" + id, "Cache"),
                (library + "/Containers/" + id, "Sandbox Container"),
                (library + "/Preferences/" + id + ".plist", "Preferences"),
                (library + "/Saved Application State/" + id + ".savedState", "Saved State"),
                (library + "/HTTPStorages/" + id, "HTTP Storage"),
                (library + "/WebKit/" + id, "WebKit Data"),
                (library + "/Logs/" + id, "Logs"),
                (library + "/Application Scripts/" + id, "Scripts"),
            ]
        }
        // Many non-sandboxed apps use their plain name instead of the bundle id.
        if bundleName.count > 2 {
            candidates += [
                (library + "/Application Support/" + bundleName, "Application Support"),
                (library + "/Caches/" + bundleName, "Cache"),
                (library + "/Logs/" + bundleName, "Logs"),
            ]
        }
        var seen = Set<String>()
        var results: [AppLeftover] = []
        for (path, label) in candidates where !seen.contains(path) {
            seen.insert(path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            results.append(AppLeftover(path: path, label: label, size: DiskScanner.totals(of: path).physical))
        }
        return results
    }
}
