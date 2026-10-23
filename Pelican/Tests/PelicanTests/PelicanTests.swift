import CoreGraphics
import XCTest
@testable import Pelican

/// Builds small trees by hand.
private final class TreeBuilder {
    let tree: FileTree

    init(rootPath: String = "/tmp/pelican-test-root") {
        tree = FileTree(rootPath: rootPath)
    }

    @discardableResult
    func add(_ name: String, under parent: NodeID = FileTree.root, size: Int64 = 0, directory: Bool = false,
             modified: Double = Date().timeIntervalSince1970) -> NodeID {
        var flags: NodeFlags = []
        let category: FileCategory
        if directory {
            flags.insert(.directory)
            let info = FileCategory.forDirectory(named: name)
            category = info.category
            if info.isPackage { flags.insert(.package) }
        } else {
            category = FileCategory.forFile(named: name)
        }
        let id = NodeID(tree.nodes.count)
        tree.nodes.append(FileNode(name: name, parent: parent, logicalSize: size, physicalSize: size,
                                   modified: modified, flags: flags, category: category))
        tree.nodes[Int(parent)].children.append(id)
        return id
    }
}

final class FileTreeTests: XCTestCase {
    func testAggregationAndCounts() {
        let builder = TreeBuilder()
        let docs = builder.add("docs", directory: true)
        builder.add("a.pdf", under: docs, size: 100)
        builder.add("b.pdf", under: docs, size: 50)
        let media = builder.add("media", directory: true)
        let raw = builder.add("raw", under: media, directory: true)
        builder.add("c.mov", under: raw, size: 1000)
        builder.tree.finalize()

        let tree = builder.tree
        XCTAssertEqual(tree[FileTree.root].physicalSize, 1150)
        XCTAssertEqual(tree[docs].physicalSize, 150)
        XCTAssertEqual(tree[media].physicalSize, 1000)
        XCTAssertEqual(tree[FileTree.root].itemCount, 6)
        XCTAssertEqual(tree[docs].itemCount, 2)
        XCTAssertEqual(tree[docs].category, .document, "folders take the category of their largest child")
        XCTAssertEqual(tree[media].category, .media)
    }

    func testPathsAndLookup() {
        let builder = TreeBuilder(rootPath: "/Users/test")
        let library = builder.add("Library", directory: true)
        let caches = builder.add("Caches", under: library, directory: true)
        let file = builder.add("blob.cache", under: caches, size: 10)
        let tree = builder.tree

        XCTAssertEqual(tree.path(of: FileTree.root), "/Users/test")
        XCTAssertEqual(tree.path(of: file), "/Users/test/Library/Caches/blob.cache")
        XCTAssertEqual(tree.node(atPath: "/Users/test/Library/Caches"), caches)
        XCTAssertEqual(tree.node(atPath: "/Users/test/Library/Caches/"), caches)
        XCTAssertNil(tree.node(atPath: "/Users/testing/Library"))
        XCTAssertNil(tree.node(atPath: "/Users/test/Missing"))
        XCTAssertEqual(tree.ancestors(of: file), [FileTree.root, library, caches, file])
        XCTAssertTrue(tree.isAncestor(library, of: file))
        XCTAssertFalse(tree.isAncestor(file, of: library))
    }

    func testRootPathIsSlash() {
        let builder = TreeBuilder(rootPath: "/")
        let users = builder.add("Users", directory: true)
        XCTAssertEqual(builder.tree.path(of: users), "/Users")
        XCTAssertEqual(builder.tree.node(atPath: "/Users"), users)
    }

    func testRemoveAndRestore() {
        let builder = TreeBuilder()
        let folder = builder.add("folder", directory: true)
        let big = builder.add("big.zip", under: folder, size: 700)
        builder.add("small.txt", under: folder, size: 300)
        builder.tree.finalize()
        let tree = builder.tree

        XCTAssertTrue(tree.markRemoved(big))
        XCTAssertFalse(tree.markRemoved(big), "removing twice is a no-op")
        XCTAssertEqual(tree[folder].physicalSize, 300)
        XCTAssertEqual(tree[FileTree.root].physicalSize, 300)
        XCTAssertEqual(tree[FileTree.root].itemCount, 2)
        XCTAssertEqual(tree.visibleChildren(of: folder, sortedBy: .physical).count, 1)
        XCTAssertNil(tree.node(atPath: tree.rootPath + "/folder/big.zip"))

        tree.restore(big)
        XCTAssertEqual(tree[FileTree.root].physicalSize, 1000)
        XCTAssertEqual(tree[FileTree.root].itemCount, 3)

        tree.markRemoved(folder)
        XCTAssertTrue(tree.isEffectivelyRemoved(big))
        XCTAssertEqual(tree.liveAncestor(of: big), FileTree.root)
    }
}

