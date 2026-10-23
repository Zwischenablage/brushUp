import AppKit
import SwiftUI

struct AppsView: View {
    @ObservedObject var inventory: AppInventory
    @State private var search = ""
    @State private var sortBySize = true
    @State private var uninstallTarget: InstalledApp?

    private var visibleApps: [InstalledApp] {
        let filtered = search.isEmpty ? inventory.apps
            : inventory.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        if sortBySize {
            return filtered.sorted { $0.totalSize > $1.totalSize }
        }
        return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.bytes(inventory.apps.reduce(0) { $0 + $1.totalSize }))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.hud)
                    Text(inventory.isLoading
                         ? "Measuring \(inventory.sizedCount) of \(inventory.apps.count) apps…"
                         : "used by \(inventory.apps.count) apps and their support files")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sort", selection: $sortBySize) {
                    Text("Largest First").tag(true)
                    Text("Least Recently Used").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Button {
                    inventory.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(inventory.isLoading)
            }
            .padding(16)
            Divider()

            List(visibleApps) { app in
                AppRow(app: app) { uninstallTarget = app }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .navigationTitle("Uninstall Apps")
        .searchable(text: $search, placement: .toolbar, prompt: "Search apps")
        .onAppear { inventory.reloadIfNeeded() }
        .sheet(item: $uninstallTarget) { app in
            UninstallSheet(app: app, inventory: inventory)
        }
        .alert("Uninstall Problem", isPresented: Binding(
            get: { inventory.lastError != nil },
            set: { if !$0 { inventory.lastError = nil } })) {
            Button("OK", role: .cancel) { inventory.lastError = nil }
        } message: {
            Text(inventory.lastError ?? "")
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).fontWeight(.medium)
                    if let version = app.version {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    }
                    if app.isProtected {
                        Image(systemName: "applelogo").font(.caption).foregroundStyle(.secondary)
                            .help("Apple app — protected by macOS")
                    }
                }
                Text(lastUsedText)
                    .font(.caption)
                    .foregroundStyle(isStale ? Theme.warning : Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let size = app.size {
                    Text(Format.bytes(size)).monospacedDigit().fontWeight(.semibold)
                } else {
                    ProgressView().controlSize(.small)
                }
                if app.leftoverSize > 0 {
                    Text("+ \(Format.bytes(app.leftoverSize)) support files")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button("Uninstall…", action: onUninstall)
                .disabled(app.isProtected || app.size == nil)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
            }
        }
    }

    private var isStale: Bool {
        guard let lastUsed = app.lastUsed else { return true }
        return Date().timeIntervalSince(lastUsed) > 180 * 24 * 3600
    }

    private var lastUsedText: String {
        guard let lastUsed = app.lastUsed else { return "Never opened (according to Spotlight)" }
        return "Last opened \(Format.relative(lastUsed))"
    }
}

private struct UninstallSheet: View {
    let app: InstalledApp
    @ObservedObject var inventory: AppInventory
    @Environment(\.dismiss) private var dismiss
    @State private var included: Set<String>

    init(app: InstalledApp, inventory: AppInventory) {
        self.app = app
        self.inventory = inventory
        _included = State(initialValue: Set(app.leftovers.map(\.path)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                    Text("Uninstall \(app.name)?").font(.title3.weight(.semibold))
                    Text("Everything checked below is moved to the Trash.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary)
                    Text("Application bundle")
                    Spacer()
                    Text(Format.bytes(app.size ?? 0)).monospacedDigit()
                }
                ForEach(app.leftovers) { leftover in
                    Toggle(isOn: Binding(
                        get: { included.contains(leftover.path) },
                        set: { isOn in
                            if isOn { included.insert(leftover.path) } else { included.remove(leftover.path) }
                        })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(leftover.label)
                                Text(Format.displayPath(leftover.path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(Format.bytes(leftover.size)).monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                if app.leftovers.isEmpty {
                    Text("No support files found in ~/Library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    inventory.uninstall(app, leftovers: app.leftovers.filter { included.contains($0.path) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
