import Foundation

typealias NodeID = Int32

enum SizeMetric: String, CaseIterable, Identifiable {
    /// Allocated blocks on disk (what you actually get back when deleting).
    case physical
    /// Logical file length (what Finder calls "size").
    case logical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .physical: return "Size on Disk"
        case .logical: return "Logical Size"
        }
    }
}

struct NodeFlags: OptionSet {
    let rawValue: UInt8

    static let directory = NodeFlags(rawValue: 1 << 0)
    static let package = NodeFlags(rawValue: 1 << 1)
    static let symlink = NodeFlags(rawValue: 1 << 2)
    static let removed = NodeFlags(rawValue: 1 << 3)
    static let unreadable = NodeFlags(rawValue: 1 << 4)
    static let hardlinkDuplicate = NodeFlags(rawValue: 1 << 5)
}

/// One file system entry. Kept as a small value type stored contiguously in `FileTree.nodes`
/// so that a multi-million node tree stays compact and cache friendly.
struct FileNode {
    var name: String
    var parent: NodeID
    var children: ContiguousArray<NodeID>
    var logicalSize: Int64
    var physicalSize: Int64
    /// Recursive number of descendants (files and folders).
    var itemCount: Int32
    /// Modification time, seconds since 1970.
    var modified: Double
    var flags: NodeFlags
    var category: FileCategory

    init(name: String, parent: NodeID, logicalSize: Int64, physicalSize: Int64, modified: Double,
         flags: NodeFlags, category: FileCategory) {
        self.name = name
        self.parent = parent
        self.children = []
        self.logicalSize = logicalSize
        self.physicalSize = physicalSize
        self.itemCount = 0
        self.modified = modified
        self.flags = flags
        self.category = category
    }

    var isDirectory: Bool { flags.contains(.directory) }
    var isPackage: Bool { flags.contains(.package) }
    var isRemoved: Bool { flags.contains(.removed) }

    func size(_ metric: SizeMetric) -> Int64 {
        metric == .physical ? physicalSize : logicalSize
    }
}

/// Flat, index-based file tree. Parents are always stored before their children
/// (`parent < child`), which lets aggregation run as a single reverse sweep.
final class FileTree: @unchecked Sendable {
    static let root: NodeID = 0

    let rootPath: String
    var nodes: ContiguousArray<FileNode>