final class ScannerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PelicanScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let locked = directory.appendingPathComponent("locked")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ relativePath: String, bytes: Int) throws {
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testScanMatchesFileSystem() throws {
        try write("a.txt", bytes: 1_000)
        try write("nested/b.bin", bytes: 20_000)
        try write("nested/deeper/c.mov", bytes: 300_000)
        try write("Ünïcödé fïlé.txt", bytes: 5)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("link").path,
                                                   withDestinationPath: directory.appendingPathComponent("nested").path)
        try FileManager.default.linkItem(atPath: directory.appendingPathComponent("nested/b.bin").path,
                                         toPath: directory.appendingPathComponent("nested/hardlink.bin").path)

        let tree = try XCTUnwrap(DiskScanner(threadCount: 4).scanSync(path: directory.path))
        let root = tree[FileTree.root]

        // Hard-linked data counted once; the symlink is not followed.
        XCTAssertEqual(root.logicalSize, 1_000 + 20_000 + 300_000 + 5 + Int64(tree[tree.node(atPath: directory.path + "/link")!].logicalSize))
        XCTAssertGreaterThanOrEqual(root.physicalSize, 320_000, "allocated size covers the large files")
        XCTAssertNotNil(tree.node(atPath: directory.path + "/Ünïcödé fïlé.txt"))

        let nested = try XCTUnwrap(tree.node(atPath: directory.path + "/nested"))
        XCTAssertEqual(tree[nested].logicalSize, 320_000)
        XCTAssertEqual(tree[nested].itemCount, 4) // b.bin, hardlink.bin, deeper, c.mov
        let link = try XCTUnwrap(tree.node(atPath: directory.path + "/link"))
        XCTAssertTrue(tree[link].flags.contains(.symlink))
        XCTAssertFalse(tree[link].isDirectory)

        let movie = try XCTUnwrap(tree.node(atPath: directory.path + "/nested/deeper/c.mov"))
        XCTAssertEqual(tree[movie].category, .media)
        XCTAssertGreaterThan(tree[movie].modified, Date().timeIntervalSince1970 - 3600)

        // Parents always precede children.
        for index in 1..<tree.count {
            XCTAssertLessThan(Int(tree.nodes[index].parent), index)
        }

        let totals = DiskScanner.totals(of: directory.path + "/nested/deeper")
        XCTAssertEqual(totals.logical, 300_000)
        XCTAssertEqual(totals.items, 1)
    }

    func testUnreadableDirectoryIsFlagged() throws {
        try write("locked/secret.txt", bytes: 10)
        let locked = directory.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        guard getuid() != 0 else { throw XCTSkip("root can read everything") }

        let tree = try XCTUnwrap(DiskScanner().scanSync(path: directory.path))
        let id = try XCTUnwrap(tree.node(atPath: locked.path))
        XCTAssertTrue(tree[id].flags.contains(.unreadable))
    }

    func testCancel() throws {
        try write("x.txt", bytes: 10)
        let scanner = DiskScanner()
        let finished = expectation(description: "completion")
        scanner.cancel()
        scanner.scan(path: directory.path) { tree in
            XCTAssertNil(tree)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
    }
}

final class LayoutTests: XCTestCase {
    func testSquarifyFillsBoundsWithoutOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let raw: [Double] = [50, 25, 10, 8, 4, 2, 1]
        let total = raw.reduce(0, +)
        let values = raw.map { $0 / total * Double(bounds.width * bounds.height) }
        let rects = TreemapLayout.squarify(values: values, in: bounds)

