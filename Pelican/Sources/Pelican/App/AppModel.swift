import AppKit
import SwiftUI

enum VizMode: String, CaseIterable, Identifiable {
    case sunburst, treemap

    var id: String { rawValue }
    var label: String { self == .sunburst ? "Sunburst" : "Treemap" }
    var symbol: String { self == .sunburst ? "circle.circle" : "square.grid.2x2" }
}

enum SidebarItem: Hashable {
    case location(String)
    case cleanup
    case apps
}

enum ScanPhase: Equatable {
    case idle
    case scanning
    case finished
}

enum SortKey: String {
    case name, size, items, modified, kind
}

enum HoverSource {
    case canvas, table
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var confirmTitle: String? = nil
    var action: (() -> Void)? = nil

    func makeAlert() -> Alert {
        if let confirmTitle, let action {
            return Alert(title: Text(title), message: Text(message),
                         primaryButton: .destructive(Text(confirmTitle), action: action),
                         secondaryButton: .cancel())
        }
        return Alert(title: Text(title), message: Text(message), dismissButton: .default(Text("OK")))
    }
}

/// High-frequency pointer state, kept separate from `AppModel` so that mouse moves
/// only re-render the views that actually show hover feedback.
final class InteractionState: ObservableObject {
    @Published private(set) var hovered: NodeID?
    @Published var pointer: CGPoint = .zero
    private(set) var source: HoverSource = .canvas
    /// Last node under the pointer; survives the pointer leaving (e.g. to open a context menu).
    private(set) var lastHovered: NodeID?

    func hover(_ id: NodeID?, from source: HoverSource) {
        if let id { lastHovered = id }
        self.source = source
        if hovered != id { hovered = id }
    }

