import Foundation

struct FriendlyRefillRoll: Equatable, Sendable {
    let groupCount: Int
    let probability: Double
    let roll: Double?
    let succeeded: Bool
}

struct FriendlyRefillDecision: Equatable, Sendable {
    let previousResolvedGroupCount: Int
    let emptySlotCount: Int
    let physicalMaxGroups: Int
    let candidateMaxGroups: Int
    let rolls: [FriendlyRefillRoll]
    let selectedTarget: Int?
}

struct FriendlyRefillPlan: Equatable, Sendable {
    let types: [OrbType]
    let plannedTarget: Int
}

enum FriendlyNaturalSkyfallPolicy {
    static let maximumGroupCount = 10
    static let refillProbabilities: [Double] = [
        1.00, 0.90, 0.80, 0.70, 0.60,
        0.50, 0.40, 0.30, 0.20, 0.10
    ]

    static func refillProbability(for groupCount: Int) -> Double? {
        guard (1...maximumGroupCount).contains(groupCount) else { return nil }
        return refillProbabilities[groupCount - 1]
    }

    static func selectTarget(
        previousResolvedGroupCount: Int,
        emptySlotCount: Int,
        roll: (Int) -> Double
    ) -> FriendlyRefillDecision {
        let physicalMaxGroups = max(0, emptySlotCount) / 3
        let candidateMaxGroups = min(
            max(0, previousResolvedGroupCount),
            physicalMaxGroups,
            maximumGroupCount
        )

        // One resolved group is the convergence boundary. The next refill is
        // non-forced, so the chain can become stable or continue only naturally.
        guard previousResolvedGroupCount > 1, candidateMaxGroups > 0 else {
            return FriendlyRefillDecision(
                previousResolvedGroupCount: previousResolvedGroupCount,
                emptySlotCount: emptySlotCount,
                physicalMaxGroups: physicalMaxGroups,
                candidateMaxGroups: candidateMaxGroups,
                rolls: [],
                selectedTarget: nil
            )
        }

        var attempts: [FriendlyRefillRoll] = []
        for groupCount in stride(from: candidateMaxGroups, through: 1, by: -1) {
            guard let probability = refillProbability(for: groupCount) else { continue }
            if groupCount == 1 {
                attempts.append(FriendlyRefillRoll(
                    groupCount: groupCount,
                    probability: probability,
                    roll: nil,
                    succeeded: true
                ))
                return FriendlyRefillDecision(
                    previousResolvedGroupCount: previousResolvedGroupCount,
                    emptySlotCount: emptySlotCount,
                    physicalMaxGroups: physicalMaxGroups,
                    candidateMaxGroups: candidateMaxGroups,
                    rolls: attempts,
                    selectedTarget: groupCount
                )
            }

            let value = roll(groupCount)
            let succeeded = value < probability
            attempts.append(FriendlyRefillRoll(
                groupCount: groupCount,
                probability: probability,
                roll: value,
                succeeded: succeeded
            ))
            if succeeded {
                return FriendlyRefillDecision(
                    previousResolvedGroupCount: previousResolvedGroupCount,
                    emptySlotCount: emptySlotCount,
                    physicalMaxGroups: physicalMaxGroups,
                    candidateMaxGroups: candidateMaxGroups,
                    rolls: attempts,
                    selectedTarget: groupCount
                )
            }
        }

        return FriendlyRefillDecision(
            previousResolvedGroupCount: previousResolvedGroupCount,
            emptySlotCount: emptySlotCount,
            physicalMaxGroups: physicalMaxGroups,
            candidateMaxGroups: candidateMaxGroups,
            rolls: attempts,
            selectedTarget: nil
        )
    }
}

/// Plans only the types for real empty refill slots. Existing Orb models are never
/// replaced, so every skyfall cycle preserves all non-removed IDs and types.
final class SkyfallController {
    private(set) var requestedCombos = GameSettings.effectiveSkyfallComboCount(
        enabled: GameSettings.defaultSkyfallComboEnabled,
        configured: GameSettings.defaultSkyfallComboCount
    )
    private(set) var generatedCombos = 0

    var hasControlledTarget: Bool { requestedCombos > 0 }
    var remainingCombos: Int { max(0, requestedCombos - generatedCombos) }
    var needsAnotherCycle: Bool { hasControlledTarget && generatedCombos < requestedCombos }
    var isComplete: Bool { generatedCombos >= requestedCombos }

    func reset(requestedCombos: Int) {
        self.requestedCombos = min(max(requestedCombos, 0), 99)
        generatedCombos = 0
    }

    @discardableResult
    func recordDetectedGroups(_ matchGroupCount: Int) -> Bool {
        guard matchGroupCount > 0 else { return false }
        generatedCombos += matchGroupCount
        return true
    }

