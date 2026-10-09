import Foundation

struct FriendlyRefillRoll: Equatable, Sendable {
    let groupCount: Int
    let probability: Double
    let roll: Double
    let succeeded: Bool
}

struct FriendlyRefillDecision: Equatable, Sendable {
    let previousResolvedGroupCount: Int
    let removedOrbCount: Int
    let capacityTarget: Int
    let emptySlotCount: Int
    let physicalMaxGroups: Int
    let candidateMaxGroups: Int
    let rolls: [FriendlyRefillRoll]
    let selectedTarget: Int
}

struct FriendlyRefillPlan: Equatable, Sendable {
    let types: [OrbType]
    let plannedTarget: Int
    let forcedTypes: [GridPosition: OrbType]
    let strategy: String
    let forcedGroups: [[GridPosition]]

    init(types: [OrbType], plannedTarget: Int,
         forcedTypes: [GridPosition: OrbType] = [:], strategy: String = "preserved-match",
         forcedGroups: [[GridPosition]] = []) {
        self.types = types
        self.plannedTarget = plannedTarget
        self.forcedTypes = forcedTypes
        self.strategy = strategy
        self.forcedGroups = forcedGroups
    }
}

enum FriendlyNaturalSkyfallPolicy {
    static let maximumGroupCount = 10
    static let hitProbability = 0.50

    static func capacityTarget(for removedOrbCount: Int) -> Int {
        max(0, removedOrbCount) / 3
    }