    func reset() {
        lastHovered = nil
        hovered = nil
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Navigation
    @Published var sidebarSelection: SidebarItem?
    @Published private(set) var tree: FileTree?
    @Published private(set) var focus: NodeID = FileTree.root
    @Published var selection: NodeID?

    // Presentation
    @Published var vizMode: VizMode = .sunburst
    @Published var metric: SizeMetric = .physical
    @Published var depth: Double = 6
    @Published var sortKey: SortKey = .size
    @Published var sortAscending = false

    // Scanning
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var progress = DiskScanner.Progress()
    @Published private(set) var scanDuration: TimeInterval = 0
    @Published private(set) var scanningPath: String?
    /// Bumped whenever the tree is mutated so caches and views refresh.
    @Published private(set) var version = 0

    // Cleanup
    @Published private(set) var basket: [NodeID] = []
    @Published var quickLookURL: URL?
    @Published var alert: AlertItem?

    // Environment
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var shortcutSizes: [String: Int64] = [:]
    @Published private(set) var hasFullDiskAccess = FullDiskAccess.isGranted
    @Published var showOnboarding: Bool

    let interaction = InteractionState()
    let inventory = AppInventory()

    private var scanner: DiskScanner?
    private var progressTimer: Timer?
    private var scanStart = Date()
    private var pendingFocusPath: String?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var shortcutGeneration = 0

    private struct SunburstKey: Equatable { let focus: NodeID; let version: Int; let metric: SizeMetric; let depth: Int }
    private struct TreemapKey: Equatable { let focus: NodeID; let version: Int; let metric: SizeMetric; let depth: Int; let width: Int; let height: Int }
    private struct RowsKey: Equatable { let focus: NodeID; let version: Int; let metric: SizeMetric; let sort: SortKey; let ascending: Bool }
    private struct SuggestionsKey: Equatable { let tree: ObjectIdentifier; let version: Int; let metric: SizeMetric }

    private var sunburstCache: (key: SunburstKey, value: [SunburstSegment])?
    private var treemapCache: (key: TreemapKey, value: [TreemapTile])?
    private var rowsCache: (key: RowsKey, value: [NodeID])?
    private var suggestionsCache: (key: SuggestionsKey, value: [CleanupSuggestion])?

    private static let onboardingDismissedKey = "onboardingDismissed"

    init() {
        showOnboarding = !FullDiskAccess.isGranted
            && !UserDefaults.standard.bool(forKey: AppModel.onboardingDismissedKey)
        volumes = VolumeService.mountedVolumes()

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshVolumes()
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let granted = FullDiskAccess.isGranted
                if granted != self.hasFullDiskAccess { self.hasFullDiskAccess = granted }
                if granted && self.showOnboarding { self.showOnboarding = false }
            })
        refreshShortcutSizes()
    }

    // MARK: Derived state

    var breadcrumb: [NodeID] { tree?.ancestors(of: focus) ?? [] }

    var rootVolume: VolumeInfo? {
        guard let path = tree?.rootPath ?? scanningPath else { return volumes.first }
        return VolumeService.volume(containing: path, in: volumes)
    }

    /// Item the keyboard shortcuts act on: the selection, else whatever is under the pointer.
    var actionTarget: NodeID? {
        if let selection { return selection }
        return interaction.hovered
    }

    var ringCount: Int { Int(depth.rounded()) }

    func dismissOnboarding() {
        UserDefaults.standard.set(true, forKey: AppModel.onboardingDismissedKey)
        showOnboarding = false
    }

    func recheckFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.isGranted
        if hasFullDiskAccess { showOnboarding = false }
    }

    // MARK: Scanning

    /// Opens a location: zooms if it is inside the current scan, otherwise scans it.
    func open(path: String) {
        let path = DiskScanner.normalize(path)
        if phase != .scanning, let tree, let id = tree.node(atPath: path), tree[id].isDirectory {
            zoom(to: id)
            return
        }
        startScan(path: path)
    }

    func rescan() {
        guard let tree else {
            if let scanningPath { startScan(path: scanningPath) }
            return
        }
        pendingFocusPath = tree.path(of: focus)
        startScan(path: tree.rootPath)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder or volume to visualise"
        if panel.runModal() == .OK, let url = panel.url {
            sidebarSelection = .location(url.path)
            open(path: url.path)
        }
    }

    func startScan(path: String) {
        scanner?.cancel()
        let scanner = DiskScanner()
        self.scanner = scanner
        phase = .scanning
        scanningPath = path
        progress = DiskScanner.Progress()
        scanStart = Date()
        scanDuration = 0

        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self, weak scanner] _ in
            guard let self, let scanner else { return }
            self.progress = scanner.progress
            self.scanDuration = Date().timeIntervalSince(self.scanStart)
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer

        scanner.scan(path: path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.scanner === scanner else { return }
                self.progressTimer?.invalidate()
                self.progressTimer = nil
                self.scanner = nil
                self.progress = scanner.progress
                self.scanDuration = Date().timeIntervalSince(self.scanStart)
                guard let result else {
                    self.phase = self.tree == nil ? .idle : .finished
                    return
                }
                self.install(tree: result)
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
        scanner = nil
        progressTimer?.invalidate()
        progressTimer = nil
        pendingFocusPath = nil
        phase = tree == nil ? .idle : .finished
    }

    private func install(tree newTree: FileTree) {
        interaction.reset()
        selection = nil
        basket = []
        tree = newTree
        if let path = pendingFocusPath, let id = newTree.node(atPath: path) {
            focus = id
        } else {
            focus = FileTree.root
        }
        pendingFocusPath = nil
        version += 1
        phase = .finished
        refreshVolumes()
    }

    func refreshVolumes() {
        volumes = VolumeService.mountedVolumes()
    }

    func refreshShortcutSizes() {
        shortcutGeneration += 1
        let token = shortcutGeneration
        let shortcuts = Shortcuts.all
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for shortcut in shortcuts {
                let size = DiskScanner.totals(of: shortcut.path).physical
                DispatchQueue.main.async {
                    guard let self, token == self.shortcutGeneration else { return }
                    self.shortcutSizes[shortcut.path] = size
                }
            }
        }
    }

    // MARK: Navigation

    func zoom(to id: NodeID) {
        guard let tree, tree[id].isDirectory, !tree.isEffectivelyRemoved(id) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            focus = id
            selection = nil
        }
        interaction.reset()
    }

    func zoomOut() {
        guard let tree, focus != FileTree.root else { return }
        zoom(to: tree[focus].parent)
    }

    func zoomIntoTarget() {
        guard let tree, let target = actionTarget else { return }
        if tree[target].isDirectory { zoom(to: target) }
    }

    /// Click in the visualisation: folders zoom, files become the selection.
    func activate(_ id: NodeID) {
        guard let tree else { return }
        if tree[id].isDirectory {
            zoom(to: id)
        } else {
            selection = selection == id ? nil : id
        }
    }

    func handlePinch(_ scale: CGFloat) {
        if scale < 0.8 {
            zoomOut()
        } else if scale > 1.25, let hovered = interaction.hovered {
            activate(hovered)
        }
    }

    func setSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = key == .name || key == .kind
        }
    }

    // MARK: Cached layouts

    func sunburstSegments() -> [SunburstSegment] {
        guard let tree else { return [] }
        let key = SunburstKey(focus: focus, version: version, metric: metric, depth: ringCount)
        if let cache = sunburstCache, cache.key == key { return cache.value }
        let value = SunburstLayout.layout(tree: tree, root: focus, metric: metric, maxDepth: ringCount)
        sunburstCache = (key, value)
        return value
    }

    func treemapTiles(size: CGSize) -> [TreemapTile] {
        guard let tree, size.width > 0, size.height > 0 else { return [] }
        let key = TreemapKey(focus: focus, version: version, metric: metric, depth: min(ringCount, 5),
                             width: Int(size.width), height: Int(size.height))
        if let cache = treemapCache, cache.key == key { return cache.value }
        let value = TreemapLayout.layout(tree: tree, root: focus, metric: metric,
                                         bounds: CGRect(origin: .zero, size: size), maxDepth: min(ringCount, 5))
        treemapCache = (key, value)
        return value
    }

    func tableRows() -> [NodeID] {
        guard let tree else { return [] }
        let key = RowsKey(focus: focus, version: version, metric: metric, sort: sortKey, ascending: sortAscending)
        if let cache = rowsCache, cache.key == key { return cache.value }
        let children = tree.visibleChildren(of: focus, sortedBy: metric)
        let sorted: [NodeID]
        switch sortKey {
        case .size:
            sorted = sortAscending ? Array(children.reversed()) : children
        case .name:
            sorted = children.sorted {
                let order = tree[$0].name.localizedStandardCompare(tree[$1].name)
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            }
        case .items:
            sorted = children.sorted {
                sortAscending ? tree[$0].itemCount < tree[$1].itemCount : tree[$0].itemCount > tree[$1].itemCount
            }
        case .modified:
            sorted = children.sorted {
                sortAscending ? tree[$0].modified < tree[$1].modified : tree[$0].modified > tree[$1].modified
            }
        case .kind:
            sorted = children.sorted {
                let lhs = Kinds.describe(tree[$0]), rhs = Kinds.describe(tree[$1])
                return sortAscending ? lhs < rhs : lhs > rhs
            }
        }
        rowsCache = (key, sorted)
        return sorted
    }

    func suggestions() -> [CleanupSuggestion] {
        guard let tree else { return [] }
        let key = SuggestionsKey(tree: ObjectIdentifier(tree), version: version, metric: metric)
        if let cache = suggestionsCache, cache.key == key { return cache.value }
        let value = CleanupAdvisor.analyze(tree: tree, metric: metric)
        suggestionsCache = (key, value)
        return value
    }

    // MARK: Item actions

    func path(of id: NodeID) -> String? { tree?.path(of: id) }

    func reveal(_ id: NodeID) {
        guard let tree else { return }
        NSWorkspace.shared.activateFileViewerSelecting([tree.url(of: id)])
    }

    func quickLook(_ id: NodeID) {
        guard let tree else { return }
        quickLookURL = tree.url(of: id)
    }

    func open(item id: NodeID) {
        guard let tree else { return }
        if tree[id].isDirectory && !tree[id].isPackage {
            zoom(to: id)
        } else {
            NSWorkspace.shared.open(tree.url(of: id))
        }
    }

    func safety(of id: NodeID) -> SafetyVerdict {
        guard let tree else { return .blocked("Nothing scanned") }
        return Safety.verdict(for: tree.path(of: id))
    }

    // MARK: Purge basket

    func isInBasket(_ id: NodeID) -> Bool { basket.contains(id) }

    func toggleBasket(_ id: NodeID) {
        if let index = basket.firstIndex(of: id) {
            basket.remove(at: index)
        } else {
            addToBasket([id])
        }
    }

    func addToBasket(_ ids: [NodeID]) {
        guard let tree else { return }
        for id in ids where !basket.contains(id) && !safety(of: id).isBlocked && !tree.isEffectivelyRemoved(id) {
            // Adding a folder supersedes anything already staged inside it.
            basket.removeAll { tree.isAncestor(id, of: $0) }
            if basket.contains(where: { tree.isAncestor($0, of: id) }) { continue }
            basket.append(id)
        }
    }

    func addToBasket(path: String) {
        guard let id = tree?.node(atPath: path) else { return }
        addToBasket([id])
    }

    func clearBasket() { basket = [] }

    var basketSize: Int64 {
        guard let tree else { return 0 }
        return basket.reduce(0) { $0 + tree[$1].size(.physical) }
    }

    // MARK: Deletion

    private var undoManager: UndoManager? {
        NSApp.mainWindow?.undoManager ?? NSApp.keyWindow?.undoManager
    }

    /// Moves items to the Trash after running the safety checks.
    func requestTrash(_ ids: [NodeID]) {
        guard let tree else { return }
        let candidates = ids.filter { !tree.isEffectivelyRemoved($0) }
        guard !candidates.isEmpty else { return }
        let blocked = candidates.filter { safety(of: $0).isBlocked }
        if !blocked.isEmpty {
            let names = blocked.map { "• \(tree[$0].name) — \(safety(of: $0).message ?? "")" }
            alert = AlertItem(title: "Protected Item", message: "Pelican will not delete:\n" + names.joined(separator: "\n"))
            return
        }
        let cautions = candidates.compactMap { id -> String? in
            if case .caution(let reason) = safety(of: id) { return "• \(tree[id].name): \(reason)" }
            return nil
        }
        if cautions.isEmpty {
            performTrash(candidates)
        } else {
            alert = AlertItem(title: "Move to Trash?",
                              message: "Please double-check:\n" + cautions.joined(separator: "\n"),
                              confirmTitle: "Move to Trash") { [weak self] in self?.performTrash(candidates) }
        }
    }

    func requestPermanentDelete(_ ids: [NodeID]) {
        guard let tree else { return }
        let candidates = ids.filter { !tree.isEffectivelyRemoved($0) }
        guard !candidates.isEmpty else { return }
        if let blocked = candidates.first(where: { safety(of: $0).isBlocked }) {
            alert = AlertItem(title: "Protected Item",
                              message: "Pelican will not delete “\(tree[blocked].name)”: \(safety(of: blocked).message ?? "")")
            return
        }
        let total = candidates.reduce(Int64(0)) { $0 + tree[$1].size(.physical) }
        let subject = candidates.count == 1 ? "“\(tree[candidates[0]].name)”" : "\(candidates.count) items"
        alert = AlertItem(title: "Delete \(subject) permanently?",
                          message: "\(Format.bytes(total)) will be erased immediately. This cannot be undone.",
                          confirmTitle: "Delete Permanently") { [weak self] in self?.performPermanentDelete(candidates) }
    }

    private struct TrashRecord {
        let id: NodeID
        let original: URL
        let trashed: URL
    }

    func performTrash(_ ids: [NodeID]) {
        guard let tree else { return }
        var records: [TrashRecord] = []
        var failures: [String] = []
        for id in ids where !tree.isEffectivelyRemoved(id) {
            let original = tree.url(of: id)
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: original, resultingItemURL: &resulting)
                tree.markRemoved(id)
                records.append(TrashRecord(id: id, original: original, trashed: (resulting as URL?) ?? original))
            } catch {
                failures.append("\(tree[id].name): \(error.localizedDescription)")
            }
        }
        didMutateTree()
        if !records.isEmpty, let undoManager {
            undoManager.registerUndo(withTarget: self) { model in model.restoreFromTrash(records) }
            undoManager.setActionName(records.count == 1 ? "Move to Trash" : "Move \(records.count) Items to Trash")
        }
        reportFailures(failures)
    }

    private func restoreFromTrash(_ records: [TrashRecord]) {
        guard let tree else { return }
        var restored: [NodeID] = []
        var failures: [String] = []
        for record in records {
            do {
                try FileManager.default.moveItem(at: record.trashed, to: record.original)
                tree.restore(record.id)
                restored.append(record.id)
            } catch {
                failures.append("\(record.original.lastPathComponent): \(error.localizedDescription)")
            }
        }
        didMutateTree()
        if !restored.isEmpty, let undoManager {
            undoManager.registerUndo(withTarget: self) { model in model.performTrash(restored) }
            undoManager.setActionName("Move to Trash")
        }
        reportFailures(failures)
    }

    private func performPermanentDelete(_ ids: [NodeID]) {
        guard let tree else { return }
        let jobs = ids.map { (id: $0, url: tree.url(of: $0), name: tree[$0].name) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var deleted: [NodeID] = []
            var failures: [String] = []
            for job in jobs {
                do {
                    try FileManager.default.removeItem(at: job.url)
                    deleted.append(job.id)
                } catch {
                    failures.append("\(job.name): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                guard let self, self.tree === tree else { return }
                deleted.forEach { tree.markRemoved($0) }
                self.didMutateTree()
                self.reportFailures(failures)
            }
        }
    }

    func trashBasket() {
        requestTrash(basket)
    }

    private func reportFailures(_ failures: [String]) {
        guard !failures.isEmpty else { return }
        alert = AlertItem(title: "Some items could not be removed",
                          message: failures.joined(separator: "\n")
                            + "\n\nItems owned by the system or another user may need Full Disk Access or administrator rights.")
    }

    private func didMutateTree() {
        guard let tree else { return }
        let newFocus = tree.liveAncestor(of: focus)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            version += 1
            focus = newFocus
        }
        if let selection, tree.isEffectivelyRemoved(selection) { self.selection = nil }
        basket.removeAll { tree.isEffectivelyRemoved($0) }
        interaction.reset()
        refreshVolumes()
        refreshShortcutSizes()
    }

    // MARK: Keyboard

    /// Space toggles Quick Look for the hovered / selected item, like Finder.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            if self.quickLookURL != nil {
                self.quickLookURL = nil
                return nil
            }
            if let target = self.actionTarget {
                self.quickLook(target)
                return nil
            }
            return event
        }
    }
}
