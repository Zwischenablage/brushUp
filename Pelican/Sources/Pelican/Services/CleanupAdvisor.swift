import Foundation

struct CleanupSuggestion: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case cache, developer, logs, installer, stale

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cache: return "Caches"
            case .developer: return "Developer Artifacts"
            case .logs: return "Logs & Reports"
            case .installer: return "Installers & Archives"
            case .stale: return "Large & Untouched"
            }
        }

        var symbol: String {
            switch self {
            case .cache: return "shippingbox"
            case .developer: return "hammer"
            case .logs: return "doc.text.magnifyingglass"
            case .installer: return "opticaldiscdrive"
            case .stale: return "clock.arrow.circlepath"
            }
        }
    }

    enum Risk {
        /// Regenerated automatically by the owning tool or app.
        case safe
        /// Probably not needed, but only the user can tell.
        case review
    }

    let node: NodeID
    let kind: Kind
    let risk: Risk
    let reason: String
    let size: Int64

    var id: NodeID { node }
}

/// Walks a scanned tree looking for well-known disposable data.
enum CleanupAdvisor {
    static let minimumSize: Int64 = 20 * 1024 * 1024
    static let largeFileSize: Int64 = 500 * 1024 * 1024
    static let staleAge: TimeInterval = 180 * 24 * 3600
    static let maximumResults = 400

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "zip", "ipa", "sparseimage"]

    static func analyze(tree: FileTree, metric: SizeMetric) -> [CleanupSuggestion] {
        var results: [CleanupSuggestion] = []
        let now = Date().timeIntervalSince1970

        func size(_ id: NodeID) -> Int64 { tree[id].size(metric) }

        func suggest(_ id: NodeID, _ kind: CleanupSuggestion.Kind, _ risk: CleanupSuggestion.Risk, _ reason: String) {
            let bytes = size(id)
            guard bytes >= minimumSize, !Safety.verdict(for: tree.path(of: id)).isBlocked else { return }
            results.append(CleanupSuggestion(node: id, kind: kind, risk: risk, reason: reason, size: bytes))
        }

        /// Suggests each sizeable child of a container folder (e.g. every app's cache
        /// folder inside ~/Library/Caches) rather than the container itself.
        func suggestChildren(of id: NodeID, _ kind: CleanupSuggestion.Kind, _ reason: String) {
            for child in tree.visibleChildren(of: id, sortedBy: metric) {
                suggest(child, kind, .safe, reason)
            }
        }

        func visit(_ id: NodeID) {
            let node = tree[id]
            // The root's stored name is a display name, so use the real path components for it.
            let rootPath = tree.rootPath as NSString
            let name = id == FileTree.root ? rootPath.lastPathComponent : node.name
            let parentName = id == FileTree.root
                ? (rootPath.deletingLastPathComponent as NSString).lastPathComponent
                : tree[node.parent].name

            if node.isDirectory {
                switch name {
                case "Caches" where parentName == "Library":
                    suggestChildren(of: id, .cache, "App cache — rebuilt automatically when needed")
                    return
                case "Logs" where parentName == "Library":
                    suggestChildren(of: id, .logs, "Log files — only useful for troubleshooting")
                    return
                case "DiagnosticReports":
                    suggest(id, .logs, .safe, "Crash and diagnostic reports")
                    return
                case "DerivedData":
                    suggest(id, .developer, .safe, "Xcode build products — rebuilt on next build")
                    return
                case "node_modules":
                    suggest(id, .developer, .safe, "npm packages — restore with `npm install`")
                    return
                case "iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport":
                    suggestChildren(of: id, .developer, "Device symbols — re-downloaded when the device reconnects")
                    return
                case "Archives" where parentName == "Xcode":
                    suggestChildren(of: id, .developer, "Xcode archive — keep it if you need to symbolicate that release")
                    return
                case "Caches" where parentName == "CoreSimulator":
                    suggest(id, .developer, .safe, "Simulator caches")
                    return
                case "_cacache" where parentName == ".npm":
                    suggest(id, .developer, .safe, "npm download cache")
                    return
                case "caches" where parentName == ".gradle":
                    suggest(id, .developer, .safe, "Gradle build cache")
                    return
                case "__pycache__", ".pytest_cache", ".mypy_cache":
                    suggest(id, .developer, .safe, "Python bytecode cache")
                    return
                case "Pods":
                    suggest(id, .developer, .review, "CocoaPods dependencies — restore with `pod install`")
                    return
                default:
                    break
                }
                // Never look inside bundles such as apps or Photos libraries.
                if node.isPackage { return }
                for child in node.children where !tree[child].isRemoved {
                    visit(child)
                }
                return
            }

            let bytes = size(id)
            if let ext = FileCategory.fileExtension(of: node.name), installerExtensions.contains(ext),
               bytes >= 50 * 1024 * 1024 {
                let reason = ext == "zip" ? "Large archive — delete it if already extracted"
                                          : "Installer image — not needed once the app is installed"
                suggest(id, .installer, .review, reason)
            } else if bytes >= largeFileSize, node.modified > 0, now - node.modified > staleAge {
                let age = Format.relative(Date(timeIntervalSince1970: node.modified))
                suggest(id, .stale, .review, "Large file last modified \(age)")
            }
        }

        visit(FileTree.root)
        results.sort { $0.size > $1.size }
        if results.count > maximumResults {
            results.removeSubrange(maximumResults...)
        }
        return results
    }
}
