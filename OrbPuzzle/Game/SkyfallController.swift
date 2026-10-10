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
    let friendlyMatchSize: Int
    let maxFriendlyCombo: Int
    let emptySlotCount: Int
    let physicalMaxGroups: Int
    let candidateMaxGroups: Int
    let rolls: [FriendlyRefillRoll]
    var selectedTarget: Int

    var friendlyHit: Bool { requestedTarget > 0 }
    var requestedTarget: Int { rolls.prefix(while: { $0.succeeded }).count }
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
    static func maximumCombos(for matchSize: Int) -> Int {
        guard (3...30).contains(matchSize) else { return 0 }
        return 30 / matchSize
    }

    static func probability(for comboIndex: Int) -> Double? {
        guard (1...10).contains(comboIndex) else { return nil }
        return Double(65 - 5 * ((comboIndex - 1) / 2)) / 100
    }

    static func selectTarget(
        previousResolvedGroupCount: Int,
        removedOrbCount: Int,
        friendlyMatchSize: Int,
        emptySlotCount: Int,
        roll: (Int) -> Double
    ) -> FriendlyRefillDecision {
        let maximum = maximumCombos(for: friendlyMatchSize)
        var attempts: [FriendlyRefillRoll] = []
        var requested = 0
        if maximum > 0 {
            for index in 1...maximum {
                guard let chance = probability(for: index) else { break }
                let value = roll(index)
                let succeeded = value < chance
                attempts.append(FriendlyRefillRoll(groupCount: index, probability: chance,
                                                  roll: value, succeeded: succeeded))
                guard succeeded else { break }
                requested += 1
            }
        }
        return FriendlyRefillDecision(
            previousResolvedGroupCount: previousResolvedGroupCount,
            removedOrbCount: removedOrbCount, friendlyMatchSize: friendlyMatchSize,
            maxFriendlyCombo: maximum, emptySlotCount: emptySlotCount,
            physicalMaxGroups: friendlyMatchSize > 0 ? max(0, emptySlotCount) / friendlyMatchSize : 0,
            candidateMaxGroups: maximum, rolls: attempts, selectedTarget: requested
        )
    }

}

struct FriendlyBoardCandidate: Equatable, Sendable {
    let positions: [GridPosition]
    let allowedColors: [OrbType]
}

struct FriendlyBoardAnalysis: Equatable, Sendable {
    let matchSize: Int
    let slots: [GridPosition]
    let columnEmptyCounts: [Int]
    let preservedTypes: [[OrbType?]]
    let runCoveredSlots: Set<GridPosition>
    let geometryCandidateCount: Int
    let candidates: [FriendlyBoardCandidate]
    let candidateSearchLimited: Bool

    // Upper bound only. It never promises disjoint packing or color feasibility.
    var directGroupUpperBound: Int { runCoveredSlots.count / max(1, matchSize) }
    var provesNoDirectGroup: Bool {
        directGroupUpperBound == 0 || (geometryCandidateCount == 0 && !candidateSearchLimited)
    }
}

/// Read-only analysis feeding SkyfallController's existing planner. This type
/// neither rolls probability nor refills or animates the live board.
enum FriendlyBoardAnalyzer {
    static func analyze(grid: OrbGrid, matchSize: Int,
                        stateLimit: Int = 8_000, candidateLimit: Int = 1_024) -> FriendlyBoardAnalysis {
        precondition(grid.rows == OrbGrid.defaultRows && grid.columns == OrbGrid.defaultColumns)
        precondition((3...30).contains(matchSize) && stateLimit > 0 && candidateLimit > 0)
        let slots = grid.emptyPositions()
        let geometry = groupGeometry(in: Set(slots), matchSize: matchSize,
                                     stateLimit: stateLimit, candidateLimit: candidateLimit)
        var candidates: [FriendlyBoardCandidate] = []
        for group in geometry.groups {
            let groupSet = Set(group)
            var colors: [OrbType] = []
            for color in OrbType.allCases {
                let types = (0..<grid.rows).map { row in
                    (0..<grid.columns).map { column in
                        let position = GridPosition(row: row, column: column)
                        return groupSet.contains(position) ? color : grid.orb(at: position)?.type ?? .fire
                    }
                }
                let partial = OrbGrid(types: types)
                _ = partial.remove(Set(slots).subtracting(groupSet))
                // Filling other holes cannot undo a preserved-orb extension or
                // split a normalized component. Reject those colors before DFS.
                if MatchDetector().detect(in: partial).contains(where: {
                    $0.type == color && $0.positions == groupSet && $0.matchSize == matchSize
                }) { colors.append(color) }
            }
            if !colors.isEmpty { candidates.append(FriendlyBoardCandidate(positions: group, allowedColors: colors)) }
        }
        return FriendlyBoardAnalysis(
            matchSize: matchSize, slots: slots,
            columnEmptyCounts: (0..<grid.columns).map { column in slots.filter { $0.column == column }.count },
            preservedTypes: grid.cells.map { $0.map { $0?.type } },
            runCoveredSlots: geometry.coverage, geometryCandidateCount: geometry.groups.count,
            candidates: candidates, candidateSearchLimited: geometry.limited
        )
    }

