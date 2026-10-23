import Foundation

/// Parallel file system scanner. A pool of worker threads (one per core, so both
/// performance and efficiency cores on Apple Silicon take part) pull directories
/// from a shared stack, read them with `getattrlistbulk` outside the lock, then
/// append the results to the flat `FileTree` under the lock.
final class DiskScanner: @unchecked Sendable {
    struct Progress: Equatable {
        var items = 0
        var directories = 0
        var bytes: Int64 = 0
    }

    /// When scanning the boot volume, skip paths that are other volumes or firmlinked
    /// duplicates of the Data volume, which would otherwise be counted twice.
    static let rootSkipList: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/Network", "/.vol", "/.nofollow", "/.resolve",
    ]

    let threadCount: Int

    private let condition = NSCondition()
    private var pending: [(id: NodeID, path: String)] = []
    private var active = 0
    private var cancelled = false
    private var progressState = Progress()
    private var seenHardLinks = Set<UInt64>()
    private var skipPaths: Set<String> = []
    private var tree: FileTree?

    init(threadCount: Int = max(2, ProcessInfo.processInfo.activeProcessorCount)) {
        self.threadCount = threadCount
    }

    var progress: Progress {
        condition.lock()
        defer { condition.unlock() }
        return progressState
    }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    /// Scans `path` on background threads. `completion` runs on a background queue
    /// with the finished tree, or `nil` when cancelled.
    func scan(path: String, completion: @escaping (FileTree?) -> Void) {
        let rootPath = DiskScanner.normalize(path)
        let tree = FileTree(rootPath: rootPath)
        condition.lock()
        self.tree = tree
        pending = [(FileTree.root, rootPath)]
        active = 0
        progressState = Progress()
        seenHardLinks.removeAll()
        skipPaths = rootPath == "/" ? DiskScanner.rootSkipList : []
        condition.unlock()

        let group = DispatchGroup()
        for index in 0..<threadCount {
            group.enter()
            let thread = Thread { [self] in
                self.workerLoop()
                group.leave()
            }
            thread.name = "Pelican.scan.\(index)"
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 20
            thread.start()
        }
        group.notify(queue: .global(qos: .userInitiated)) { [self] in
            if self.isCancelled {
                completion(nil)
                return
            }
            tree.finalize()
            completion(tree)
        }
    }

    /// Blocking variant, used by tests and command-line style callers.
    func scanSync(path: String) -> FileTree? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: FileTree?
        scan(path: path) { tree in
            result = tree
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    static func normalize(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    private struct PreparedChild {
        var node: FileNode
        var path: String
        var fileID: UInt64
        var checkHardLink: Bool
    }

    private func workerLoop() {
        let bufferSize = BulkDirectoryReader.recommendedBufferSize
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var prepared: [PreparedChild] = []
        prepared.reserveCapacity(512)

        while true {
            condition.lock()
            while pending.isEmpty && active > 0 && !cancelled {
                condition.wait()
            }
            if cancelled || pending.isEmpty {
                condition.broadcast()
                condition.unlock()
                return
            }
            let job = pending.removeLast()
            active += 1
            let skip = skipPaths
            condition.unlock()

            // Expensive part runs without holding the lock.
            prepared.removeAll(keepingCapacity: true)
            let readable = BulkDirectoryReader.read(path: job.path, buffer: buffer, bufferSize: bufferSize) { entry in
                let childPath = job.path == "/" ? "/" + entry.name : job.path + "/" + entry.name
                if entry.isDirectory && skip.contains(childPath) { return }
                var flags: NodeFlags = []
                let category: FileCategory
                if entry.isDirectory {
                    flags.insert(.directory)
                    let info = FileCategory.forDirectory(named: entry.name)
                    category = info.category
                    if info.isPackage { flags.insert(.package) }
                } else if entry.isSymlink {
                    flags.insert(.symlink)
                    category = .other
                } else {
                    category = FileCategory.forFile(named: entry.name)
                }
                let node = FileNode(name: entry.name, parent: job.id, logicalSize: entry.logicalSize,
                                    physicalSize: entry.physicalSize, modified: entry.modified,
                                    flags: flags, category: category)
                prepared.append(PreparedChild(node: node, path: childPath, fileID: entry.fileID,
                                              checkHardLink: !entry.isDirectory && entry.linkCount > 1))
            }

            condition.lock()
            if let tree {
                if !readable {
                    tree.nodes[Int(job.id)].flags.insert(.unreadable)
                }
                var childIDs = ContiguousArray<NodeID>()
                childIDs.reserveCapacity(prepared.count)
                for var child in prepared {
                    // Count hard-linked files only once.
                    if child.checkHardLink && !seenHardLinks.insert(child.fileID).inserted {
                        child.node.logicalSize = 0
                        child.node.physicalSize = 0
                        child.node.flags.insert(.hardlinkDuplicate)
                    }
                    let id = NodeID(tree.nodes.count)
                    tree.nodes.append(child.node)
                    childIDs.append(id)
                    if child.node.isDirectory {
                        pending.append((id, child.path))
                        progressState.directories += 1
                    }
                    progressState.bytes += child.node.physicalSize
                }
                tree.nodes[Int(job.id)].children = childIDs
                progressState.items += prepared.count
            }
            active -= 1
            condition.broadcast()
            condition.unlock()
        }
    }

    // MARK: Lightweight sizing

    struct Totals {
        var logical: Int64 = 0
        var physical: Int64 = 0
        var items = 0
    }

    /// Single-threaded size of a path without building a tree; used for sidebar
    /// badges and application bundles.
    static func totals(of path: String) -> Totals {
        var totals = Totals()
        var info = stat()
        guard lstat(path, &info) == 0 else { return totals }
        if UInt32(info.st_mode) & 0o170000 != 0o040000 {
            totals.logical = Int64(info.st_size)
            totals.physical = Int64(info.st_blocks) * 512
            totals.items = 1
            return totals
        }
        let bufferSize = BulkDirectoryReader.recommendedBufferSize
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        var stack = [path]
        while let directory = stack.popLast() {
            BulkDirectoryReader.read(path: directory, buffer: buffer, bufferSize: bufferSize) { entry in
                totals.items += 1
                if entry.isDirectory {
                    stack.append(directory + "/" + entry.name)
                } else {
                    totals.logical += entry.logicalSize
                    totals.physical += entry.physicalSize
                }
            }
        }
        return totals
    }
}
