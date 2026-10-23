import SwiftUI
import UniformTypeIdentifiers

private enum Column {
    static let size: CGFloat = 200
    static let items: CGFloat = 80
    static let modified: CGFloat = 150
    static let kind: CGFloat = 140
    static let action: CGFloat = 30
}

/// Children of the focused folder, synchronised with the canvas hover and selection.
struct DetailTableView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var interaction: InteractionState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let tree = model.tree {
                let rows = model.tableRows()
                let parentSize = max(1, tree[model.focus].size(model.metric))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element) { index, id in
                                DetailRow(tree: tree, id: id, parentSize: parentSize, striped: index % 2 == 1,
                                          isHovered: interaction.hovered == id,
                                          isSelected: model.selection == id)
                                    .id(id)
                            }
                        }
                    }
                    .onChange(of: interaction.hovered) { hovered in
                        // Follow the canvas: keep the hovered item's row in view.
                        guard interaction.source == .canvas, let hovered, rows.contains(hovered) else { return }
                        proxy.scrollTo(hovered)
                    }
                }
                if rows.isEmpty {
                    Text(tree[model.focus].flags.contains(.unreadable)
                         ? "This folder could not be read. Grant Full Disk Access to include it."
                         : "This folder is empty.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Spacer()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerCell("Name", .name).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 34)
            headerCell("Size", .size).frame(width: Column.size, alignment: .leading)
            headerCell("Items", .items).frame(width: Column.items, alignment: .trailing)
            headerCell("Last Modified", .modified).frame(width: Column.modified, alignment: .leading).padding(.leading, 16)
            headerCell("Kind", .kind).frame(width: Column.kind, alignment: .leading)
            Color.clear.frame(width: Column.action)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 8)
        .frame(height: 28)
    }

    private func headerCell(_ title: String, _ key: SortKey) -> some View {
        Button {
            model.setSort(key)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if model.sortKey == key {
                    Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.sortKey == key ? Color.primary : Color.secondary)
    }
}

private struct DetailRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var interaction: InteractionState
    let tree: FileTree
    let id: NodeID
    let parentSize: Int64
    let striped: Bool
    let isHovered: Bool
    let isSelected: Bool

    var body: some View {
        let node = tree[id]
        let path = tree.path(of: id)
        let verdict = Safety.verdict(for: path)
        let size = node.size(model.metric)
        let fraction = Double(size) / Double(parentSize)

        HStack(spacing: 0) {
            // Name
            HStack(spacing: 6) {
                Button {
                    model.zoom(to: id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .opacity(node.isDirectory ? 1 : 0)
                .disabled(!node.isDirectory)

                Image(nsImage: IconCache.icon(for: node, path: path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if node.isPackage {
                    Text(FileCategory.fileExtension(of: node.name)?.uppercased() ?? "PKG")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().stroke(Color.secondary.opacity(0.6)))
                        .foregroundStyle(.secondary)
                }
                switch verdict {
                case .blocked(let reason):
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).help(reason)
                case .caution(let reason):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).help(reason)
                case .allowed:
                    EmptyView()
                }
                if node.flags.contains(.unreadable) {
                    Image(systemName: "eye.slash").foregroundStyle(Theme.warning)
                        .help("Could not be read completely — grant Full Disk Access for accurate sizes")
                }
                if model.isInBasket(id) {
                    Image(systemName: "basket.fill").foregroundStyle(FileCategory.archive.color)
                        .help("In the Purge Basket")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size + bar
            HStack(spacing: 8) {
                Text(Format.bytes(size))
                    .monospacedDigit()
                    .frame(width: 74, alignment: .trailing)
                SizeBar(fraction: fraction, color: node.category.color)
                    .frame(height: 5)
            }
            .frame(width: Column.size)

            Text(node.isDirectory ? Format.count(node.itemCount) : "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: Column.items, alignment: .trailing)

            Text(Format.date(node.modified))
                .monospacedDigit()
                .foregroundStyle(Format.isStale(node.modified) ? Theme.warning : Color.secondary)
                .help(Format.isStale(node.modified)
                      ? "Not modified \(Format.relative(Date(timeIntervalSince1970: node.modified)))" : "")
                .frame(width: Column.modified, alignment: .leading)
                .padding(.leading, 16)

            Text(Kinds.describe(node))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: Column.kind, alignment: .leading)

            Button {
                model.requestTrash([id])
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move to Trash (⌘⌫)")
            .opacity(isHovered && !verdict.isBlocked ? 1 : 0)
            .disabled(verdict.isBlocked)
            .frame(width: Column.action)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(background)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                interaction.hover(id, from: .table)
            } else if interaction.hovered == id {
                interaction.hover(nil, from: .table)
            }
        }
        .onTapGesture(count: 2) { model.open(item: id) }
        .simultaneousGesture(TapGesture().onEnded { model.selection = id })
        .onDrag {
            NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
        }
        .contextMenu { NodeContextMenu(id: id) }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.35) }
        if isHovered { return Theme.hud.opacity(0.12) }
        return striped ? Color.primary.opacity(0.035) : Color.clear
    }
}

private struct SizeBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
                    .shadow(color: color.opacity(0.6), radius: 3)
            }
        }
    }
}

// MARK: - Purge basket

struct PurgeBasketPill: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDetails = false
    @State private var isTargeted = false

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.basket.isEmpty ? "basket" : "basket.fill")
                if model.basket.isEmpty {
                    Text(isTargeted ? "Drop to stage" : "Purge Basket")
                } else {
                    Text("\(model.basket.count) item\(model.basket.count == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(Format.bytes(model.basketSize)) to free")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(isTargeted ? 0.7 : 0.45)))
            .overlay(Capsule().stroke(model.basket.isEmpty && !isTargeted ? Theme.hudDim : FileCategory.archive.color,
                                      lineWidth: isTargeted ? 2 : 1))
            .shadow(color: model.basket.isEmpty ? .clear : FileCategory.archive.color.opacity(0.5), radius: 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help("Stage folders here (right-click → Add to Purge Basket, ⌘B, or drag rows from the table)")
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSURL.self) { reading, _ in
                    guard let url = reading as? NSURL, let path = url.path else { return }
                    DispatchQueue.main.async { model.addToBasket(path: path) }
                }
            }
            return true
        }
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            BasketPopover(close: { showDetails = false })
                .environmentObject(model)
        }
    }
}

private struct BasketPopover: View {
    @EnvironmentObject private var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Purge Basket").font(.headline)
                Spacer()
                Text("Space to be freed: \(Format.bytes(model.basketSize))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if model.basket.isEmpty {
                Text("Nothing staged yet. Right-click any segment or row and choose “Add to Purge Basket”, press ⌘B while hovering, or drag rows from the table onto the basket.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let tree = model.tree {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.basket, id: \.self) { id in
                            HStack(spacing: 8) {
                                Image(nsImage: IconCache.icon(for: tree[id], path: tree.path(of: id)))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(tree[id].name).lineLimit(1)
                                    Text(Format.displayPath(tree.path(of: id)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(Format.bytes(tree[id].size(.physical)))
                                    .monospacedDigit()
                                Button {
                                    model.toggleBasket(id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
            HStack {
                Button("Clear") { model.clearBasket() }
                    .disabled(model.basket.isEmpty)
                Spacer()
                Button("Move All to Trash") {
                    close()
                    model.trashBasket()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.basket.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 420)
    }
}
