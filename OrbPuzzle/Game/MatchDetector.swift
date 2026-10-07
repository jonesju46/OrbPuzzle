import Foundation

struct MatchDetector {
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
                if end - start >= 3 {
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
                if end - start >= 3 {
                    for row in start..<end {
                        matchedByType[type, default: []].insert(GridPosition(row: row, column: column))
                    }
                }
                start = end
            }
        }

        // A connected matched shape of one type is one combo. Separate shapes remain separate combos.
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
            let lhs = $0.positions.min { ($0.row, $0.column) < ($1.row, $1.column) }!
            let rhs = $1.positions.min { ($0.row, $0.column) < ($1.row, $1.column) }!
            return (lhs.row, lhs.column) < (rhs.row, rhs.column)
        }
    }
}
