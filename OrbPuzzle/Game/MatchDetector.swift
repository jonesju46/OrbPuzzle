import Foundation

struct MatchDetector {
    private static let minimumRunLength = 3

    func detect(in grid: OrbGrid) -> [MatchResult] {
        var matchedByType: [OrbType: Set<GridPosition>] = [:]

        for row in 0..<grid.rows {
            var start = 0
            while start < grid.columns {
                guard let type = grid.orb(at: GridPosition(row: row, column: start))?.type else {
                    start += 1
                    continue
                }
                var end = start + 1
                while end < grid.columns,
                      grid.orb(at: GridPosition(row: row, column: end))?.type == type {
                    end += 1
                }
                if end - start >= Self.minimumRunLength {
                    for column in start..<end {
                        matchedByType[type, default: []].insert(GridPosition(row: row, column: column))
                    }
                }
                start = end
            }
        }

        for column in 0..<grid.columns {
            var start = 0
            while start < grid.rows {
                guard let type = grid.orb(at: GridPosition(row: start, column: column))?.type else {
                    start += 1
                    continue
                }
                var end = start + 1
                while end < grid.rows,
                      grid.orb(at: GridPosition(row: end, column: column))?.type == type {
                    end += 1
                }
                if end - start >= Self.minimumRunLength {
                    for row in start..<end {
                        matchedByType[type, default: []].insert(GridPosition(row: row, column: column))
                    }
                }
                start = end
            }
        }

        return normalize(matchedByType)
    }

    /// Horizontal and vertical runs contribute candidate positions. Normalizing
    /// by same-type orthogonal connected components merges shared T/L/cross
    /// positions exactly once while preserving disconnected runs as combos.
    private func normalize(
        _ matchedByType: [OrbType: Set<GridPosition>]
    ) -> [MatchResult] {
        var results: [MatchResult] = []
        for (type, positions) in matchedByType {
            var remaining = positions
            while let seed = remaining.first {
                var component: Set<GridPosition> = []
                var queue = [seed]
                remaining.remove(seed)
                while let current = queue.popLast() {
                    component.insert(current)
                    let neighbors = [
                        GridPosition(row: current.row - 1, column: current.column),
                        GridPosition(row: current.row + 1, column: current.column),
                        GridPosition(row: current.row, column: current.column - 1),
                        GridPosition(row: current.row, column: current.column + 1)
                    ]
                    for neighbor in neighbors where remaining.remove(neighbor) != nil {
                        queue.append(neighbor)
                    }
                }
                results.append(MatchResult(type: type, positions: component))
            }
        }
        return results.sorted {
            let lhs = firstPosition(in: $0.positions)
            let rhs = firstPosition(in: $1.positions)
            return (lhs.row, lhs.column) < (rhs.row, rhs.column)
        }
    }

    private func firstPosition(in positions: Set<GridPosition>) -> GridPosition {
        positions.min { ($0.row, $0.column) < ($1.row, $1.column) }
            ?? GridPosition(row: .max, column: .max)
    }
}
