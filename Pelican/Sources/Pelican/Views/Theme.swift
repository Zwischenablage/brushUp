import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let canvasTop = Color(red: 0.03, green: 0.07, blue: 0.11)
    static let canvasBottom = Color(red: 0.05, green: 0.12, blue: 0.17)
    static let hud = Color(red: 0.30, green: 0.90, blue: 1.00)
    static let hudDim = Color(red: 0.30, green: 0.90, blue: 1.00).opacity(0.45)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.20)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension FileCategory {
    /// Neon palette following the PRD semantics (indigo = code, amber = media,
    /// rose = archives, slate/steel = system, teal = documents).
    var color: Color {
        switch self {
        case .folder: return Color(red: 0.35, green: 0.75, blue: 1.00)
        case .code: return Color(red: 0.49, green: 0.43, blue: 1.00)
        case .media: return Color(red: 1.00, green: 0.66, blue: 0.16)
        case .archive: return Color(red: 1.00, green: 0.32, blue: 0.48)
        case .system: return Color(red: 0.48, green: 0.66, blue: 0.86)
        case .document: return Color(red: 0.16, green: 0.90, blue: 0.76)
        case .application: return Color(red: 0.93, green: 0.40, blue: 0.95)
        case .other: return Color(red: 0.45, green: 0.92, blue: 0.45)
        }
    }
}

/// Human-readable "Kind" column (Uniform Type Identifier descriptions), cached per extension.
enum Kinds {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func describe(_ node: FileNode) -> String {
        if node.isDirectory && !node.isPackage { return "Folder" }
        if node.flags.contains(.symlink) { return "Alias" }
        guard let ext = FileCategory.fileExtension(of: node.name) else {
            return node.isPackage ? "Package" : "Document"
        }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[ext] { return cached }
        let description = UTType(filenameExtension: ext)?.localizedDescription
            ?? (node.isPackage ? "Package" : ext.uppercased() + " File")
        cache[ext] = description
        return description
    }
}

/// Finder icons, cached by extension (or by path for app bundles, whose icons differ).
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for node: FileNode, path: @autoclosure () -> String) -> NSImage {
        let key: String
        if node.isPackage, FileCategory.fileExtension(of: node.name) == "app" {
            key = path()
        } else if node.isDirectory && !node.isPackage {
            key = "/folder"
        } else {
            key = "." + (FileCategory.fileExtension(of: node.name) ?? "")
        }
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let image: NSImage
        if key.hasPrefix("/") && key != "/folder" {
            image = NSWorkspace.shared.icon(forFile: key)
        } else if key == "/folder" {
            image = NSWorkspace.shared.icon(for: .folder)
        } else {
            let ext = String(key.dropFirst())
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

/// Dark grid backdrop behind the visualisation.
struct HoloBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.canvasTop, Theme.canvasBottom], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                let spacing: CGFloat = 28
                var grid = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(grid, with: .color(Theme.hud.opacity(0.05)), lineWidth: 0.5)
            }
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 200, endRadius: 900)
        }
        .allowsHitTesting(false)
    }
}

/// Corner bracket frame used by the HUD.
struct HUDFrame: Shape {
    var arm: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect
        path.move(to: CGPoint(x: r.minX, y: r.minY + arm)); path.addLine(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX + arm, y: r.minY))
        path.move(to: CGPoint(x: r.maxX - arm, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY + arm))
        path.move(to: CGPoint(x: r.maxX, y: r.maxY - arm)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
        path.move(to: CGPoint(x: r.minX + arm, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY - arm))
        return path
    }
}
