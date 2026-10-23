import CoreGraphics
import Foundation

struct TreemapTile {
    let node: NodeID
    let rect: CGRect
    /// 0 = immediate child of the focused folder.
    let depth: Int
    let category: FileCategory
    let isDirectory: Bool
    /// True when the tile's own children are drawn inside it.
    let isNested: Bool
    /// True when there is room for a title strip at the top of a nested tile.
    let hasHeader: Bool
}

enum TreemapLayout {
    static let headerHeight: CGFloat = 16
    static let minimumArea: Double = 6

    static func layout(tree: FileTree, root: NodeID, metric: SizeMetric, bounds: CGRect,
                       maxDepth: Int) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        tiles.reserveCapacity(2048)

        func visit(_ id: NodeID, rect: CGRect, depth: Int) {
            let total = Double(tree[id].size(metric))
            guard total > 0, rect.width > 1, rect.height > 1 else { return }
            let area = Double(rect.width * rect.height)
            var ids: [NodeID] = []
            var values: [Double] = []
            for child in tree.visibleChildren(of: id, sortedBy: metric) {
                let value = Double(tree[child].size(metric)) / total * area
                if value < minimumArea { break }
                ids.append(child)
                values.append(value)
            }
            let rects = squarify(values: values, in: rect)
            for (child, childRect) in zip(ids, rects) {
                let node = tree[child]
                let nested = node.isDirectory && depth + 1 < maxDepth && childRect.width > 28 && childRect.height > 28
                let header = nested && childRect.width > 70 && childRect.height > 54
                tiles.append(TreemapTile(node: child, rect: childRect, depth: depth, category: node.category,
                                         isDirectory: node.isDirectory, isNested: nested, hasHeader: header))
                if nested {
                    let inner: CGRect
                    if header {
                        inner = CGRect(x: childRect.minX + 2, y: childRect.minY + headerHeight,
                                       width: childRect.width - 4, height: childRect.height - headerHeight - 2)
                    } else {
                        inner = childRect.insetBy(dx: 2, dy: 2)
                    }
                    visit(child, rect: inner, depth: depth + 1)
                }
            }
        }

        visit(root, rect: bounds, depth: 0)
        return tiles
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk). `values` must be sorted in
    /// descending order and already scaled to areas; their sum may be smaller than
    /// the rectangle, in which case the remainder stays empty.
    static func squarify(values: [Double], in bounds: CGRect) -> [CGRect] {
        var result: [CGRect] = []
        result.reserveCapacity(values.count)
        var remaining = bounds
        var index = 0

        func worst(sum: Double, minValue: Double, maxValue: Double, side: Double) -> Double {
            let side2 = side * side
            let sum2 = sum * sum
            return max(side2 * maxValue / sum2, sum2 / (side2 * minValue))
        }

        while index < values.count {
            let width = Double(remaining.width)
            let height = Double(remaining.height)
            guard width > 0, height > 0 else {
                // No room left: give the rest zero-size rects so indices still line up.
                while result.count < values.count { result.append(.zero) }
                break
            }
            let side = min(width, height)

            var rowEnd = index + 1
            var sum = values[index]
            var minValue = values[index]
            var maxValue = values[index]
            var currentWorst = worst(sum: sum, minValue: minValue, maxValue: maxValue, side: side)
            while rowEnd < values.count {
                let value = values[rowEnd]
                let candidate = worst(sum: sum + value, minValue: min(minValue, value),
                                      maxValue: max(maxValue, value), side: side)
                if candidate > currentWorst { break }
                sum += value
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
                currentWorst = candidate
                rowEnd += 1
            }

            if width >= height {
                // Lay the row out as a column on the left.
                let columnWidth = min(width, sum / height)
                var y = Double(remaining.minY)
                for value in values[index..<rowEnd] {
                    let tileHeight = value / columnWidth
                    result.append(CGRect(x: Double(remaining.minX), y: y, width: columnWidth, height: tileHeight))
                    y += tileHeight
                }
                remaining = CGRect(x: remaining.minX + CGFloat(columnWidth), y: remaining.minY,
                                   width: remaining.width - CGFloat(columnWidth), height: remaining.height)
            } else {
                // Lay the row out along the top.
                let rowHeight = min(height, sum / width)
                var x = Double(remaining.minX)
                for value in values[index..<rowEnd] {
                    let tileWidth = value / rowHeight
                    result.append(CGRect(x: x, y: Double(remaining.minY), width: tileWidth, height: rowHeight))
                    x += tileWidth
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + CGFloat(rowHeight),
                                   width: remaining.width, height: remaining.height - CGFloat(rowHeight))
            }
            index = rowEnd
        }
        return result
    }

    /// Deepest tile containing the point.
    static func hitTest(_ point: CGPoint, tiles: [TreemapTile]) -> Int? {
        for index in tiles.indices.reversed() where tiles[index].rect.contains(point) {
            return index
        }
        return nil
    }
}