        XCTAssertEqual(rects.count, values.count)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        XCTAssertEqual(area, Double(bounds.width * bounds.height), accuracy: 1)
        for (rect, value) in zip(rects, values) {
            XCTAssertEqual(Double(rect.width * rect.height), value, accuracy: 0.5)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    func testLayoutsRespectHierarchy() {
        let builder = TreeBuilder()
        let a = builder.add("a", directory: true)
        builder.add("a1.mov", under: a, size: 600)
        builder.add("a2.zip", under: a, size: 200)
        builder.add("b.pdf", size: 200)
        builder.tree.finalize()
        let tree = builder.tree

        let segments = SunburstLayout.layout(tree: tree, root: FileTree.root, metric: .physical, maxDepth: 4)
        XCTAssertEqual(segments.count, 4)
        let first = segments.first { $0.node == a }!
        XCTAssertEqual(first.end - first.start, 2 * .pi * 0.8, accuracy: 1e-9)
        for segment in segments where segment.depth == 1 {
            XCTAssertGreaterThanOrEqual(segment.start, first.start - 1e-9)
            XCTAssertLessThanOrEqual(segment.end, first.end + 1e-9)
        }

        let geometry = SunburstGeometry(size: CGSize(width: 400, height: 400), rings: 4)
        let probeRadius = geometry.innerRadius + geometry.ringWidth / 2
        // Just right of 12 o'clock on the first ring lands on the largest child.
        let probe = CGPoint(x: geometry.center.x + 2, y: geometry.center.y - probeRadius)
        XCTAssertEqual(geometry.hitTest(probe, segments: segments), .segment(segments.firstIndex { $0.node == a }!))
        XCTAssertEqual(geometry.hitTest(geometry.center, segments: segments), .center)

        let bounds = CGRect(x: 0, y: 0, width: 500, height: 300)
        let tiles = TreemapLayout.layout(tree: tree, root: FileTree.root, metric: .physical, bounds: bounds, maxDepth: 3)
        let parent = tiles.first { $0.node == a }!
        XCTAssertTrue(parent.isNested)
        for tile in tiles where tile.depth == 1 {
            XCTAssertTrue(parent.rect.insetBy(dx: -0.01, dy: -0.01).contains(tile.rect))
        }
    }
}

final class SafetyAndCategoryTests: XCTestCase {
    func testGuardrails() {
        let home = NSHomeDirectory()
        XCTAssertTrue(Safety.verdict(for: "/").isBlocked)
        XCTAssertTrue(Safety.verdict(for: "/System/Library/CoreServices").isBlocked)
        XCTAssertTrue(Safety.verdict(for: "/usr/bin/swift").isBlocked)
        XCTAssertTrue(Safety.verdict(for: home).isBlocked)
        XCTAssertTrue(Safety.verdict(for: home + "/Library").isBlocked)
        XCTAssertTrue(Safety.verdict(for: "/Volumes/External").isBlocked)
        XCTAssertEqual(Safety.verdict(for: "/usr/local/lib/thing"), .allowed)
        XCTAssertEqual(Safety.verdict(for: home + "/Library/Caches/com.example.app"), .allowed)
        XCTAssertEqual(Safety.verdict(for: "/Volumes/External/old.dmg"), .allowed)
        if case .caution = Safety.verdict(for: home + "/Library/Application Support/MobileSync/Backup/abc") {} else {
            XCTFail("device backups need a confirmation")
        }
        if case .caution = Safety.verdict(for: "/Applications/Some.app") {} else {
            XCTFail("apps need a confirmation")
        }
    }

    func testCategories() {
        XCTAssertEqual(FileCategory.forFile(named: "Movie.MOV"), .media)
        XCTAssertEqual(FileCategory.forFile(named: "installer.dmg"), .archive)
        XCTAssertEqual(FileCategory.forFile(named: "main.swift"), .code)
        XCTAssertEqual(FileCategory.forFile(named: ".gitignore"), .other)
        XCTAssertEqual(FileCategory.forFile(named: "README"), .other)
        XCTAssertEqual(FileCategory.forDirectory(named: "Xcode.app").category, .application)
        XCTAssertTrue(FileCategory.forDirectory(named: "Photos Library.photoslibrary").isPackage)
        XCTAssertEqual(FileCategory.forDirectory(named: "DerivedData").category, .code)
        XCTAssertFalse(FileCategory.forDirectory(named: "Projects").isPackage)
    }

    func testCleanupAdvisorFindsKnownJunk() {
        let mb: Int64 = 1024 * 1024
        let builder = TreeBuilder(rootPath: "/Users/someone")
        let library = builder.add("Library", directory: true)
        let caches = builder.add("Caches", under: library, directory: true)
        let appCache = builder.add("com.example.app", under: caches, directory: true)
        builder.add("blob", under: appCache, size: 300 * mb)
        let project = builder.add("project", directory: true)
        let modules = builder.add("node_modules", under: project, directory: true)
        builder.add("index.js", under: modules, size: 80 * mb)
        builder.add("tiny.dmg", size: 1 * mb)
        builder.add("old-installer.dmg", size: 900 * mb)
        builder.add("ancient.mov", size: 2_000 * mb, modified: Date().timeIntervalSince1970 - 400 * 24 * 3600)
        builder.add("fresh.mov", size: 2_000 * mb)
        builder.tree.finalize()

        let suggestions = CleanupAdvisor.analyze(tree: builder.tree, metric: .physical)
        let names = Set(suggestions.map { builder.tree[$0.node].name })
        XCTAssertEqual(names, ["com.example.app", "node_modules", "old-installer.dmg", "ancient.mov"])
        XCTAssertEqual(suggestions.first.map { builder.tree[$0.node].name }, "ancient.mov", "sorted by size")
    }
}
