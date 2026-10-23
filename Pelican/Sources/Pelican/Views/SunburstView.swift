import SwiftUI

/// Radial sunburst. The expensive base layer is an `Equatable` view keyed by the layout,
/// so pointer movement only redraws the lightweight highlight layer on top.
struct SunburstView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var interaction: InteractionState
    let tree: FileTree

    var body: some View {
        GeometryReader { proxy in
            let geometry = SunburstGeometry(size: proxy.size, rings: model.ringCount)
            let segments = model.sunburstSegments()
            let focusNode = tree[model.focus]

            ZStack {
                SunburstBaseLayer(segments: segments, geometry: geometry, size: proxy.size,
                                  layoutVersion: model.version, focus: model.focus,
                                  title: focusNode.name, subtitle: Format.bytes(focusNode.size(model.metric)))
                    .equatable()

                SunburstHighlightLayer(segments: segments, geometry: geometry,
                                       hovered: interaction.hovered, selected: model.selection,
                                       basket: model.basket)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    interaction.pointer = location
                    switch geometry.hitTest(location, segments: segments) {
                    case .segment(let index)?:
                        interaction.hover(segments[index].node, from: .canvas)
                    case .center?, nil:
                        interaction.hover(nil, from: .canvas)
                    }
                case .ended:
                    interaction.hover(nil, from: .canvas)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard abs(value.translation.width) < 5, abs(value.translation.height) < 5 else { return }
                        switch geometry.hitTest(value.location, segments: segments) {
                        case .segment(let index)?:
                            model.activate(segments[index].node)
                        case .center?:
                            model.zoomOut()
                        case nil:
                            model.selection = nil
                        }
                    }
            )
            .simultaneousGesture(MagnificationGesture().onEnded { model.handlePinch($0) })
            .contextMenu {
                NodeContextMenu(id: interaction.hovered ?? interaction.lastHovered)
            }
        }
        .padding(8)
    }
}

private struct SunburstBaseLayer: View, Equatable {
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry
    let size: CGSize
    let layoutVersion: Int
    let focus: NodeID
    let title: String
    let subtitle: String

    static func == (lhs: SunburstBaseLayer, rhs: SunburstBaseLayer) -> Bool {
        lhs.layoutVersion == rhs.layoutVersion && lhs.focus == rhs.focus && lhs.size == rhs.size
            && lhs.segments.count == rhs.segments.count && lhs.geometry.rings == rhs.geometry.rings
            && lhs.subtitle == rhs.subtitle
    }

    var body: some View {
        Canvas { context, _ in
            drawDecorations(in: context)

            // Bloom pass: a blurred copy underneath gives the neon glow.
            var bloom = context
            bloom.addFilter(.blur(radius: 9))
            bloom.opacity = 0.75
            bloom.drawLayer { layer in drawSegments(in: layer, bright: true) }

            context.drawLayer { layer in drawSegments(in: layer, bright: false) }

            drawCenter(in: context)
        }
        .drawingGroup() // Metal-backed offscreen rendering
    }

    private func drawSegments(in context: GraphicsContext, bright: Bool) {
        for segment in segments {
            let radii = geometry.radii(forDepth: segment.depth)
            let span = segment.end - segment.start
            let padding = span > 0.02 ? 0.003 : 0
            let path = SunburstShape.path(center: geometry.center, inner: radii.inner + 1, outer: radii.outer - 1,
                                          start: segment.start + padding, end: segment.end - padding)
            let color = segment.category.color
            let intensity = max(0.35, 1 - Double(segment.depth) * 0.09)
            if bright {
                context.fill(path, with: .color(color.opacity(intensity * 0.8)))
            } else {
                let inner = CGPoint(x: geometry.center.x, y: geometry.center.y)
                context.fill(path, with: .radialGradient(
                    Gradient(colors: [color.opacity(intensity * 0.25), color.opacity(intensity * 0.6)]),
                    center: inner, startRadius: radii.inner, endRadius: radii.outer))
                context.stroke(path, with: .color(color.opacity(min(1, intensity + 0.1))),
                               lineWidth: segment.isDirectory ? 1.2 : 0.8)
            }
        }
    }