    func selectFriendlyRefillTarget(
        previousResolvedGroupCount: Int,
        emptySlotCount: Int,
        roll: (Int) -> Double = { _ in Double.random(in: 0..<1) }
    ) -> FriendlyRefillDecision? {
        guard !hasControlledTarget else { return nil }
        return FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: previousResolvedGroupCount,
            emptySlotCount: emptySlotCount,
            roll: roll
        )
    }

    func makeControlledRefill(grid: OrbGrid, refillSlots: [GridPosition]) -> [OrbType]? {
        var generator = SystemRandomNumberGenerator()
        return makeControlledRefill(grid: grid, refillSlots: refillSlots, using: &generator)
    }

    func makeSafeRefill(grid: OrbGrid, refillSlots: [GridPosition]) -> [OrbType]? {
        var generator = SystemRandomNumberGenerator()
        return makeSafeRefill(grid: grid, refillSlots: refillSlots, using: &generator)
    }

    func makeFriendlyNaturalRefill(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        targetGroupCount: Int
    ) -> FriendlyRefillPlan? {
        var generator = SystemRandomNumberGenerator()
        return makeFriendlyNaturalRefill(
            grid: grid,
            refillSlots: refillSlots,
            targetGroupCount: targetGroupCount,
            using: &generator
        )
    }

    /// Unfiltered six-color refill retained for deterministic natural-refill
    /// tests and callers that explicitly request ordinary random generation.
    func makeNaturalRefill(grid: OrbGrid, refillSlots: [GridPosition]) -> [OrbType]? {
        return makeNaturalRefill(grid: grid, refillSlots: refillSlots) {
            OrbType.allCases.randomElement() ?? .fire
        }
    }

    func makeNaturalRefill(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        typeProvider: () -> OrbType
    ) -> [OrbType]? {
        guard refillSlots == grid.emptyPositions() else { return nil }
        return refillSlots.map { _ in typeProvider() }
    }

    func makeControlledRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        using generator: inout R
    ) -> [OrbType]? {
        guard needsAnotherCycle,
              refillSlots == grid.emptyPositions(),
              !refillSlots.isEmpty,
              MatchDetector().detect(in: grid).isEmpty else { return nil }

        let maximumGroupCount = min(
            remainingCombos,
            refillSlots.count,
            (grid.rows * grid.columns) / 3
        )
        guard maximumGroupCount > 0 else { return nil }

        return makeMatchProducingRefill(
            grid: grid,
            refillSlots: refillSlots,
            maximumGroupCount: maximumGroupCount,
            using: &generator
        )
    }

    func makeFriendlyNaturalRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        targetGroupCount: Int,
        using generator: inout R
    ) -> FriendlyRefillPlan? {
        guard !hasControlledTarget,
              targetGroupCount > 0,
              refillSlots == grid.emptyPositions(),
              !refillSlots.isEmpty else { return nil }

        // Gravity may already have formed a real match from preserved orbs. Fill
        // only the empty slots safely and let the full-board detector resolve it.
        if !MatchDetector().detect(in: grid).isEmpty {
            guard let types = makeSafeRefill(
                grid: grid,
                refillSlots: refillSlots,
                using: &generator
            ) else { return nil }
            let plannedTarget = MatchDetector().detect(
                in: simulatedGrid(grid: grid, slots: refillSlots, types: types)
            ).count
            return FriendlyRefillPlan(types: types, plannedTarget: plannedTarget)
        }

        let maximumGroupCount = min(
            targetGroupCount,
            refillSlots.count / 3,
            FriendlyNaturalSkyfallPolicy.maximumGroupCount
        )
        guard maximumGroupCount > 0,
              let types = makeMatchProducingRefill(
            grid: grid,
            refillSlots: refillSlots,
            maximumGroupCount: maximumGroupCount,
            using: &generator
        ) else { return nil }
        let plannedTarget = MatchDetector().detect(
            in: simulatedGrid(grid: grid, slots: refillSlots, types: types)
        ).count
        guard plannedTarget > 0 else { return nil }
        return FriendlyRefillPlan(types: types, plannedTarget: plannedTarget)
    }

    private func makeMatchProducingRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        maximumGroupCount: Int,
        using generator: inout R
    ) -> [OrbType]? {

        if refillSlots.count <= 4 {
            return exhaustivePlan(
                grid: grid,
                refillSlots: refillSlots,
                maximumGroupCount: maximumGroupCount
            )
        }

        let candidates = tripleCandidates(in: Set(refillSlots))
        var bestPlan: [OrbType]?
        var bestScore = (groups: 0, removed: 0)

        // Prefer the largest legal batch, but keep the work per animation cycle
        // bounded. The outer resolve pipeline remains completion-driven, so a
        // target of 99 never becomes a synchronous 99-cycle loop.
        for desiredGroupCount in stride(from: maximumGroupCount, through: 1, by: -1) {
            var bestDesiredPlan: [OrbType]?
            var bestDesiredRemoved = 0

            for _ in 0..<96 {
                guard let groups = selectDisjointCandidates(
                    count: desiredGroupCount,
                    from: candidates,
                    using: &generator
                ) else { break }
                let forcedTypes = forcedTypeAssignments(
                    for: groups,
                    using: &generator
                )
                guard let planned = planTypes(
                    grid: grid,
                    refillSlots: refillSlots,
                    forcedTypes: forcedTypes,
                    using: &generator
                ) else { continue }
                let score = planScore(
                    grid: grid,
                    refillSlots: refillSlots,
                    types: planned,
                    maximumGroupCount: maximumGroupCount
                )
                guard score.groups > 0 else { continue }
                if score.groups > bestScore.groups
                    || (score.groups == bestScore.groups && score.removed > bestScore.removed) {
                    bestPlan = planned
                    bestScore = score
                }
                if score.groups == desiredGroupCount,
                   score.removed > bestDesiredRemoved {
                    bestDesiredPlan = planned
                    bestDesiredRemoved = score.removed
                }
            }
            if let bestDesiredPlan { return bestDesiredPlan }
        }

        // Groups can also be completed by existing orbs, so sample bounded full
        // assignments after trying all-new disjoint triples. MatchDetector still
        // validates the complete board and is the only source of the group count.
        for _ in 0..<384 {
            let planned = refillSlots.map { _ in
                OrbType.allCases.randomElement(using: &generator) ?? .fire
            }
            let score = planScore(
                grid: grid,
                refillSlots: refillSlots,
                types: planned,
                maximumGroupCount: maximumGroupCount
            )
            if score.groups > bestScore.groups
                || (score.groups == bestScore.groups && score.removed > bestScore.removed) {
                bestPlan = planned
                bestScore = score
            }
            if bestScore.groups == maximumGroupCount { break }
        }
        return bestPlan
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
            // Candidate checks apply only to new slots. Any match made solely by
            // existing orbs survives unchanged and is found by the normal
            // full-board scan after the fall animation completes.
            return planned
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

    private func exhaustivePlan(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        maximumGroupCount: Int
    ) -> [OrbType]? {
        var current = Array(repeating: OrbType.fire, count: refillSlots.count)
        var bestPlan: [OrbType]?
        var bestScore = (groups: 0, removed: 0)

        func visit(_ index: Int) {
            guard index < current.count else {
                let score = planScore(
                    grid: grid,
                    refillSlots: refillSlots,
                    types: current,
                    maximumGroupCount: maximumGroupCount
                )
                if score.groups > bestScore.groups
                    || (score.groups == bestScore.groups && score.removed > bestScore.removed) {
                    bestPlan = current
                    bestScore = score
                }
                return
            }
            for type in OrbType.allCases {
                current[index] = type
                visit(index + 1)
            }
        }

        visit(0)
        return bestPlan
    }

    private func selectDisjointCandidates<R: RandomNumberGenerator>(
        count: Int,
        from candidates: [[GridPosition]],
        using generator: inout R
    ) -> [[GridPosition]]? {
        guard count > 0 else { return [] }
        for _ in 0..<24 {
            var selected: [[GridPosition]] = []
            var occupied: Set<GridPosition> = []
            for candidate in candidates.shuffled(using: &generator)
            where Set(candidate).isDisjoint(with: occupied) {
                selected.append(candidate)
                occupied.formUnion(candidate)
                if selected.count == count { return selected }
            }
        }
        return nil
    }

    private func forcedTypeAssignments<R: RandomNumberGenerator>(
        for groups: [[GridPosition]],
        using generator: inout R
    ) -> [GridPosition: OrbType] {
        var assignments: [GridPosition: OrbType] = [:]
        for group in groups {
            let candidates = OrbType.allCases.shuffled(using: &generator)
            let type = candidates.min { lhs, rhs in
                adjacentConflictCount(type: lhs, group: group, assignments: assignments)
                    < adjacentConflictCount(type: rhs, group: group, assignments: assignments)
            } ?? .fire
            for position in group { assignments[position] = type }
        }
        return assignments
    }

    private func adjacentConflictCount(
        type: OrbType,
        group: [GridPosition],
        assignments: [GridPosition: OrbType]
    ) -> Int {
        group.reduce(into: 0) { count, position in
            let neighbors = [
                GridPosition(row: position.row - 1, column: position.column),
                GridPosition(row: position.row + 1, column: position.column),
                GridPosition(row: position.row, column: position.column - 1),
                GridPosition(row: position.row, column: position.column + 1)
            ]
            count += neighbors.filter { assignments[$0] == type }.count
        }
    }

    private func planScore(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        types: [OrbType],
        maximumGroupCount: Int
    ) -> (groups: Int, removed: Int) {
        guard types.count == refillSlots.count else { return (0, 0) }
        let simulated = simulatedGrid(grid: grid, slots: refillSlots, types: types)
        let matches = MatchDetector().detect(in: simulated)
        guard !matches.isEmpty, matches.count <= maximumGroupCount else { return (0, 0) }
        let removedPositions = matches.reduce(into: Set<GridPosition>()) {
            $0.formUnion($1.positions)
        }
        return (matches.count, removedPositions.count)
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
}
