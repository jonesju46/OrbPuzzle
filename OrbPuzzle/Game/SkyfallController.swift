import Foundation

/// Plans only the types for real empty refill slots. Existing Orb models are never
/// replaced, so every skyfall cycle preserves all non-removed IDs and types.
final class SkyfallController {
    private(set) var requestedCombos = GameSettings.defaultSkyfallComboCount
    private(set) var generatedCombos = 0

    var remainingCombos: Int { max(0, requestedCombos - generatedCombos) }
    var needsAnotherCycle: Bool { generatedCombos < requestedCombos }
    var isComplete: Bool { generatedCombos == requestedCombos }

    func reset(requestedCombos: Int) {
        self.requestedCombos = min(max(requestedCombos, 1), 99)
        generatedCombos = 0
    }

    @discardableResult
    func recordCycle(matchGroupCount: Int) -> Bool {
        guard needsAnotherCycle, matchGroupCount == 1 else { return false }
        generatedCombos += 1
        return true
    }

    func makeControlledRefill(grid: OrbGrid, refillSlots: [GridPosition]) -> [OrbType]? {
        var generator = SystemRandomNumberGenerator()
        return makeControlledRefill(grid: grid, refillSlots: refillSlots, using: &generator)
    }

    func makeSafeRefill(grid: OrbGrid, refillSlots: [GridPosition]) -> [OrbType]? {
        var generator = SystemRandomNumberGenerator()
        return makeSafeRefill(grid: grid, refillSlots: refillSlots, using: &generator)
    }

    func makeControlledRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        using generator: inout R
    ) -> [OrbType]? {
        guard refillSlots == grid.emptyPositions(), refillSlots.count >= 3 else { return nil }
        let candidates = tripleCandidates(in: Set(refillSlots)).shuffled(using: &generator)

        for target in candidates {
            for targetType in OrbType.allCases.shuffled(using: &generator) {
                for _ in 0..<32 {
                    guard let planned = planTypes(
                        grid: grid,
                        refillSlots: refillSlots,
                        forcedTypes: Dictionary(uniqueKeysWithValues: target.map { ($0, targetType) }),
                        using: &generator
                    ) else { continue }
                    let simulated = simulatedGrid(grid: grid, slots: refillSlots, types: planned)
                    let matches = MatchDetector().detect(in: simulated)
                    guard matches.count == 1,
                          matches[0].count == 3,
                          matches[0].positions == Set(target),
                          isStableAfterRemoving(matches[0], from: simulated) else { continue }
                    return planned
                }
            }
        }
        return nil
    }

    func makeSafeRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        using generator: inout R
    ) -> [OrbType]? {
        guard refillSlots == grid.emptyPositions() else { return nil }
        for _ in 0..<128 {
            guard let planned = planTypes(
                grid: grid,
                refillSlots: refillSlots,
                forcedTypes: [:],
                using: &generator
            ) else { continue }
            let simulated = simulatedGrid(grid: grid, slots: refillSlots, types: planned)
            if MatchDetector().detect(in: simulated).isEmpty { return planned }
        }
        return nil
    }

    private func tripleCandidates(in slots: Set<GridPosition>) -> [[GridPosition]] {
        var result: [[GridPosition]] = []
        for row in 0..<OrbGrid.defaultRows {
            for column in 0...(OrbGrid.defaultColumns - 3) {
                let candidate = (0..<3).map { GridPosition(row: row, column: column + $0) }
                if candidate.allSatisfy(slots.contains) { result.append(candidate) }
            }
        }
        for column in 0..<OrbGrid.defaultColumns {
            for row in 0...(OrbGrid.defaultRows - 3) {
                let candidate = (0..<3).map { GridPosition(row: row + $0, column: column) }
                if candidate.allSatisfy(slots.contains) { result.append(candidate) }
            }
        }
        return result
    }

    private func planTypes<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        forcedTypes: [GridPosition: OrbType],
        using generator: inout R
    ) -> [OrbType]? {
        var board = (0..<grid.rows).map { row in
            (0..<grid.columns).map { column in
                grid.orb(at: GridPosition(row: row, column: column))?.type
            }
        }
        for (position, type) in forcedTypes { board[position.row][position.column] = type }

        for position in refillSlots.shuffled(using: &generator) where forcedTypes[position] == nil {
            let candidates = OrbType.allCases.shuffled(using: &generator)
            guard let type = candidates.first(where: {
                !formsMatch(type: $0, at: position, in: board)
            }) else { return nil }
            board[position.row][position.column] = type
        }
        return refillSlots.compactMap { board[$0.row][$0.column] }
    }

    private func formsMatch(type: OrbType, at position: GridPosition, in board: [[OrbType?]]) -> Bool {
        func contiguousCount(rowStep: Int, columnStep: Int) -> Int {
            var count = 0
            var row = position.row + rowStep
            var column = position.column + columnStep
            while (0..<OrbGrid.defaultRows).contains(row),
                  (0..<OrbGrid.defaultColumns).contains(column),
                  board[row][column] == type {
                count += 1
                row += rowStep
                column += columnStep
            }
            return count
        }
        let horizontal = 1 + contiguousCount(rowStep: 0, columnStep: -1)
            + contiguousCount(rowStep: 0, columnStep: 1)
        let vertical = 1 + contiguousCount(rowStep: -1, columnStep: 0)
            + contiguousCount(rowStep: 1, columnStep: 0)
        return horizontal >= 3 || vertical >= 3
    }

    private func simulatedGrid(grid: OrbGrid, slots: [GridPosition], types: [OrbType]) -> OrbGrid {
        let typeByPosition = Dictionary(uniqueKeysWithValues: zip(slots, types))
        let completeTypes = (0..<grid.rows).map { row in
            (0..<grid.columns).map { column in
                let position = GridPosition(row: row, column: column)
                return grid.orb(at: position)?.type ?? typeByPosition[position] ?? .fire
            }
        }
        return OrbGrid(types: completeTypes)
    }

    private func isStableAfterRemoving(_ match: MatchResult, from grid: OrbGrid) -> Bool {
        _ = grid.remove(match.positions)
        _ = grid.collapse()
        return MatchDetector().detect(in: grid).isEmpty
    }
}
