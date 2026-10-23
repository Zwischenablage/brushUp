import SwiftUI

private struct VizIdentity: Hashable {
    let focus: NodeID
    let mode: VizMode
}

struct VisualizationPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            HoloBackground()

            if let tree = model.tree {
                Group {
                    switch model.vizMode {
                    case .sunburst: SunburstView(tree: tree)
                    case .treemap: TreemapView(tree: tree)
                    }
                }
                .id(VizIdentity(focus: model.focus, mode: model.vizMode))
                .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                        removal: .scale(scale: 1.1).combined(with: .opacity)))

                HUDOverlay(tree: tree)
                    .allowsHitTesting(false)
                HoverPill(tree: tree)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        DepthControl()
                        Spacer()
                        PurgeBasketPill()
                    }
                }
                .padding(18)
            } else if model.phase != .scanning {
                EmptyStateView()
            }

            if model.phase == .scanning {
                ScanningOverlay()
            }
        }
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Context menu shared by canvas and table

struct NodeContextMenu: View {
    @EnvironmentObject private var model: AppModel
    let id: NodeID?

    var body: some View {
        if let id, let tree = model.tree, Int(id) < tree.count {
            let node = tree[id]
            let verdict = model.safety(of: id)
            Text("\(node.name) — \(Format.bytes(node.size(model.metric)))")
            if let message = verdict.message {
                Text(verdict.isBlocked ? "Protected: \(message)" : "⚠︎ \(message)")
            }
            Divider()
            if node.isDirectory && !node.isPackage {
                Button("Zoom In") { model.zoom(to: id) }
            } else {
                Button("Open") { model.open(item: id) }
            }
            Button("Quick Look") { model.quickLook(id) }
            Button("Reveal in Finder") { model.reveal(id) }
            Divider()
            Button(model.isInBasket(id) ? "Remove from Purge Basket" : "Add to Purge Basket") {
                model.toggleBasket(id)
            }
            .disabled(verdict.isBlocked)
            Divider()
            Button("Move to Trash") { model.requestTrash([id]) }
                .disabled(verdict.isBlocked)
            Button("Delete Permanently…") { model.requestPermanentDelete([id]) }
                .disabled(verdict.isBlocked)
        } else {
            Button("Enclosing Folder") { model.zoomOut() }
                .disabled(model.focus == FileTree.root)
        }
    }
}

// MARK: - HUD

struct HUDOverlay: View {
    @EnvironmentObject private var model: AppModel
    let tree: FileTree

    var body: some View {
        let focusNode = tree[model.focus]
        let rootSize = max(1, tree[FileTree.root].size(model.metric))
        let volume = model.rootVolume
        ZStack {
            HUDFrame()
                .stroke(Theme.hudDim, lineWidth: 1)
                .padding(12)

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(focusNode.name.uppercased())
                            .font(Theme.mono(17, weight: .medium))
                            .foregroundStyle(Theme.hud)
                            .lineLimit(1)
                        stat("ITEMS", Format.count(focusNode.itemCount))
                        stat("DEPTH", "\(tree.depth(of: model.focus)) / \(model.ringCount) RINGS")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Format.duration(model.scanDuration))
                            .font(Theme.mono(17, weight: .medium))
                            .foregroundStyle(Theme.hud)
                        stat("SCANNED", Format.count(model.progress.items))
                        stat("MODE", model.metric == .physical ? "ON DISK" : "LOGICAL")
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        stat("OF SCAN", Format.percent(Double(focusNode.size(model.metric)) / Double(rootSize)))
                        Text(Format.bytes(focusNode.size(model.metric)))
                            .font(Theme.mono(20, weight: .medium))
                            .foregroundStyle(Theme.hud)
                    }
                    .padding(.leading, 150) // leave room for the depth control
                    Spacer()
                    if let volume {
                        VStack(alignment: .trailing, spacing: 3) {
                            stat(volume.name.uppercased(), "\(Format.bytes(volume.used)) USED")
                            Text("\(Format.bytes(volume.available)) FREE")
                                .font(Theme.mono(20, weight: .medium))
                                .foregroundStyle(Theme.hud)
                        }
                        .padding(.trailing, 230) // leave room for the purge basket
                    }
                }
            }
            .padding(26)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.hudDim)
            Text(value).foregroundStyle(Theme.hud.opacity(0.85))
        }
        .font(Theme.mono(10.5))
        .lineLimit(1)
    }
}

