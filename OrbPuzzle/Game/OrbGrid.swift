import Foundation

struct OrbMovement: Equatable, Sendable {
    let orb: Orb
    let from: GridPosition
    let to: GridPosition
}

struct OrbSpawn: Equatable, Sendable {
    let orb: Orb
    let destination: GridPosition
    let sourceRow: Int
}

final class OrbGrid {
    static let defaultRows = 5
    static let defaultColumns = 6

    let rows: Int
    let columns: Int
    private(set) var cells: [[Orb?]]

    init(rows: Int = defaultRows, columns: Int = defaultColumns) {
        self.rows = rows
        self.columns = columns
        cells = Array(repeating: Array(repeating: nil, count: columns), count: rows)
    }

    convenience init(types: [[OrbType]]) {
        precondition(!types.isEmpty && !(types.first?.isEmpty ?? true))
        precondition(types.allSatisfy { $0.count == types[0].count })
        self.init(rows: types.count, columns: types[0].count)
        for row in 0..<rows {
            for column in 0..<columns {
                cells[row][column] = Orb(type: types[row][column])
            }
        }
    }

    func contains(_ position: GridPosition) -> Bool {
        (0..<rows).contains(position.row) && (0..<columns).contains(position.column)
    }

    func orb(at position: GridPosition) -> Orb? {
        guard contains(position) else { return nil }
        return cells[position.row][position.column]
    }

    @discardableResult
    func swap(_ first: GridPosition, _ second: GridPosition) -> Bool {
        guard contains(first), contains(second), first.isAdjacent(to: second) else { return false }
        let held = cells[first.row][first.column]
        cells[first.row][first.column] = cells[second.row][second.column]
        cells[second.row][second.column] = held
        return true
    }

    func fillAvoidingInitialMatches(maxRetries: Int = 200, randomType: () -> OrbType) {
        let detector = MatchDetector()
        for _ in 0..<maxRetries {
            for row in 0..<rows {
                for column in 0..<columns {
                    cells[row][column] = Orb(type: randomType())
                }
            }
            if detector.detect(in: self).isEmpty { return }
        }

        // Deterministic fallback guarantees no initial three-in-a-row board.
        let cases = OrbType.allCases
        for row in 0..<rows {
            for column in 0..<columns {
                cells[row][column] = Orb(type: cases[(row * 2 + column) % cases.count])
            }
        }
    }

    func remove(_ positions: Set<GridPosition>) -> [Orb] {
        var removed: [Orb] = []
        for position in positions where contains(position) {
            if let orb = cells[position.row][position.column] { removed.append(orb) }
            cells[position.row][position.column] = nil
        }
        return removed
    }

    func collapse() -> [OrbMovement] {
        var movements: [OrbMovement] = []
        for column in 0..<columns {
            var writeRow = 0
            for readRow in 0..<rows {
                guard let orb = cells[readRow][column] else { continue }
                if readRow != writeRow {
                    cells[writeRow][column] = orb
                    cells[readRow][column] = nil
                    movements.append(OrbMovement(
                        orb: orb,
                        from: GridPosition(row: readRow, column: column),
                        to: GridPosition(row: writeRow, column: column)
                    ))
                }
                writeRow += 1
            }
        }
        return movements
    }

    func refill(typeProvider: (GridPosition) -> OrbType) -> [OrbSpawn] {
        var spawns: [OrbSpawn] = []
        for column in 0..<columns {
            let emptyRows = (0..<rows).filter { cells[$0][column] == nil }
            for (offset, row) in emptyRows.enumerated() {
                let destination = GridPosition(row: row, column: column)
                let orb = Orb(type: typeProvider(destination))
                cells[row][column] = orb
                spawns.append(OrbSpawn(orb: orb, destination: destination, sourceRow: rows + offset))
            }
        }
        return spawns
    }
}
