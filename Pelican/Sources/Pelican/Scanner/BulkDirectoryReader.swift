import Darwin

/// One directory entry as returned by the kernel.
struct BulkEntry {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var logicalSize: Int64
    var physicalSize: Int64
    var modified: Double
    var fileID: UInt64
    var linkCount: UInt32
}

/// Reads whole directories with `getattrlistbulk(2)`: names, types, sizes and
/// timestamps for many entries come back in one syscall, which is several times
/// faster than `readdir` + `lstat` per file.
enum BulkDirectoryReader {
    private static let cmnReturnedAttrs = attrgroup_t(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS)
    private static let cmnName = attrgroup_t(truncatingIfNeeded: ATTR_CMN_NAME)
    private static let cmnError = attrgroup_t(truncatingIfNeeded: ATTR_CMN_ERROR)
    private static let cmnObjType = attrgroup_t(truncatingIfNeeded: ATTR_CMN_OBJTYPE)
    private static let cmnModTime = attrgroup_t(truncatingIfNeeded: ATTR_CMN_MODTIME)
    private static let cmnFileID = attrgroup_t(truncatingIfNeeded: ATTR_CMN_FILEID)
    private static let fileLinkCount = attrgroup_t(truncatingIfNeeded: ATTR_FILE_LINKCOUNT)
    private static let fileTotalSize = attrgroup_t(truncatingIfNeeded: ATTR_FILE_TOTALSIZE)
    private static let fileAllocSize = attrgroup_t(truncatingIfNeeded: ATTR_FILE_ALLOCSIZE)

    // fsobj_type_t values from <sys/vnode.h>
    private static let typeDirectory: UInt32 = 2
    private static let typeSymlink: UInt32 = 5

    static let recommendedBufferSize = 256 * 1024

    /// Calls `body` for each entry in the directory. Returns false if the directory
    /// could not be opened or read (e.g. permission denied).
    @discardableResult
    static func read(path: String, buffer: UnsafeMutableRawPointer, bufferSize: Int,
                     _ body: (BulkEntry) -> Void) -> Bool {
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = cmnReturnedAttrs | cmnName | cmnError | cmnObjType | cmnModTime | cmnFileID
        request.fileattr = fileLinkCount | fileTotalSize | fileAllocSize

        var deliveredAny = false
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count == 0 { return true }
            if count < 0 {
                if errno == EINTR { continue }
                if !deliveredAny && (errno == ENOTSUP || errno == EINVAL) {
                    return readFallback(path: path, body)
                }
                return deliveredAny
            }
            deliveredAny = true
            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<Int(count) {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if let parsed = parse(entry: entry) {
                    body(parsed)
                }
                entry += length
            }
        }
    }

    /// Parses one packed entry. Attributes appear in bit order and only if they are
    /// set in the returned attribute set, so each one is checked before reading.
    private static func parse(entry: UnsafeRawPointer) -> BulkEntry? {
        var field = entry + MemoryLayout<UInt32>.size
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        if returned.commonattr & cmnError != 0 {
            let error = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            if error != 0 { return nil }
        }

        var name = ""
        if returned.commonattr & cmnName != 0 {
            let reference = field.loadUnaligned(as: attrreference_t.self)
            let nameStart = field + Int(reference.attr_dataoffset)
            let nameLength = max(0, Int(reference.attr_length) - 1) // drop the NUL terminator
            name = String(decoding: UnsafeRawBufferPointer(start: nameStart, count: nameLength), as: UTF8.self)
            field += MemoryLayout<attrreference_t>.size
        }
        guard !name.isEmpty else { return nil }

        var objectType: UInt32 = 0
        if returned.commonattr & cmnObjType != 0 {
            objectType = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }

        var modified: Double = 0
        if returned.commonattr & cmnModTime != 0 {
            let time = field.loadUnaligned(as: timespec.self)
            modified = Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
            field += MemoryLayout<timespec>.size
        }

        var fileID: UInt64 = 0
        if returned.commonattr & cmnFileID != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }

        var linkCount: UInt32 = 1
        if returned.fileattr & fileLinkCount != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }

        var logical: Int64 = 0
        if returned.fileattr & fileTotalSize != 0 {
            logical = field.loadUnaligned(as: Int64.self)
            field += MemoryLayout<Int64>.size
        }

        var physical: Int64 = 0
        if returned.fileattr & fileAllocSize != 0 {
            physical = field.loadUnaligned(as: Int64.self)
            field += MemoryLayout<Int64>.size
        }

        let isDirectory = objectType == typeDirectory
        return BulkEntry(name: name,
                         isDirectory: isDirectory,
                         isSymlink: objectType == typeSymlink,
                         logicalSize: isDirectory ? 0 : logical,
                         physicalSize: isDirectory ? 0 : physical,
                         modified: modified,
                         fileID: fileID,
                         linkCount: linkCount)
    }

    /// Portable fallback for file systems that do not implement bulk attributes.
    private static func readFallback(path: String, _ body: (BulkEntry) -> Void) -> Bool {
        guard let directory = opendir(path) else { return false }
        defer { closedir(directory) }
        while let item = readdir(directory) {
            let nameLength = Int(item.pointee.d_namlen)
            let name = withUnsafeBytes(of: item.pointee.d_name) { raw in
                String(decoding: raw.prefix(nameLength), as: UTF8.self)
            }
            if name == "." || name == ".." || name.isEmpty { continue }
            let fullPath = path.hasSuffix("/") ? path + name : path + "/" + name
            var info = stat()
            guard lstat(fullPath, &info) == 0 else { continue }
            let format = UInt32(info.st_mode) & 0o170000
            let isDirectory = format == 0o040000
            body(BulkEntry(name: name,
                           isDirectory: isDirectory,
                           isSymlink: format == 0o120000,
                           logicalSize: isDirectory ? 0 : Int64(info.st_size),
                           physicalSize: isDirectory ? 0 : Int64(info.st_blocks) * 512,
                           modified: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9,
                           fileID: UInt64(info.st_ino),
                           linkCount: UInt32(info.st_nlink)))
        }
        return true
    }
}