    init(rootPath: String) {
        self.rootPath = rootPath
        let displayName = FileManager.default.displayName(atPath: rootPath)
        var modified: Double = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: rootPath),
           let date = attributes[.modificationDate] as? Date {
            modified = date.timeIntervalSince1970
        }
        let (category, isPackage) = FileCategory.forDirectory(named: (rootPath as NSString).lastPathComponent)
        var flags: NodeFlags = [.directory]
        if isPackage { flags.insert(.package) }
        nodes = [FileNode(name: displayName.isEmpty ? rootPath : displayName, parent: -1, logicalSize: 0,
                          physicalSize: 0, modified: modified, flags: flags, category: category)]
    }

    var count: Int { nodes.count }

    subscript(id: NodeID) -> FileNode { nodes[Int(id)] }

    // MARK: Paths

    func path(of id: NodeID) -> String {
        var components: [String] = []
        var current = id
        while current > FileTree.root {
            components.append(nodes[Int(current)].name)
            current = nodes[Int(current)].parent
        }
        var path = rootPath
        for component in components.reversed() {
            if !path.hasSuffix("/") { path += "/" }
            path += component
        }
        return path
    }

    func url(of id: NodeID) -> URL {
        URL(fileURLWithPath: path(of: id), isDirectory: self[id].isDirectory)
    }

    /// Chain from the root down to (and including) `id`.
    func ancestors(of id: NodeID) -> [NodeID] {
        var chain: [NodeID] = []
        var current = id
        while current >= 0 {
            chain.append(current)
            current = nodes[Int(current)].parent
        }
        return chain.reversed()
    }

    func depth(of id: NodeID) -> Int {
        var depth = 0
        var current = nodes[Int(id)].parent
        while current >= 0 {
            depth += 1
            current = nodes[Int(current)].parent
        }
        return depth
    }

    func isAncestor(_ ancestor: NodeID, of id: NodeID) -> Bool {
        var current = id
        while current >= 0 {
            if current == ancestor { return true }
            current = nodes[Int(current)].parent
        }
        return false
    }

    /// Looks up the node for an absolute path inside this tree.
    func node(atPath path: String) -> NodeID? {
        let normalized = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        if normalized == rootPath { return FileTree.root }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard normalized.hasPrefix(prefix) else { return nil }
        var current = FileTree.root
        for component in normalized.dropFirst(prefix.count).split(separator: "/") {
            guard let next = nodes[Int(current)].children.first(where: {
                nodes[Int($0)].name == component && !nodes[Int($0)].isRemoved
            }) else { return nil }
            current = next
        }
        return current
    }

    // MARK: Children

    func visibleChildren(of id: NodeID, sortedBy metric: SizeMetric) -> [NodeID] {
        let children = nodes[Int(id)].children.filter { !nodes[Int($0)].isRemoved }
        return children.sorted { nodes[Int($0)].size(metric) > nodes[Int($1)].size(metric) }
    }

    // MARK: Aggregation

    /// Rolls sizes and item counts up to every directory and derives a dominant
    /// category for plain folders. Call once after the scan has added all nodes.
    func finalize() {
        let count = nodes.count
        guard count > 1 else { return }
        var bestChildSize = [Int64](repeating: -1, count: count)
        var bestChildCategory = [FileCategory](repeating: .other, count: count)

        for index in stride(from: count - 1, through: 0, by: -1) {
            // All descendants have larger indices, so this node is complete now.
            if nodes[index].isDirectory && nodes[index].category == .folder && bestChildSize[index] >= 0 {
                let dominant = bestChildCategory[index]
                nodes[index].category = dominant == .folder ? .other : dominant
            }
            let parent = Int(nodes[index].parent)
            guard parent >= 0 else { continue }
            let node = nodes[index]
            nodes[parent].logicalSize += node.logicalSize
            nodes[parent].physicalSize += node.physicalSize
            nodes[parent].itemCount += node.itemCount + 1
            if node.physicalSize > bestChildSize[parent] {
                bestChildSize[parent] = node.physicalSize
                bestChildCategory[parent] = node.category
            }
        }
    }

    // MARK: Mutation (deletion without rescanning)

    /// Marks a node as removed and subtracts its totals from all ancestors.
    @discardableResult
    func markRemoved(_ id: NodeID) -> Bool {
        guard id != FileTree.root, !nodes[Int(id)].isRemoved else { return false }
        nodes[Int(id)].flags.insert(.removed)
        adjustAncestors(of: id, sign: -1)
        return true
    }

    /// Reverses `markRemoved` (used for undo).
    func restore(_ id: NodeID) {
        guard nodes[Int(id)].isRemoved else { return }
        nodes[Int(id)].flags.remove(.removed)
        adjustAncestors(of: id, sign: 1)
    }

    private func adjustAncestors(of id: NodeID, sign: Int64) {
        let node = nodes[Int(id)]
        var current = node.parent
        while current >= 0 {
            nodes[Int(current)].logicalSize += sign * node.logicalSize
            nodes[Int(current)].physicalSize += sign * node.physicalSize
            nodes[Int(current)].itemCount += Int32(sign) * (node.itemCount + 1)
            current = nodes[Int(current)].parent
        }
    }

    /// Whether the node or any ancestor has been removed.
    func isEffectivelyRemoved(_ id: NodeID) -> Bool {
        var current = id
        while current >= 0 {
            if nodes[Int(current)].isRemoved { return true }
            current = nodes[Int(current)].parent
        }
        return false
    }

    /// Nearest ancestor (or self) that is still present.
    func liveAncestor(of id: NodeID) -> NodeID {
        let chain = ancestors(of: id)
        if let firstRemoved = chain.firstIndex(where: { nodes[Int($0)].isRemoved }) {
            return chain[max(0, firstRemoved - 1)]
        }
        return id
    }
}