    private static func groupGeometry(in slots: Set<GridPosition>, matchSize: Int, stateLimit: Int, candidateLimit: Int) -> (groups: [[GridPosition]], limited: Bool, coverage: Set<GridPosition>) {
        func bit(_ position: GridPosition) -> UInt64 {
            UInt64(1) << (position.row * OrbGrid.defaultColumns + position.column)
        }
        func mask(_ positions: [GridPosition]) -> UInt64 {
            positions.reduce(UInt64(0)) { $0 | bit($1) }
        }
        func positions(_ value: UInt64) -> [GridPosition] {
            slots.filter { value & bit($0) != 0 }.sorted {
                ($0.row, $0.column) < ($1.row, $1.column)
            }
        }
        var runs = Set<UInt64>()
        for start in slots {
            for direction in [(row: 0, column: 1), (row: 1, column: 0)] {
                var line: [GridPosition] = []
                for offset in 0..<matchSize {
                    let next = GridPosition(row: start.row + offset * direction.row,
                                            column: start.column + offset * direction.column)
                    guard slots.contains(next) else { break }
                    line.append(next)
                    if line.count >= 3 { runs.insert(mask(line)) }
                }
            }
        }
        let orderedRuns = runs.sorted()
        var exact = Set(orderedRuns.filter { $0.nonzeroBitCount == matchSize })
        if slots.count == matchSize {
            let all = mask(Array(slots))
            let covered = orderedRuns.reduce(UInt64(0), |)
            // Final normalization still checks connectivity and preserved extensions.
            if covered == all { exact.insert(all) }
        }
        // Include compact bands up front so large sizes do not depend on traversing
        // thousands of smaller unions before reaching the requested cardinality.
        for startRow in 0..<OrbGrid.defaultRows {
            for startColumn in 0..<OrbGrid.defaultColumns {
                for width in 1...(OrbGrid.defaultColumns - startColumn) {
                    let height = (matchSize + width - 1) / width
                    guard startRow + height <= OrbGrid.defaultRows else { continue }
                    let group = (0..<matchSize).map {
                        GridPosition(row: startRow + $0 / width, column: startColumn + $0 % width)
                    }
                    guard Set(group).isSubset(of: slots) else { continue }
                    let value = mask(group)
                    let covered = orderedRuns.filter { $0 & value == $0 }.reduce(UInt64(0), |)
                    if covered == value { exact.insert(value) }
                }
            }
        }
        var seen = runs
        var queue = orderedRuns.filter { $0.nonzeroBitCount < matchSize }
        var cursor = 0
        var truncated = false
        while cursor < queue.count, seen.count < stateLimit, exact.count < candidateLimit {
            let current = queue[cursor]
            cursor += 1
            var neighbors: UInt64 = current
            for position in positions(current) {
                for neighbor in [GridPosition(row: position.row - 1, column: position.column),
                                 GridPosition(row: position.row + 1, column: position.column),
                                 GridPosition(row: position.row, column: position.column - 1),
                                 GridPosition(row: position.row, column: position.column + 1)] where slots.contains(neighbor) {
                    neighbors |= bit(neighbor)
                }
            }
            for run in orderedRuns where run & neighbors != 0 {
                let combined = current | run
                guard combined.nonzeroBitCount <= matchSize,
                      seen.insert(combined).inserted else { continue }
                if combined.nonzeroBitCount == matchSize { exact.insert(combined) }
                else { queue.append(combined) }
                if seen.count >= stateLimit || exact.count >= candidateLimit { truncated = true; break }
            }
        }
        let coverageMask = orderedRuns.reduce(UInt64(0), |)
        return (exact.sorted().map { positions($0) },
                truncated || cursor < queue.count, Set(positions(coverageMask)))
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
        friendlyMatchSize: Int,
        emptySlotCount: Int,
        roll: (Int) -> Double = { _ in Double.random(in: 0..<1) }
    ) -> FriendlyRefillDecision? {
        guard !hasControlledTarget else { return nil }
        return FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: previousResolvedGroupCount,
            removedOrbCount: removedOrbCount,
            friendlyMatchSize: friendlyMatchSize,
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
        targetGroupCount: Int,
        matchSize: Int = 3
    ) -> FriendlyRefillPlan? {
        var generator = SystemRandomNumberGenerator()
        return makeFriendlyNaturalRefill(
            grid: grid,
            refillSlots: refillSlots,
            targetGroupCount: targetGroupCount,
            matchSize: matchSize,
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
        matchSize: Int = 3,
        analysis: FriendlyBoardAnalysis? = nil,
        searchNodeLimit: Int = 20_000,
        using generator: inout R
    ) -> FriendlyRefillPlan? {
        lastFriendlyPlanningFailure = nil
        guard !hasControlledTarget,
              targetGroupCount > 0,
              refillSlots == grid.emptyPositions(),
              !refillSlots.isEmpty else { return nil }

        guard (3...30).contains(matchSize),
              targetGroupCount <= FriendlyNaturalSkyfallPolicy.maximumGroupCount else {
            lastFriendlyPlanningFailure = "planner-failure"
            return nil
        }
        guard targetGroupCount <= refillSlots.count / matchSize else {
            lastFriendlyPlanningFailure = "geometry-impossible"
            return nil
        }
        let maximumGroupCount = targetGroupCount
        guard maximumGroupCount > 0,
              let candidate = makeFriendlyMatchProducingRefill(
            grid: grid,
            refillSlots: refillSlots,
            maximumGroupCount: maximumGroupCount,
            matchSize: matchSize,
            analysis: analysis ?? FriendlyBoardAnalyzer.analyze(grid: grid, matchSize: matchSize),
            searchNodeLimit: searchNodeLimit,
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
        matchSize: Int,
        analysis: FriendlyBoardAnalysis,
        searchNodeLimit: Int,
        using generator: inout R
    ) -> (types: [OrbType], forcedTypes: [GridPosition: OrbType], strategy: String,
          groups: [[GridPosition]])? {
        let slots = Set(refillSlots)
        precondition(analysis.slots == refillSlots && analysis.matchSize == matchSize)
        precondition(analysis.preservedTypes == grid.cells.map { $0.map { $0?.type } })
        let boardCandidates = analysis.candidates.shuffled(using: &generator)
        let candidates = boardCandidates.map { $0.positions }
        let allowedColors = Dictionary(uniqueKeysWithValues: boardCandidates.map {
            (Set($0.positions), $0.allowedColors)
        })
        guard !analysis.provesNoDirectGroup else {
            lastFriendlyPlanningFailure = "geometry-impossible"
            return nil
        }
        guard maximumGroupCount <= analysis.directGroupUpperBound else {
            lastFriendlyPlanningFailure = "geometry-impossible"
            return nil
        }
        // Bounded backtracking keeps the chosen target fixed. Packing failure,
        // color merges or natural extensions try another assignment, never N-1.
        var visited = 0
        var fullBoardChecks = 0
        let nodeLimit = max(1, searchNodeLimit)
        let validationLimit = 2_048

        // Capture the complete assignment returned by color recursion, not just
        // its outermost first-group prefix.
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
                guard matches.filter({ $0.positions.isSubset(of: slots) && $0.matchSize == matchSize }).count >= maximumGroupCount
                else { return nil }
                acceptedForced = forced
                return types
            }
            let palette = (allowedColors[Set(groups[index])] ?? []).shuffled(using: &generator).sorted { lhs, rhs in
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
                  slots.subtracting(occupied).count >= needed * matchSize else { return nil }
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
#if DEBUG
            print("[FRIENDLY_SEARCH] target=\(maximumGroupCount) nodes=\(visited)/\(nodeLimit) validations=\(fullBoardChecks)/\(validationLimit) candidateSearchLimited=\(analysis.candidateSearchLimited)")
#endif
            lastFriendlyPlanningFailure = visited >= nodeLimit || fullBoardChecks >= validationLimit
                || analysis.candidateSearchLimited ? "search-limit" : "planner-failure"
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

    var failureCategory: String? {
        guard !usesFriendlyTypes, let fallbackReason else { return nil }
        if fallbackReason.hasPrefix("roll-miss") { return "probability-miss" }
        if fallbackReason.hasPrefix("search-limit") { return "search-limit" }
        if fallbackReason.hasPrefix("geometry-impossible") { return "geometry-impossible" }
        return "planner-failure"
    }

    func refill(in grid: OrbGrid) -> [OrbSpawn] {
        precondition(slots == grid.emptyPositions())
        precondition(types.count == slots.count)
        return grid.refill(types: types, at: slots)
    }

#if DEBUG
    func logDebug(resolveID: UInt) {
        for attempt in decision.rolls {
            print("[FRIENDLY_ROLL] resolveID=\(resolveID) previousResolvedGroupCount=\(decision.previousResolvedGroupCount) emptySlotCount=\(decision.emptySlotCount) physicalMaxGroups=\(decision.physicalMaxGroups) removedOrbCount=\(decision.removedOrbCount) matchSize=\(decision.friendlyMatchSize) maxFriendlyCombo=\(decision.maxFriendlyCombo) probability=\(attempt.probability) roll=\(attempt.roll) comboIndex=\(attempt.groupCount) selectedTarget=\(decision.selectedTarget)")
        }
        if decision.rolls.isEmpty {
            print("[FRIENDLY_ROLL] resolveID=\(resolveID) previousResolvedGroupCount=\(decision.previousResolvedGroupCount) emptySlotCount=\(decision.emptySlotCount) physicalMaxGroups=\(decision.physicalMaxGroups) removedOrbCount=\(decision.removedOrbCount) matchSize=\(decision.friendlyMatchSize) maxFriendlyCombo=\(decision.maxFriendlyCombo) probability=none roll=none selectedTarget=\(decision.selectedTarget)")
        }
        let forced = plan?.forcedTypes ?? [:]
        let positions = forced.keys.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        let rawGroups = plan?.forcedGroups.map { FriendlyRefillPipeline.describe($0) } ?? []
        let forcedTypes = positions.map { forced[$0]?.rawValue ?? "missing" }
        print("[FRIENDLY_PLAN] resolveID=\(resolveID) requestedTarget=\(decision.requestedTarget) hit=\(decision.friendlyHit) selectedTarget=\(decision.selectedTarget) plannedTarget=\(plan?.plannedTarget.description ?? "none") removedOrbs=\(removedOrbCount) rawForcedGroups=\(rawGroups) refillSlots=\(FriendlyRefillPipeline.describe(slots)) planCalled=\(planCalled) planReturned=\(plan != nil) plannedTypeCount=\(plan?.types.count ?? 0) forcedPositions=\(FriendlyRefillPipeline.describe(positions)) forcedTypes=\(forcedTypes) strategy=\(plan?.strategy ?? "none") forcedTraceAvailable=\(plan != nil && plan?.strategy != "multi-group-search") validationDetectedGroups=\(validationDetectedGroups?.description ?? "none") directGroups=\(directGroupCount) fallbackUsed=\(!usesFriendlyTypes) fallbackReason=\(fallbackReason ?? "none") planUsed=\(usesFriendlyTypes) refillMode=\(refillMode)")
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
        guard var decision = controller.selectFriendlyRefillTarget(
            previousResolvedGroupCount: previousResolution.comboCount,
            removedOrbCount: previousResolution.removedOrbCount,
            friendlyMatchSize: previousResolution.matches.map { $0.matchSize }.max() ?? 0,
            emptySlotCount: slots.count,
            roll: roll
        ) else { preconditionFailure("Friendly preparation called in ON mode") }
        let requested = decision.requestedTarget
        let called = requested > 0
        let analysis = called ? FriendlyBoardAnalyzer.analyze(grid: grid, matchSize: decision.friendlyMatchSize) : nil
        var failureReasons: [String] = []
        decision.selectedTarget = 0
        var plan: FriendlyRefillPlan?
        var detected: Int?
        var direct = 0
        var reason: String?
#if DEBUG
        print("[FRIENDLY] removed=\(decision.removedOrbCount) matchSize=\(decision.friendlyMatchSize) maxFriendlyCombo=\(decision.maxFriendlyCombo) roll=\(decision.rolls.first?.roll.description ?? "none") hit=\(decision.friendlyHit) requested=\(requested)")
#endif
#if DEBUG
        if let analysis {
            let boardTypes = analysis.preservedTypes.map { row in row.map { $0?.rawValue ?? "_" } }
            print("[FRIENDLY_BOARD] matchSize=\(analysis.matchSize) slots=\(analysis.slots.count) columnEmptyCounts=\(analysis.columnEmptyCounts) coveredSlots=\(analysis.runCoveredSlots.count) upperBound=\(analysis.directGroupUpperBound) geometryCandidates=\(analysis.geometryCandidateCount) colorValidCandidates=\(analysis.candidates.count) candidateSearchLimited=\(analysis.candidateSearchLimited) boardTypes=\(boardTypes)")
        }
#endif
        // The wave's stop-on-miss probability chain is complete. These attempts only
        // search assignments; each candidate must meet its own direct target.
        if called {
            for target in stride(from: requested, through: 1, by: -1) {
                if let planProvider {
                    plan = planProvider(grid, slots, target)
                } else {
                    plan = controller.makeFriendlyNaturalRefill(
                        grid: grid, refillSlots: slots, targetGroupCount: target,
                        matchSize: decision.friendlyMatchSize,
                        analysis: analysis,
                        using: &generator
                    )
                }
                reason = nil
                detected = nil
                direct = 0
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
                        direct = matches.filter {
                            $0.positions.isSubset(of: slotSet) && $0.matchSize == decision.friendlyMatchSize
                        }.count
                        if detected == 0 { reason = "full-grid-validation-zero-groups" }
                        else if direct < target { reason = "direct-groups-below-selected-target" }
                    }
                    if reason == nil {
                        decision.selectedTarget = target
#if DEBUG
                        print("[FRIENDLY_TRY] target=\(target) result=success planned=\(plan.plannedTarget) detected=\(detected ?? 0) direct=\(direct)")
                        print("[FRIENDLY_RESULT] requested=\(requested) selected=\(target) fallback=false")
#endif
                        return FriendlyRefillPreparation(
                            slots: slots, removedOrbCount: previousResolution.removedOrbCount, decision: decision, planCalled: called, plan: plan,
                            types: plan.types, validationDetectedGroups: detected, directGroupCount: direct,
                            usesFriendlyTypes: true, fallbackReason: nil
                        )
                    }
                }
                failureReasons.append(reason ?? controller.lastFriendlyPlanningFailure ?? "planner-failure")
#if DEBUG
                print("[FRIENDLY_TRY] target=\(target) result=fail reason=\(reason ?? controller.lastFriendlyPlanningFailure ?? "no-feasible-assignment")")
#endif
            }
            if failureReasons.contains("search-limit") {
                reason = "search-limit"
            } else if analysis?.provesNoDirectGroup == true {
                reason = "geometry-impossible"
            } else {
                reason = "planner-failure"
            }
        } else {
            reason = decision.maxFriendlyCombo == 0 ? "insufficient-candidate-groups" : "roll-miss"
        }
#if DEBUG
        print("[FRIENDLY_RESULT] requested=\(requested) selected=0 fallback=true reason=\(reason ?? "unknown")")
#endif
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
        if matches.contains(where: { $0.positions.isSubset(of: slots) && $0.matchSize == preparation.decision.friendlyMatchSize }) { detected += 1 }
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
        let direct = matches.filter { $0.positions.isSubset(of: Set(preparation.slots)) && $0.matchSize == preparation.decision.friendlyMatchSize }.count
        if direct >= preparation.decision.selectedTarget { detectedExactOrMore += 1 }
    }
}
#endif