    private func drawDecorations(in context: GraphicsContext) {
        let center = geometry.center
        // Ring guides.
        for ring in 0...geometry.rings {
            let radius = geometry.innerRadius + CGFloat(ring) * geometry.ringWidth
            context.stroke(circle(center, radius), with: .color(Theme.hud.opacity(0.06)), lineWidth: 0.5)
        }
        // Outer tick ring.
        let tickInner = geometry.outerRadius + 10
        var ticks = Path()
        var majorTicks = Path()
        for index in 0..<180 {
            let angle = Double(index) / 180 * 2 * .pi - .pi / 2
            let major = index % 15 == 0
            let length: CGFloat = major ? 9 : 4
            let start = CGPoint(x: center.x + CGFloat(cos(angle)) * tickInner, y: center.y + CGFloat(sin(angle)) * tickInner)
            let end = CGPoint(x: center.x + CGFloat(cos(angle)) * (tickInner + length),
                              y: center.y + CGFloat(sin(angle)) * (tickInner + length))
            if major {
                majorTicks.move(to: start)
                majorTicks.addLine(to: end)
            } else {
                ticks.move(to: start)
                ticks.addLine(to: end)
            }
        }
        context.stroke(ticks, with: .color(Theme.hud.opacity(0.3)), lineWidth: 0.7)
        context.stroke(majorTicks, with: .color(Theme.hud.opacity(0.7)), lineWidth: 1.2)

        // Partial HUD arcs.
        let arcRadius = geometry.outerRadius + 26
        for (start, length) in [(0.15, 0.9), (1.9, 0.5), (3.3, 1.1), (5.0, 0.6)] {
            var arc = Path()
            arc.addArc(center: center, radius: arcRadius, startAngle: .radians(start),
                       endAngle: .radians(start + length), clockwise: false)
            context.stroke(arc, with: .color(Theme.hud.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func drawCenter(in context: GraphicsContext) {
        let center = geometry.center
        let radius = geometry.innerRadius - 4
        context.fill(circle(center, radius), with: .radialGradient(
            Gradient(colors: [Theme.hud.opacity(0.18), Theme.canvasTop.opacity(0.9)]),
            center: center, startRadius: 0, endRadius: radius))
        context.stroke(circle(center, radius), with: .color(Theme.hud.opacity(0.6)), lineWidth: 1)
        context.stroke(circle(center, radius * 0.82), with: .color(Theme.hud.opacity(0.2)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

        let maxWidth = radius * 1.6
        let titleText = context.resolve(Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.white))
        let subtitleText = context.resolve(Text(subtitle).font(Theme.mono(11)).foregroundColor(Theme.hud))
        if titleText.measure(in: CGSize(width: maxWidth, height: 40)).width <= maxWidth {
            context.draw(titleText, at: CGPoint(x: center.x, y: center.y - 8))
        } else {
            let short = String(title.prefix(12)) + "…"
            context.draw(Text(short).font(.system(size: 13, weight: .semibold)).foregroundColor(.white),
                         at: CGPoint(x: center.x, y: center.y - 8))
        }
        context.draw(subtitleText, at: CGPoint(x: center.x, y: center.y + 10))
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

private struct SunburstHighlightLayer: View {
    let segments: [SunburstSegment]
    let geometry: SunburstGeometry
    let hovered: NodeID?
    let selected: NodeID?
    let basket: [NodeID]

    var body: some View {
        Canvas { context, _ in
            for segment in segments where basket.contains(segment.node) {
                let radii = geometry.radii(forDepth: segment.depth)
                let path = SunburstShape.path(center: geometry.center, inner: radii.inner + 1, outer: radii.outer - 1,
                                              start: segment.start, end: segment.end)
                context.stroke(path, with: .color(FileCategory.archive.color),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            for segment in segments where segment.node == hovered || segment.node == selected {
                let radii = geometry.radii(forDepth: segment.depth)
                let path = SunburstShape.path(center: geometry.center, inner: radii.inner, outer: radii.outer,
                                              start: segment.start, end: segment.end)
                let color = segment.category.color
                var glow = context
                glow.addFilter(.shadow(color: color, radius: 10))
                glow.fill(path, with: .color(color.opacity(segment.node == hovered ? 0.85 : 0.6)))
                context.stroke(path, with: .color(.white.opacity(0.9)),
                               style: StrokeStyle(lineWidth: segment.node == selected ? 2 : 1.2,
                                                  dash: segment.node == selected ? [5, 3] : []))
            }
        }
        .allowsHitTesting(false)
    }
}

enum SunburstShape {
    /// Annular sector; angles are 0 at 12 o'clock and increase clockwise on screen.
    static func path(center: CGPoint, inner: CGFloat, outer: CGFloat, start: Double, end: Double) -> Path {
        var path = Path()
        guard end > start, outer > inner else { return path }
        let startAngle = Angle(radians: start - .pi / 2)
        let endAngle = Angle(radians: end - .pi / 2)
        path.addArc(center: center, radius: outer, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: max(0, inner), startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}