struct HoverPill: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var interaction: InteractionState
    let tree: FileTree

    var body: some View {
        GeometryReader { geometry in
            if let id = interaction.hovered, interaction.source == .canvas, Int(id) < tree.count {
                let node = tree[id]
                let parentSize = node.parent >= 0 ? tree[node.parent].size(model.metric) : node.size(model.metric)
                let fraction = parentSize > 0 ? Double(node.size(model.metric)) / Double(parentSize) : 0
                HStack(spacing: 8) {
                    Circle()
                        .fill(node.category.color)
                        .frame(width: 9, height: 9)
                        .shadow(color: node.category.color, radius: 4)
                    Text(node.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("·").foregroundStyle(.secondary)
                    Text(Format.bytes(node.size(model.metric)))
                        .monospacedDigit()
                    Text("·").foregroundStyle(.secondary)
                    Text("\(Format.percent(fraction)) of parent")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if model.safety(of: id).isBlocked {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(Theme.hud.opacity(0.6), lineWidth: 1))
                .shadow(color: Theme.hud.opacity(0.35), radius: 10)
                .fixedSize()
                .position(pillPosition(in: geometry.size))
            }
        }
    }

    private func pillPosition(in size: CGSize) -> CGPoint {
        let point = interaction.pointer
        let x = min(max(point.x + 150, 170), size.width - 170)
        let y = min(max(point.y - 34, 30), size.height - 30)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Controls & states

private struct DepthControl: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .foregroundStyle(Theme.hud)
            Slider(value: $model.depth, in: 2...10, step: 1)
                .frame(width: 90)
                .tint(Theme.hud)
            Text("\(model.ringCount)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.hud)
                .frame(width: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().stroke(Theme.hudDim, lineWidth: 0.5))
        .help("Visible depth (rings / nesting levels)")
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Theme.hud)
                .shadow(color: Theme.hud, radius: 12)
            Text("Choose a location to map")
                .font(.title2.weight(.medium))
            Text("Pick a volume or folder in the sidebar, or scan one of these:")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let boot = model.volumes.first {
                    Button {
                        model.sidebarSelection = .location(boot.path)
                    } label: {
                        Label("Scan \(boot.name)", systemImage: "internaldrive")
                    }
                }
                Button {
                    model.sidebarSelection = .location(NSHomeDirectory())
                } label: {
                    Label("Scan Home Folder", systemImage: "house")
                }
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Other…", systemImage: "folder")
                }
            }
            .controlSize(.large)
        }
        .foregroundStyle(.white)
    }
}

private struct ScanningOverlay: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(model.tree == nil ? 0 : 0.55)
            VStack(spacing: 22) {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for ring in 0..<4 {
                            let radius = CGFloat(30 + ring * 22)
                            let start = t * (1.2 - Double(ring) * 0.22) * (ring.isMultiple(of: 2) ? 1 : -1)
                            var arc = Path()
                            arc.addArc(center: center, radius: radius, startAngle: .radians(start),
                                       endAngle: .radians(start + 1.6 + Double(ring) * 0.5), clockwise: false)
                            context.stroke(arc, with: .color(Theme.hud.opacity(0.9 - Double(ring) * 0.18)),
                                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                                  width: radius * 2, height: radius * 2)),
                                           with: .color(Theme.hud.opacity(0.08)), lineWidth: 1)
                        }
                    }
                    .frame(width: 220, height: 220)
                    .shadow(color: Theme.hud.opacity(0.7), radius: 8)
                }
                VStack(spacing: 6) {
                    Text("Scanning \(Format.displayPath(model.scanningPath ?? ""))")
                        .font(.title3.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(Format.count(model.progress.items)) items  ·  \(Format.count(model.progress.directories)) folders  ·  \(Format.bytes(model.progress.bytes))")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.hud)
                    Text(Format.duration(model.scanDuration))
                        .font(Theme.mono(12))
                        .foregroundStyle(.secondary)
                }
                Button("Stop Scan") { model.cancelScan() }
                    .keyboardShortcut(.cancelAction)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
        }
    }
}
