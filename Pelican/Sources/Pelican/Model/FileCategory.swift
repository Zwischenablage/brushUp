import Foundation

/// Semantic category used for colour-coding the visualisation.
enum FileCategory: UInt8, CaseIterable {
    case folder
    case code
    case media
    case archive
    case system
    case document
    case application
    case other

    var label: String {
        switch self {
        case .folder: return "Folder"
        case .code: return "Code & Developer"
        case .media: return "Media"
        case .archive: return "Archives & Installers"
        case .system: return "System & Caches"
        case .document: return "Documents"
        case .application: return "Applications"
        case .other: return "Other"
        }
    }

    static func forFile(named name: String) -> FileCategory {
        guard let ext = fileExtension(of: name) else { return .other }
        return extensionMap[ext] ?? .other
    }

    /// Category and package flag for a directory entry.
    static func forDirectory(named name: String) -> (category: FileCategory, isPackage: Bool) {
        if let ext = fileExtension(of: name), let category = packageMap[ext] {
            return (category, true)
        }
        if let category = directoryNameMap[name] {
            return (category, false)
        }
        return (.folder, false)
    }

    /// Lower-cased extension without the dot. Fast path that avoids NSString bridging,
    /// since this runs for every file during a scan.
    static func fileExtension(of name: String) -> String? {
        let utf8 = name.utf8
        guard let dot = utf8.lastIndex(of: UInt8(ascii: ".")), dot != utf8.startIndex else { return nil }
        let start = utf8.index(after: dot)
        guard start != utf8.endIndex, utf8.distance(from: start, to: utf8.endIndex) <= 16 else { return nil }
        return String(name[start...]).lowercased()
    }

    private static let extensionMap: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ extensions: [String]) {
            for ext in extensions { map[ext] = category }
        }
        add(.code, ["swift", "m", "mm", "h", "hpp", "c", "cc", "cpp", "cxx", "js", "mjs", "cjs", "ts", "tsx", "jsx",
                    "py", "pyc", "rb", "go", "rs", "java", "class", "jar", "kt", "kts", "scala", "cs", "php", "lua",
                    "json", "yml", "yaml", "toml", "xml", "sh", "zsh", "o", "a", "dylib", "so", "swiftmodule",
                    "swiftdoc", "swiftinterface", "swiftsourceinfo", "pcm", "dia", "d", "wasm", "map", "lock",
                    "gguf", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel", "npy", "npz", "pb", "tflite",
                    "ipynb", "gradle", "pbxproj", "xcconfig", "metal", "metallib", "sql", "css", "scss", "vue"])
        add(.media, ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "raw", "cr2", "cr3", "nef", "arw",
                     "dng", "raf", "orf", "rw2", "psd", "psb", "ai", "svg", "webp", "bmp", "ico", "icns", "exr",
                     "hdr", "mov", "mp4", "m4v", "avi", "mkv", "webm", "mts", "m2ts", "braw", "r3d", "mxf", "mp3",
                     "m4a", "m4b", "aac", "wav", "aif", "aiff", "flac", "ogg", "opus", "caf", "mid", "blend",
                     "fbx", "obj", "usdz", "abc"])
        add(.archive, ["zip", "dmg", "pkg", "mpkg", "iso", "img", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z",
                       "rar", "xip", "ipa", "apk", "sparseimage", "cab", "deb", "rpm", "lz4", "vmdk", "qcow2", "vdi"])
        add(.system, ["cache", "db", "sqlite", "sqlite3", "sqlite-wal", "sqlite-shm", "log", "plist", "dat", "tmp",
                      "temp", "journal", "wal", "shm", "idx", "car", "nib", "strings", "asl", "ips", "crash",
                      "diag", "tracev3", "kext", "bom"])
        add(.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf",
                        "md", "markdown", "csv", "tsv", "epub", "html", "htm", "odt", "ods", "odp", "tex", "eml",
                        "emlx", "mbox", "vcf", "ics"])
        return map
    }()

    private static let packageMap: [String: FileCategory] = [
        "app": .application, "appex": .application, "prefpane": .application, "saver": .application,
        "framework": .code, "bundle": .code, "plugin": .code, "xcarchive": .code, "xcodeproj": .code,
        "xcworkspace": .code, "docset": .code, "xcframework": .code, "simruntime": .code, "playground": .code,
        "photoslibrary": .media, "fcpbundle": .media, "logicx": .media, "band": .media, "imovielibrary": .media,
        "tvlibrary": .media, "musiclibrary": .media, "lrlibrary": .media, "cocatalog": .media,
        "sparsebundle": .archive, "rtfd": .document, "kext": .system,
    ]

    private static let directoryNameMap: [String: FileCategory] = [
        "Caches": .system, "Cache": .system, "cache": .system, ".cache": .system, "Logs": .system,
        "tmp": .system, "CrashReporter": .system, "DiagnosticReports": .system,
        "DerivedData": .code, "node_modules": .code, ".git": .code, "Pods": .code, ".npm": .code,
        ".gradle": .code, ".cargo": .code, ".rustup": .code, "CoreSimulator": .code, "iOS DeviceSupport": .code,
        ".ollama": .code, "huggingface": .code, "__pycache__": .code, ".venv": .code, "venv": .code,
        "Movies": .media, "Music": .media, "Pictures": .media,
        "Documents": .document, "Mail": .document,
        "Applications": .application,
    ]
}
