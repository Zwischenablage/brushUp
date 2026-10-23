import SwiftUI

/// Squarified cushion treemap with nested folders.
struct TreemapView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var interaction: InteractionState
    let tree: FileTree

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let tiles = model.treemapTiles(size: size)

            ZStack {
                TreemapBaseLayer(tree: tree, tiles: tiles, size: size, layoutVersion: model.version,
                                 focus: model.focus, metric: model.metric)
                    .equatable()
                TreemapHighlightLayer(tiles: tiles, hovered: interaction.hovered, selected: model.selection,
                                      basket: model.basket)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    interaction.pointer = location
                    let hit = TreemapLayout.hitTest(location, tiles: tiles).map { tiles[$0].node }
                    interaction.hover(hit, from: .canvas)
                case .ended:
                    interaction.hover(nil, from: .canvas)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard abs(value.translation.width) < 5, abs(value.translation.height) < 5 else { return }
                        guard let index = TreemapLayout.hitTest(value.location, tiles: tiles) else {
                            model.selection = nil
                            return
                        }
                        let tile = tiles[index]
                        if tile.isDirectory || tile.depth == 0 {
                            model.activate(tile.node)
                        } else {
                            // A file inside a nested folder: zoom into that folder.
                            model.zoom(to: tree[tile.node].parent)
                        }
                    }
            )
            .simultaneousGesture(MagnificationGesture().onEnded { model.handlePinch($0) })
            .contextMenu {
                NodeContextMenu(id: interaction.hovered ?? interaction.lastHovered)
            }
        }
        .padding(EdgeInsets(top: 84, leading: 24, bottom: 76, trailing: 24))
    }
}

private struct TreemapBaseLayer: View, Equatable {
    let tree: FileTree
    let tiles: [TreemapTile]
    let size: CGSize
    let layoutVersion: Int
    let focus: NodeID
    let metric: SizeMetric

    static func == (lhs: TreemapBaseLayer, rhs: TreemapBaseLayer) -> Bool {
        lhs.layoutVersion == rhs.layoutVersion && lhs.focus == rhs.focus && lhs.size == rhs.size
            && lhs.metric == rhs.metric && lhs.tiles.count == rhs.tiles.count
    }

    var body: some View {
        Canvas { context, _ in
            var bloom = context
            bloom.addFilter(.blur(radius: 8))
            bloom.opacity = 0.5
            bloom.drawLayer { layer in
                for tile in tiles where tile.depth == 0 {
                    layer.fill(Path(tile.rect), with: .color(tile.category.color.opacity(0.6)))
                }
            }

            for tile in tiles {
                let color = tile.category.color
                let rect = tile.rect.insetBy(dx: 0.5, dy: 0.5)
                guard rect.width > 0.5, rect.height > 0.5 else { continue }
                let path = Path(roundedRect: rect, cornerRadius: min(3, rect.width / 4, rect.height / 4))
                if tile.isNested {
                    context.fill(path, with: .color(color.opacity(0.10)))
                    context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: tile.depth == 0 ? 1.2 : 0.8)
                    if tile.hasHeader {
                        let header = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: TreemapLayout.headerHeight - 1)
                        context.fill(Path(header), with: .color(color.opacity(0.22)))
                        drawLabel(tile, in: context, rect: header.insetBy(dx: 5, dy: 0), compact: true)
                    }
                } else {
                    // Cushion shading: bright top-left fading to dark bottom-right.
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [color.opacity(0.95), color.opacity(0.55), color.opacity(0.25)]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                    context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.6)
                    if rect.width > 70 && rect.height > 30 {
                        drawLabel(tile, in: context, rect: rect.insetBy(dx: 6, dy: 4), compact: false)
                    }
                }
            }
        }
        .drawingGroup()
    }

    private func drawLabel(_ tile: TreemapTile, in context: GraphicsContext, rect: CGRect, compact: Bool) {
        let node = tree[tile.node]
        var text = Text(node.name).font(.system(size: compact ? 10 : 11, weight: .semibold)).foregroundColor(.white)
        if !compact || rect.width > 160 {
            text = text + Text(compact ? "  " : "\n").font(.system(size: 10))
                + Text(Format.bytes(node.size(metric))).font(Theme.mono(10)).foregroundColor(.white.opacity(0.75))
        }
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.draw(text, in: rect)
    }
}

private struct TreemapHighlightLayer: View {
    let tiles: [TreemapTile]
    let hovered: NodeID?
    let selected: NodeID?
    let basket: [NodeID]

    var body: some View {
        Canvas { context, _ in
            for tile in tiles where basket.contains(tile.node) {
                context.stroke(Path(tile.rect.insetBy(dx: 1, dy: 1)), with: .color(FileCategory.archive.color),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            for tile in tiles where tile.node == hovered || tile.node == selected {
                let path = Path(roundedRect: tile.rect, cornerRadius: 3)
                var glow = context
                glow.addFilter(.shadow(color: tile.category.color, radius: 8))
                glow.stroke(path, with: .color(.white), lineWidth: 2)
                if tile.node == hovered {
                    context.fill(path, with: .color(.white.opacity(0.12)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
