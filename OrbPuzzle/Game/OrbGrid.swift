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

    /// Count-only upper bound; does not imply a reachable layout or timed solution.
    static func theoreticalMaxCombo(for counts: [OrbType: Int]) -> Int {
        OrbType.allCases.reduce(0) { $0 + max(0, counts[$1, default: 0]) / 3 }
    }

    var theoreticalMaxCombo: Int {
        let counts = cells.flatMap { $0 }.compactMap { $0 }.reduce(into: [OrbType: Int]()) {
            $0[$1.type, default: 0] += 1
        }
        return Self.theoreticalMaxCombo(for: counts)
    }

    // Enumerated once. All ordered quotas are equally eligible, so no color
    // receives a preferred count. Every quota totals 30 with 3...7 of each color.
    private static let initialQuotas: [Int: [[Int]]] = {
        var result: [Int: [[Int]]] = [:]
        func visit(_ counts: [Int], _ total: Int) {
            if counts.count == OrbType.allCases.count {
                guard total == defaultRows * defaultColumns else { return }
                let potential = counts.reduce(0) { $0 + $1 / 3 }
                if potential >= 8 { result[potential, default: []].append(counts) }
                return
            }
            for count in 3...7 where total + count <= defaultRows * defaultColumns {
                visit(counts + [count], total + count)
            }
        }
        visit([], 0)
        return result
    }()

    func fillBalancedInitialBoard() {
        var generator = SystemRandomNumberGenerator()
        fillBalancedInitialBoard(using: &generator)
    }

    /// Initial generation only. Refill continues to use the existing algorithms.
    func fillBalancedInitialBoard<R: RandomNumberGenerator>(
        maxRetries: Int = 200,
        using generator: inout R
    ) {
        precondition(rows == Self.defaultRows && columns == Self.defaultColumns)
        let roll = Int.random(in: 0..<100, using: &generator)
        let target = roll < 40 ? 8 : (roll < 85 ? 9 : 10)
        guard let quota = Self.initialQuotas[target]?.randomElement(using: &generator)
        else { preconditionFailure("Missing initial-board quota") }
        let bag = zip(OrbType.allCases, quota).flatMap { type, count in
            Array(repeating: type, count: count)
        }
        func assign(_ types: [OrbType]) {
            for row in 0..<rows {
                for column in 0..<columns {
                    cells[row][column] = Orb(type: types[row * columns + column])
                }
            }
        }
        let detector = MatchDetector()
        for _ in 0..<max(0, maxRetries) {
            assign(bag.shuffled(using: &generator))
            if detector.detect(in: self).isEmpty { return }
        }

        // Bounded emergency fallback: verified match-free 10-potential layout.
        // Random color permutation and reflections keep all colors symmetric.
        let palette = OrbType.allCases.shuffled(using: &generator)
        let layout = [
            [4, 2, 1, 1, 3, 0], [0, 5, 1, 3, 1, 5],
            [2, 2, 0, 3, 3, 1], [2, 3, 2, 2, 0, 1], [0, 4, 4, 5, 3, 0]
        ]
        let flipRows = Bool.random(using: &generator)
        let flipColumns = Bool.random(using: &generator)
        assign((0..<rows).flatMap { row in
            (0..<columns).map { column in
                palette[layout[flipRows ? rows - 1 - row : row]
                    [flipColumns ? columns - 1 - column : column]]
            }
        })
        assert(detector.detect(in: self).isEmpty)
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
        let slots = emptyPositions()
        let types = slots.map(typeProvider)
        return refill(types: types, at: slots)
    }

    /// Empty slots in the exact order used for refill: bottom-to-top per column.
    func emptyPositions() -> [GridPosition] {
        var positions: [GridPosition] = []
        for column in 0..<columns {
            for row in 0..<rows where cells[row][column] == nil {
                positions.append(GridPosition(row: row, column: column))
            }
        }
        return positions
    }

    func refill(types: [OrbType], at positions: [GridPosition]) -> [OrbSpawn] {
        precondition(types.count == positions.count)
        precondition(positions == emptyPositions())
        var spawns: [OrbSpawn] = []
        var offsetsByColumn: [Int: Int] = [:]
        for (position, type) in zip(positions, types) {
            let offset = offsetsByColumn[position.column, default: 0]
            let orb = Orb(type: type)
            cells[position.row][position.column] = orb
            spawns.append(OrbSpawn(
                orb: orb,
                destination: position,
                sourceRow: rows + offset
            ))
            offsetsByColumn[position.column] = offset + 1
        }
        return spawns
    }
}
