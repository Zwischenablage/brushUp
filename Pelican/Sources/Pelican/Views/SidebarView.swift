import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section("Locations") {
                ForEach(model.volumes) { volume in
                    SidebarRow(title: volume.name, symbol: volume.symbol,
                               detail: "\(Format.bytes(volume.available)) free",
                               gauge: volume.usedFraction)
                        .tag(SidebarItem.location(volume.path))
                }
            }

            shortcutSection("Favorites", Shortcuts.favorites)
            shortcutSection("Library & Caches", Shortcuts.library)
            if !Shortcuts.developer.isEmpty {
                shortcutSection("Developer", Shortcuts.developer)
            }

            Section("Reclaim Space") {
                SidebarRow(title: "Cleanup Suggestions", symbol: "wand.and.stars",
                           detail: model.tree == nil ? nil : Format.bytes(model.suggestions().reduce(0) { $0 + $1.size }))
                    .tag(SidebarItem.cleanup)
                SidebarRow(title: "Uninstall Apps", symbol: "xmark.app", detail: nil)
                    .tag(SidebarItem.apps)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            BrandHeader()
        }
        .safeAreaInset(edge: .bottom) {
            SidebarStatusCard()
                .padding(10)
        }
    }

    private func shortcutSection(_ title: String, _ shortcuts: [Shortcut]) -> some View {
        Section(title) {
            ForEach(shortcuts) { shortcut in
                SidebarRow(title: shortcut.title, symbol: shortcut.symbol,
                           detail: model.shortcutSizes[shortcut.path].map(Format.bytes))
                    .tag(SidebarItem.location(shortcut.path))
            }
        }
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bird")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.hud, FileCategory.application.color],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text("Pelican")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Disk Visualizer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let detail: String?
    var gauge: Double? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.hud)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .lineLimit(1)
                if let gauge {
                    CapacityBar(fraction: gauge)
                        .frame(height: 3)
                }
            }
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CapacityBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.hud, fraction > 0.9 ? Theme.warning : FileCategory.code.color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
    }
}

private struct SidebarStatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.phase == .scanning {
                HStack {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Scanning \(Format.displayPath(model.scanningPath ?? ""))")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(Format.count(model.progress.items)) items · \(Format.bytes(model.progress.bytes))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop") { model.cancelScan() }
                        .controlSize(.small)
                }
            } else if let volume = model.rootVolume {
                Text(volume.name)
                    .font(.caption.weight(.medium))
                CapacityBar(fraction: volume.usedFraction)
                    .frame(height: 5)
                Text("\(Format.bytes(volume.used)) used of \(Format.bytes(volume.total))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if !model.hasFullDiskAccess {
                Button {
                    FullDiskAccess.openSystemSettings()
                } label: {
                    Label("Grant Full Disk Access", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .foregroundStyle(Theme.warning)
                .help("Without Full Disk Access some folders (Mail, Safari, other apps' containers) cannot be measured")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }
}