    static func selectTarget(
        previousResolvedGroupCount: Int,
        removedOrbCount: Int,
        emptySlotCount: Int,
        roll: (Int) -> Double
    ) -> FriendlyRefillDecision {
        let capacity = capacityTarget(for: removedOrbCount)
        let physicalMaxGroups = max(0, emptySlotCount) / 3
        // Previous groups and actual slots are diagnostics, never the roll basis.
        // The planner rejects an impossible target rather than shrinking it.
        let attempts: [FriendlyRefillRoll]
        let selectedTarget: Int
        if capacity > 0 {
            let value = roll(capacity)
            let succeeded = value < hitProbability
            attempts = [FriendlyRefillRoll(groupCount: capacity, probability: hitProbability,
                                          roll: value, succeeded: succeeded)]
            selectedTarget = succeeded ? capacity : 0
        } else {
            attempts = []
            selectedTarget = 0
        }
        return FriendlyRefillDecision(
            previousResolvedGroupCount: previousResolvedGroupCount,
            removedOrbCount: removedOrbCount, capacityTarget: capacity,
            emptySlotCount: emptySlotCount, physicalMaxGroups: physicalMaxGroups,
            candidateMaxGroups: capacity, rolls: attempts, selectedTarget: selectedTarget
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
    private(set) var lastFriendlyPlanningFailure: String?

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
        removedOrbCount: Int,
        emptySlotCount: Int,
        roll: (Int) -> Double = { _ in Double.random(in: 0..<1) }
    ) -> FriendlyRefillDecision? {
        guard !hasControlledTarget else { return nil }
        return FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: previousResolvedGroupCount,
            removedOrbCount: removedOrbCount,
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

    /// OFF-mode refill always returns one type for every current empty slot.
    /// Prefer a match-avoiding assignment, then fall back to ordinary random
    /// types so a safe-planning failure can never leave the board partially empty.
    func makeNonForcedRefill(grid: OrbGrid, refillSlots: [GridPosition]) -> [OrbType]? {
        var generator = SystemRandomNumberGenerator()
        return makeNonForcedRefill(grid: grid, refillSlots: refillSlots, using: &generator)
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
        lastFriendlyPlanningFailure = nil
        guard !hasControlledTarget,
              targetGroupCount > 0,
              refillSlots == grid.emptyPositions(),
              !refillSlots.isEmpty else { return nil }

        guard targetGroupCount <= refillSlots.count / 3,
              targetGroupCount <= FriendlyNaturalSkyfallPolicy.maximumGroupCount else { return nil }
        let maximumGroupCount = targetGroupCount
        guard maximumGroupCount > 0,
              let candidate = makeFriendlyMatchProducingRefill(
            grid: grid,
            refillSlots: refillSlots,
            maximumGroupCount: maximumGroupCount,
            using: &generator
        ) else { return nil }
        let plannedTarget = MatchDetector().detect(
            in: simulatedGrid(grid: grid, slots: refillSlots, types: candidate.types)
        ).count
        guard plannedTarget > 0 else { return nil }
        return FriendlyRefillPlan(
            types: candidate.types,
            plannedTarget: plannedTarget,
            forcedTypes: candidate.forcedTypes,
            strategy: candidate.strategy,
            forcedGroups: candidate.groups
        )
    }

    /// Friendly guarantees must be made entirely from this refill's new orbs.
    /// Preserved-orb matches are natural extras, never substitutes for the target.
    private func makeFriendlyMatchProducingRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        maximumGroupCount: Int,
        using generator: inout R
    ) -> (types: [OrbType], forcedTypes: [GridPosition: OrbType], strategy: String,
          groups: [[GridPosition]])? {
        let slots = Set(refillSlots)
        let candidates = tripleCandidates(in: slots).shuffled(using: &generator)
        // Bounded backtracking keeps the chosen target fixed. Packing failure,
        // color merges or natural extensions try another assignment, never N-1.
        var visited = 0
        var fullBoardChecks = 0
        let nodeLimit = 20_000
        let validationLimit = 2_048

        // Capture the complete assignment returned by color recursion, not just
        // its outermost three-cell prefix.
        var acceptedForced: [GridPosition: OrbType] = [:]
        func assignColors(_ groups: [[GridPosition]], at index: Int,
                          forced: [GridPosition: OrbType], using generator: inout R) -> [OrbType]? {
            visited += 1
            guard visited <= nodeLimit, fullBoardChecks < validationLimit else { return nil }
            if index == groups.count {
                fullBoardChecks += 1
                guard let types = planTypes(grid: grid, refillSlots: refillSlots,
                                            forcedTypes: forced, using: &generator) else { return nil }
                let matches = MatchDetector().detect(
                    in: simulatedGrid(grid: grid, slots: refillSlots, types: types)
                )
                guard matches.filter({ $0.positions.isSubset(of: slots) }).count >= maximumGroupCount
                else { return nil }
                acceptedForced = forced
                return types
            }
            let palette = OrbType.allCases.shuffled(using: &generator).sorted { lhs, rhs in
                forced.values.filter { $0 == lhs }.count < forced.values.filter { $0 == rhs }.count
            }
            for type in palette {
                guard adjacentConflictCount(type: type, group: groups[index], assignments: forced) == 0
                else { continue }
                var next = forced
                for position in groups[index] { next[position] = type }
                if let types = assignColors(groups, at: index + 1, forced: next, using: &generator) {
                    return types
                }
            }
            return nil
        }

        func place(from start: Int, groups: [[GridPosition]], occupied: Set<GridPosition>,
                   using generator: inout R) -> (types: [OrbType], groups: [[GridPosition]])? {
            visited += 1
            guard visited <= nodeLimit, fullBoardChecks < validationLimit else { return nil }
            if groups.count == maximumGroupCount {
                guard let types = assignColors(groups, at: 0, forced: [:], using: &generator)
                else { return nil }
                return (types, groups)
            }
            let needed = maximumGroupCount - groups.count
            let available = candidates.indices.filter {
                $0 >= start && Set(candidates[$0]).isDisjoint(with: occupied)
            }
            guard available.count >= needed,
                  slots.subtracting(occupied).count >= needed * 3 else { return nil }
            for index in available {
                let candidate = candidates[index]
                if let plan = place(from: index + 1, groups: groups + [candidate],
                                    occupied: occupied.union(candidate), using: &generator) {
                    return plan
                }
            }
            return nil
        }
        guard let plan = place(from: 0, groups: [], occupied: [], using: &generator) else {
            lastFriendlyPlanningFailure = visited >= nodeLimit || fullBoardChecks >= validationLimit
                ? "search-budget-exhausted" : "no-feasible-direct-target"
            return nil
        }
        return (plan.types, acceptedForced, "fixed-target-backtracking", plan.groups)
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

    func makeNonForcedRefill<R: RandomNumberGenerator>(
        grid: OrbGrid,
        refillSlots: [GridPosition],
        using generator: inout R
    ) -> [OrbType]? {
        guard refillSlots == grid.emptyPositions() else { return nil }
        if let safeTypes = makeSafeRefill(
            grid: grid,
            refillSlots: refillSlots,
            using: &generator
        ), safeTypes.count == refillSlots.count {
            return safeTypes
        }
        return makeNaturalRefill(grid: grid, refillSlots: refillSlots) {
            OrbType.allCases.randomElement(using: &generator) ?? .fire
        }
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

/// The OFF-mode path actually used by GameScene after gravity. Keeping the
/// decision, assignment and full-board scan together makes shape tests exercise
/// the caller's path, including fallback, rather than the planner alone.
struct FriendlyRefillPreparation {
    let slots: [GridPosition]
    let removedOrbCount: Int
    let decision: FriendlyRefillDecision
    let planCalled: Bool
    let plan: FriendlyRefillPlan?
    let types: [OrbType]
    let validationDetectedGroups: Int?
    let directGroupCount: Int
    let usesFriendlyTypes: Bool
    let fallbackReason: String?

    var refillMode: String { usesFriendlyTypes ? "friendly" : "nonForced" }

    func refill(in grid: OrbGrid) -> [OrbSpawn] {
        precondition(slots == grid.emptyPositions())
        precondition(types.count == slots.count)
        return grid.refill(types: types, at: slots)
    }

#if DEBUG
    func logDebug(resolveID: UInt) {
        for attempt in decision.rolls {
            print("[FRIENDLY_ROLL] resolveID=\(resolveID) previousResolvedGroupCount=\(decision.previousResolvedGroupCount) emptySlotCount=\(decision.emptySlotCount) physicalMaxGroups=\(decision.physicalMaxGroups) removedOrbCount=\(decision.removedOrbCount) capacityTarget=\(decision.capacityTarget) probability=\(attempt.probability) roll=\(attempt.roll) attemptedTarget=\(attempt.groupCount) selectedTarget=\(decision.selectedTarget)")
        }
        if decision.rolls.isEmpty {
            print("[FRIENDLY_ROLL] resolveID=\(resolveID) previousResolvedGroupCount=\(decision.previousResolvedGroupCount) emptySlotCount=\(decision.emptySlotCount) physicalMaxGroups=\(decision.physicalMaxGroups) removedOrbCount=\(decision.removedOrbCount) capacityTarget=\(decision.capacityTarget) probability=none roll=none selectedTarget=\(decision.selectedTarget)")
        }
        let forced = plan?.forcedTypes ?? [:]
        let positions = forced.keys.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        let rawTriples = plan?.forcedGroups.map { FriendlyRefillPipeline.describe($0) } ?? []
        let forcedTypes = positions.map { forced[$0]?.rawValue ?? "missing" }
        print("[FRIENDLY_PLAN] resolveID=\(resolveID) selectedTarget=\(decision.selectedTarget) plannedTarget=\(plan?.plannedTarget.description ?? "none") removedOrbs=\(removedOrbCount) rawForcedTriples=\(rawTriples) refillSlots=\(FriendlyRefillPipeline.describe(slots)) planCalled=\(planCalled) planReturned=\(plan != nil) plannedTypeCount=\(plan?.types.count ?? 0) forcedPositions=\(FriendlyRefillPipeline.describe(positions)) forcedTypes=\(forcedTypes) strategy=\(plan?.strategy ?? "none") forcedTraceAvailable=\(plan != nil && plan?.strategy != "multi-group-search") validationDetectedGroups=\(validationDetectedGroups?.description ?? "none") directGroups=\(directGroupCount) fallbackUsed=\(!usesFriendlyTypes) fallbackReason=\(fallbackReason ?? "none") planUsed=\(usesFriendlyTypes) refillMode=\(refillMode)")
    }
#endif
}

enum FriendlyRefillPipeline {
    static func prepare(
        grid: OrbGrid,
        previousResolution: ResolveResult,
        controller: SkyfallController
    ) -> FriendlyRefillPreparation {
        var generator = SystemRandomNumberGenerator()
        return prepare(grid: grid, previousResolution: previousResolution,
                       controller: controller, using: &generator)
    }

    static func prepare<R: RandomNumberGenerator>(
        grid: OrbGrid,
        previousResolution: ResolveResult,
        controller: SkyfallController,
        using generator: inout R,
        roll: (Int) -> Double = { _ in Double.random(in: 0..<1) },
        planProvider: ((OrbGrid, [GridPosition], Int) -> FriendlyRefillPlan?)? = nil
    ) -> FriendlyRefillPreparation {
        precondition(!controller.hasControlledTarget)
        let slots = grid.emptyPositions()
        guard let decision = controller.selectFriendlyRefillTarget(
            previousResolvedGroupCount: previousResolution.comboCount,
            removedOrbCount: previousResolution.removedOrbCount,
            emptySlotCount: slots.count,
            roll: roll
        ) else { preconditionFailure("Friendly preparation called in ON mode") }
        let called = decision.selectedTarget > 0
        let plan: FriendlyRefillPlan?
        if called {
            if let planProvider {
                // Test seam for verifying caller behavior on nil, malformed or
                // extra-natural-group plans. GameScene always uses the planner.
                plan = planProvider(grid, slots, decision.selectedTarget)
            } else {
                plan = controller.makeFriendlyNaturalRefill(
                    grid: grid, refillSlots: slots, targetGroupCount: decision.selectedTarget,
                    using: &generator
                )
            }
        } else {
            plan = nil
        }
        var detected: Int?
        var direct = 0
        var reason: String?
        if let plan {
            if plan.types.count != slots.count {
                reason = "assignment-count-mismatch"
            } else {
                let assignments = Dictionary(uniqueKeysWithValues: zip(slots, plan.types))
                let completeTypes = (0..<grid.rows).map { row in
                    (0..<grid.columns).map { column in
                        let position = GridPosition(row: row, column: column)
                        guard let type = grid.orb(at: position)?.type ?? assignments[position]
                        else { preconditionFailure("Incomplete Friendly assignment") }
                        return type
                    }
                }
                let matches = scan(in: OrbGrid(types: completeTypes)).matches
                detected = matches.count
                let slotSet = Set(slots)
                direct = matches.filter { $0.positions.isSubset(of: slotSet) }.count
                if detected == 0 { reason = "full-grid-validation-zero-groups" }
                else if direct < decision.selectedTarget { reason = "direct-groups-below-selected-target" }
            }
            if reason == nil {
                return FriendlyRefillPreparation(
                    slots: slots, removedOrbCount: previousResolution.removedOrbCount, decision: decision, planCalled: called, plan: plan,
                    types: plan.types, validationDetectedGroups: detected, directGroupCount: direct,
                    usesFriendlyTypes: true, fallbackReason: nil
                )
            }
        } else {
            if called {
                let empty = Set(slots)
                let hasDirectGeometry = slots.contains { position in
                    (empty.contains(GridPosition(row: position.row, column: position.column + 1))
                     && empty.contains(GridPosition(row: position.row, column: position.column + 2)))
                    || (empty.contains(GridPosition(row: position.row + 1, column: position.column))
                        && empty.contains(GridPosition(row: position.row + 2, column: position.column)))
                }
                reason = hasDirectGeometry ? (controller.lastFriendlyPlanningFailure ?? "planner-returned-nil") : "no-direct-new-slot-geometry"
            } else {
                reason = decision.candidateMaxGroups == 0 ? "insufficient-candidate-groups" : "roll-miss"
            }
        }
        let nonForced = controller.makeNonForcedRefill(grid: grid, refillSlots: slots, using: &generator)
        let types: [OrbType]
        if let nonForced, nonForced.count == slots.count {
            types = nonForced
        } else {
            reason = (reason ?? "unknown") + ";nonforced-assignment-count-mismatch"
            guard let natural = controller.makeNaturalRefill(grid: grid, refillSlots: slots, typeProvider: {
                OrbType.allCases.randomElement(using: &generator) ?? .fire
            }) else { preconditionFailure("Actual empty slots changed during planning") }
            types = natural
        }
        return FriendlyRefillPreparation(
            slots: slots, removedOrbCount: previousResolution.removedOrbCount, decision: decision, planCalled: called, plan: plan,
            types: types, validationDetectedGroups: detected, directGroupCount: direct,
            usesFriendlyTypes: false, fallbackReason: reason
        )
    }

    static func scan(in grid: OrbGrid) -> StableBoardScan {
        StableBoardScan(matches: MatchDetector().detect(in: grid))
    }

#if DEBUG
    static func describe(_ positions: [GridPosition]) -> String {
        let ordered = positions.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        return "[" + ordered.map { "(\($0.row),\($0.column))" }.joined(separator: ",") + "]"
    }
#endif
}

#if DEBUG
struct FriendlyRefillDebugStatistics {
    var eligible = 0
    var targets = 0
    var plans = 0
    var detected = 0

    mutating func record(_ preparation: FriendlyRefillPreparation) {
        if preparation.decision.candidateMaxGroups > 0 { eligible += 1 }
        if preparation.decision.selectedTarget > 0 { targets += 1 }
        if preparation.usesFriendlyTypes { plans += 1 }
    }

    mutating func recordPostRefill(_ matches: [MatchResult], preparation: FriendlyRefillPreparation) {
        guard preparation.usesFriendlyTypes else { return }
        let slots = Set(preparation.slots)
        if matches.contains(where: { $0.positions.isSubset(of: slots) }) { detected += 1 }
    }
}
#endif

#if DEBUG
struct FriendlyTargetDebugStatistics {
    var attempts = 0
    var plannedExact = 0
    var detectedExactOrMore = 0

    mutating func record(_ preparation: FriendlyRefillPreparation) {
        attempts += 1
        if preparation.usesFriendlyTypes && preparation.directGroupCount >= preparation.decision.selectedTarget {
            plannedExact += 1
        }
    }

    mutating func recordPostRefill(_ matches: [MatchResult], preparation: FriendlyRefillPreparation) {
        guard preparation.usesFriendlyTypes else { return }
        let direct = matches.filter { $0.positions.isSubset(of: Set(preparation.slots)) }.count
        if direct >= preparation.decision.selectedTarget { detectedExactOrMore += 1 }
    }
}
#endif
