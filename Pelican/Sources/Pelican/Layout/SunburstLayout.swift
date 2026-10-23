import CoreGraphics
import Foundation

struct SunburstSegment {
    let node: NodeID
    /// 0 = first ring around the centre.
    let depth: Int
    /// Angles in radians, 0 at 12 o'clock, increasing clockwise.
    let start: Double
    let end: Double
    let category: FileCategory
    let isDirectory: Bool
}

enum SunburstLayout {
    /// Segments narrower than this are not drawn (they remain as a gap so the
    /// proportions stay honest).
    static let minimumAngle = 0.0035

    static func layout(tree: FileTree, root: NodeID, metric: SizeMetric, maxDepth: Int) -> [SunburstSegment] {
        var segments: [SunburstSegment] = []
        segments.reserveCapacity(4096)

        func visit(_ id: NodeID, depth: Int, start: Double, end: Double) {
            let total = Double(tree[id].size(metric))
            guard total > 0 else { return }
            let span = end - start
            var angle = start
            for child in tree.visibleChildren(of: id, sortedBy: metric) {
                let node = tree[child]
                let childSpan = span * Double(node.size(metric)) / total
                // Children are sorted by size, so everything after this is smaller still.
                if childSpan < minimumAngle { break }
                segments.append(SunburstSegment(node: child, depth: depth, start: angle, end: angle + childSpan,
                                                category: node.category, isDirectory: node.isDirectory))
                if node.isDirectory && depth + 1 < maxDepth {
                    visit(child, depth: depth + 1, start: angle, end: angle + childSpan)
                }
                angle += childSpan
            }
        }

        visit(root, depth: 0, start: 0, end: 2 * .pi)
        return segments
    }
}

/// Maps rings to radii for a given canvas size and does polar hit-testing.
struct SunburstGeometry {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let rings: Int

    init(size: CGSize, rings: Int) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(10, min(size.width, size.height) / 2)
        outerRadius = radius * 0.84
        innerRadius = radius * 0.2
        self.rings = max(1, rings)
    }

    var ringWidth: CGFloat { (outerRadius - innerRadius) / CGFloat(rings) }

    func radii(forDepth depth: Int) -> (inner: CGFloat, outer: CGFloat) {
        let inner = innerRadius + CGFloat(depth) * ringWidth
        return (inner, inner + ringWidth)
    }

    enum Hit: Equatable {
        case center
        case segment(Int)
    }

    func hitTest(_ point: CGPoint, segments: [SunburstSegment]) -> Hit? {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let distance = CGFloat((dx * dx + dy * dy).squareRoot())
        if distance < innerRadius { return .center }
        let depth = Int((distance - innerRadius) / ringWidth)
        guard depth >= 0, depth < rings else { return nil }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        if angle >= 2 * .pi { angle -= 2 * .pi }
        for (index, segment) in segments.enumerated()
        where segment.depth == depth && angle >= segment.start && angle < segment.end {
            return .segment(index)
        }
        return nil
    }
}
