import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected = Set<NodeID>()
    @State private var kindFilter: CleanupSuggestion.Kind?

    var body: some View {
        Group {
            if let tree = model.tree, model.phase != .scanning {
                content(tree: tree)
            } else if model.phase == .scanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning \(Format.displayPath(model.scanningPath ?? ""))… suggestions appear when the scan finishes.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Theme.hud)
                    Text("Scan a location to find reclaimable space")
                        .font(.title3.weight(.medium))
                    Text("Pelican looks for caches, build artifacts, logs, old installers and large files you haven't touched in months.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Scan Home Folder") {
                        model.startScan(path: NSHomeDirectory())
                    }
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Cleanup Suggestions")
        .onChange(of: model.version) { _ in selected.removeAll() }
    }

    @ViewBuilder
    private func content(tree: FileTree) -> some View {
        let all = model.suggestions()
        let visible = kindFilter.map { kind in all.filter { $0.kind == kind } } ?? all
        let selectedSize = all.filter { selected.contains($0.node) }.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.bytes(all.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.hud)
                    Text("potentially reclaimable in \(Format.displayPath(tree.rootPath))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(selected.isEmpty ? "Select All Safe" : "Deselect All") {
                    if selected.isEmpty {
                        selected = Set(visible.filter { $0.risk == .safe }.map(\.node))
                    } else {
                        selected.removeAll()
                    }
                }
                Button {
                    model.requestTrash(Array(selected))
                } label: {
                    Label("Move \(selected.count) to Trash (\(Format.bytes(selectedSize)))", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", symbol: "line.3.horizontal.decrease.circle", isOn: kindFilter == nil,
                               detail: Format.bytes(all.reduce(0) { $0 + $1.size })) { kindFilter = nil }
                    ForEach(CleanupSuggestion.Kind.allCases) { kind in
                        let items = all.filter { $0.kind == kind }
                        if !items.isEmpty {
                            FilterChip(title: kind.label, symbol: kind.symbol, isOn: kindFilter == kind,
                                       detail: Format.bytes(items.reduce(0) { $0 + $1.size })) { kindFilter = kind }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)

            Divider()

            if visible.isEmpty {
                Text("Nothing obvious to clean up here. Try scanning your home folder or the whole disk.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visible) { suggestion in
                    SuggestionRow(tree: tree, suggestion: suggestion,
                                  isSelected: Binding(
                                    get: { selected.contains(suggestion.node) },
                                    set: { isOn in
                                        if isOn { selected.insert(suggestion.node) } else { selected.remove(suggestion.node) }
                                    }))
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn ? Theme.hud.opacity(0.25) : Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(isOn ? Theme.hud : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct SuggestionRow: View {
    @EnvironmentObject private var model: AppModel
    let tree: FileTree
    let suggestion: CleanupSuggestion
    @Binding var isSelected: Bool

    var body: some View {
        let node = tree[suggestion.node]
        let path = tree.path(of: suggestion.node)
        HStack(spacing: 10) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(nsImage: IconCache.icon(for: node, path: path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name).fontWeight(.medium).lineLimit(1)
                    RiskBadge(risk: suggestion.risk)
                }
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.displayPath(path))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Format.bytes(suggestion.size))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Button {
                model.reveal(suggestion.node)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            Button {
                model.addToBasket([suggestion.node])
            } label: {
                Image(systemName: model.isInBasket(suggestion.node) ? "basket.fill" : "basket")
            }
            .buttonStyle(.borderless)
            .help("Add to Purge Basket")
        }
        .padding(.vertical, 3)
        .contextMenu { NodeContextMenu(id: suggestion.node) }
    }
}

private struct RiskBadge: View {
    let risk: CleanupSuggestion.Risk

    var body: some View {
        Text(risk == .safe ? "SAFE" : "REVIEW")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(risk == .safe ? FileCategory.document.color : Theme.warning)
            .overlay(Capsule().stroke(risk == .safe ? FileCategory.document.color : Theme.warning, lineWidth: 1))
            .help(risk == .safe ? "Regenerated automatically when needed" : "Check before deleting — may contain data you want to keep")
    }
}
