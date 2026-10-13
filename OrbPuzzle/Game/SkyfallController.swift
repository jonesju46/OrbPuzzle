import Foundation

struct FriendlyRefillRoll: Equatable, Sendable {
    let groupCount: Int
    let probability: Double
    let roll: Double
    let succeeded: Bool
}

struct FriendlyPlannerTiming: Equatable, Sendable {
    var analyzerMs = 0.0
    var candidateMs = 0.0
    var searchMs = 0.0
    var validationMs = 0.0

    static let zero = FriendlyPlannerTiming()
}

/// Immutable description of one normalized group from the just-completed
/// resolve wave. Offsets are translation-normalized only: rotation, mirroring,
/// color changes and size changes are intentionally not canonicalized.
struct FriendlyGroupTemplate: Equatable, Hashable, Sendable {
    let sourceIndex: Int
    let orbType: OrbType
    let originalPositions: Set<GridPosition>
    let normalizedOffsets: [GridPosition]

    var matchSize: Int { normalizedOffsets.count }

    init(sourceIndex: Int, orbType: OrbType, positions: Set<GridPosition>) {
        precondition(!positions.isEmpty)
        self.sourceIndex = sourceIndex
        self.orbType = orbType
        originalPositions = positions
        let minimumRow = positions.map(\.row).min()!
        let minimumColumn = positions.map(\.column).min()!
        normalizedOffsets = positions.map {
            GridPosition(row: $0.row - minimumRow, column: $0.column - minimumColumn)
        }.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    init(sourceIndex: Int, match: MatchResult) {
        self.init(sourceIndex: sourceIndex, orbType: match.type, positions: match.positions)
    }

    func matches(_ match: MatchResult) -> Bool {
        guard match.type == orbType, match.matchSize == matchSize else { return false }
        return FriendlyGroupTemplate(sourceIndex: sourceIndex, orbType: match.type,
                                     positions: match.positions).normalizedOffsets == normalizedOffsets
    }
}

struct FriendlyTemplatePlacement: Equatable, Sendable {
    let template: FriendlyGroupTemplate
    let positions: [GridPosition]

    func matches(_ match: MatchResult) -> Bool {
        match.type == template.orbType && match.positions == Set(positions)
            && template.matches(match)
    }
}

enum FriendlyRefillPolicyMode: String, Equatable, Sendable {
    case threeOrbStepped = "ThreeOrbStepped"
    case multiSizeStepped = "MultiSizeStepped"
}

struct FriendlySizeBucketDecision: Equatable, Sendable {
    let matchSize: Int
    let startingCombo: Int
    let probability: Double
    let rolls: [FriendlyRefillRoll]
    let selectedTarget: Int

    var attemptedTargets: [Int] { rolls.map(\.groupCount) }
    var requestedSizes: [Int] { Array(repeating: matchSize, count: selectedTarget) }
}

struct FriendlyRefillDecision: Equatable, Sendable {
    let previousSizes: [Int]
    let removedOrbCount: Int
    let emptySlotCount: Int
    let mode: FriendlyRefillPolicyMode
    let bucketDecisions: [FriendlySizeBucketDecision]
    var selectedTarget: Int
    var previousResolvedGroupCount: Int { previousSizes.count }
    var candidateMaxGroups: Int { previousSizes.count }
    var rolls: [FriendlyRefillRoll] { bucketDecisions.flatMap(\.rolls) }
    var probabilityTarget: Int { bucketDecisions.reduce(0) { $0 + $1.selectedTarget } }
    var friendlyHit: Bool { probabilityTarget > 0 }
    var requestedSizes: [Int] { bucketDecisions.flatMap(\.requestedSizes) }
    var requestedTarget: Int { requestedSizes.count }
}

struct FriendlyRefillPlan: Equatable, Sendable {
    let types: [OrbType]
    let plannedTarget: Int
    let forcedTypes: [GridPosition: OrbType]
    let strategy: String
    let forcedGroups: [[GridPosition]]
    let templatePlacements: [FriendlyTemplatePlacement]

    init(types: [OrbType], plannedTarget: Int,
         forcedTypes: [GridPosition: OrbType] = [:], strategy: String = "preserved-match",
         forcedGroups: [[GridPosition]] = [],
         templatePlacements: [FriendlyTemplatePlacement] = []) {
        self.types = types
        self.plannedTarget = plannedTarget
        self.forcedTypes = forcedTypes
        self.strategy = strategy
        self.forcedGroups = forcedGroups
        self.templatePlacements = templatePlacements
    }
}

enum ThreeOrbSteppedFriendlyPolicy {
    static let supportedCombos = 1...10

    static func probability(startingCombo: Int) -> Double {
        FriendlySizeSteppedPolicy.probability(matchSize: 3, sizeCombo: startingCombo) ?? 0
    }

    static func selectTarget(startingCombo: Int,
                             roll: (Int) -> Double) -> (rolls: [FriendlyRefillRoll], target: Int) {
        guard let decision = FriendlySizeSteppedPolicy.selectBucket(
            matchSize: 3, startingCombo: startingCombo, roll: roll) else { return ([], 0) }
        return (decision.rolls, decision.selectedTarget)
    }
}

enum FriendlySizeSteppedPolicy {
    static func maximumSizeCombo(matchSize: Int) -> Int {
        guard (3...30).contains(matchSize) else { return 0 }
        return 30 / matchSize
    }

    static func probability(matchSize: Int, sizeCombo: Int) -> Double? {
        let maximum = maximumSizeCombo(matchSize: matchSize)
        guard maximum > 0, sizeCombo >= 1, sizeCombo <= maximum else { return nil }
        switch matchSize {
        case 3:
            switch sizeCombo {
            case 1: return 0.50
            case 2...4: return 0.55
            case 5...7: return 0.65
            case 8...10: return 0.75
            default: return nil
            }
        case 4:
            switch sizeCombo {
            case 1: return 0.50
            case 2...4: return 0.65
            case 5...7: return 0.75
            default: return nil
            }
        case 5:
            switch sizeCombo {
            case 1: return 0.50
            case 2...3: return 0.65
            case 4...6: return 0.75
            default: return nil
            }
        case 6:
            switch sizeCombo {
            case 1: return 0.50
            case 2...3: return 0.65
            case 4...5: return 0.75
            default: return nil
            }
        case 7:
            switch sizeCombo {
            case 1: return 0.50
            case 2...3: return 0.65
            case 4: return 0.75
            default: return nil
            }
        case 8...9:
            switch sizeCombo {
            case 1: return 0.50
            case 2: return 0.65
            case 3: return 0.75
            default: return nil
            }
        case 10...15:
            return sizeCombo == 1 ? 0.65 : 0.75
        case 16...30:
            return 0.75
        default:
            return nil
        }
    }

    static func buckets(for previousSizes: [Int]) -> [(matchSize: Int, sizeCombo: Int)] {
        Dictionary(grouping: previousSizes, by: { $0 }).map {
            (matchSize: $0.key, sizeCombo: $0.value.count)
        }.sorted { $0.matchSize < $1.matchSize }
    }

    static func selectBucket(matchSize: Int, startingCombo: Int,
                             roll: (Int) -> Double) -> FriendlySizeBucketDecision? {
        guard let waveProbability = probability(matchSize: matchSize, sizeCombo: startingCombo) else {
            return nil
        }
        var results: [FriendlyRefillRoll] = []
        for candidate in stride(from: startingCombo, through: 1, by: -1) {
            let value = roll(candidate)
            let succeeded = value < waveProbability
            results.append(FriendlyRefillRoll(groupCount: candidate, probability: waveProbability,
                                              roll: value, succeeded: succeeded))
            if succeeded {
                return FriendlySizeBucketDecision(matchSize: matchSize, startingCombo: startingCombo,
                    probability: waveProbability, rolls: results, selectedTarget: candidate)
            }
        }
        return FriendlySizeBucketDecision(matchSize: matchSize, startingCombo: startingCombo,
            probability: waveProbability, rolls: results, selectedTarget: 0)
    }
}

enum FriendlyNaturalSkyfallPolicy {
    static let maximumGroupCount = 10

    static func mode(for previousSizes: [Int]) -> FriendlyRefillPolicyMode {
        if previousSizes.count >= 1 && previousSizes.count <= maximumGroupCount
            && previousSizes.allSatisfy({ $0 == 3 }) {
            return .threeOrbStepped
        }
        return .multiSizeStepped
    }

    static func threeOrbFriendlyProbability(startingCombo: Int) -> Double {
        ThreeOrbSteppedFriendlyPolicy.probability(startingCombo: startingCombo)
    }

    static func selectTarget(previousSizes: [Int], removedOrbCount: Int,
                             emptySlotCount: Int, roll: (Int) -> Double) -> FriendlyRefillDecision {
        precondition(previousSizes.allSatisfy { (3...30).contains($0) })
        precondition(previousSizes.count <= maximumGroupCount && previousSizes.reduce(0, +) <= 30)
        let policyMode = mode(for: previousSizes)
        let bucketDecisions = FriendlySizeSteppedPolicy.buckets(for: previousSizes).map { bucket in
            guard let decision = FriendlySizeSteppedPolicy.selectBucket(
                matchSize: bucket.matchSize, startingCombo: bucket.sizeCombo, roll: roll) else {
                preconditionFailure("Invalid Friendly bucket size=\(bucket.matchSize) combo=\(bucket.sizeCombo)")
            }
            return decision
        }
        return FriendlyRefillDecision(previousSizes: previousSizes, removedOrbCount: removedOrbCount,
            emptySlotCount: emptySlotCount, mode: policyMode,
            bucketDecisions: bucketDecisions, selectedTarget: 0)
    }

    // Unique multisets: maximize groups, preserve three-orb groups, then
    // compare the remaining size counts before total requested orbs.
    static func subsets(of sizes: [Int]) -> [[Int]] {
        var unique = Set<[Int]>()
        for mask in 1..<(1 << sizes.count) {
            unique.insert(sizes.indices.filter { mask & (1 << $0) != 0 }.map { sizes[$0] }.sorted(by: >))
        }
        return unique.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            let leftThree = $0.filter { $0 == 3 }.count
            let rightThree = $1.filter { $0 == 3 }.count
            if leftThree != rightThree { return leftThree > rightThree }
            for size in 4...30 {
                let leftCount = $0.filter { $0 == size }.count
                let rightCount = $1.filter { $0 == size }.count
                if leftCount != rightCount { return leftCount > rightCount }
            }
            let left = $0.reduce(0, +), right = $1.reduce(0, +)
            if left != right { return left > right }
            return $1.lexicographicallyPrecedes($0)
        }
    }

    /// Enumerates concrete source-template subsets allowed by the per-size
    /// probability decisions. Ranking preserves V3 fallback priority while
    /// still trying alternate same-size source templates instead of blindly
    /// taking the first N groups returned by MatchDetector.
    static func templateSubsets(
        from templates: [FriendlyGroupTemplate],
        bucketDecisions: [FriendlySizeBucketDecision]
    ) -> [[FriendlyGroupTemplate]] {
        let targetBySize = Dictionary(uniqueKeysWithValues: bucketDecisions.map {
            ($0.matchSize, $0.selectedTarget)
        })
        let ordered = templates.sorted(by: templateOrder)
        guard !ordered.isEmpty, ordered.count <= maximumGroupCount else { return [] }
        var result: [[FriendlyGroupTemplate]] = []
        for mask in 1..<(1 << ordered.count) {
            let subset = ordered.indices.compactMap { index in
                mask & (1 << index) == 0 ? nil : ordered[index]
            }
            let counts = Dictionary(grouping: subset, by: \.matchSize).mapValues { $0.count }
            guard counts.allSatisfy({ $0.value <= targetBySize[$0.key, default: 0] }) else { continue }
            result.append(subset.sorted(by: templateOrder))
        }
        return result.sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            let leftThree = left.filter { $0.matchSize == 3 }.count
            let rightThree = right.filter { $0.matchSize == 3 }.count
            if leftThree != rightThree { return leftThree > rightThree }
            for size in 4...30 {
                let leftCount = left.filter { $0.matchSize == size }.count
                let rightCount = right.filter { $0.matchSize == size }.count
                if leftCount != rightCount { return leftCount > rightCount }
            }
            let leftOrbs = left.reduce(0) { $0 + $1.matchSize }
            let rightOrbs = right.reduce(0) { $0 + $1.matchSize }
            if leftOrbs != rightOrbs { return leftOrbs > rightOrbs }
            return templateSequence(left).lexicographicallyPrecedes(templateSequence(right))
        }
    }

    private static func templateOrder(_ left: FriendlyGroupTemplate,
                                      _ right: FriendlyGroupTemplate) -> Bool {
        if left.matchSize != right.matchSize { return left.matchSize < right.matchSize }
        let leftType = OrbType.resolveOrder.firstIndex(of: left.orbType) ?? .max
        let rightType = OrbType.resolveOrder.firstIndex(of: right.orbType) ?? .max
        if leftType != rightType { return leftType < rightType }
        let leftOffsets = left.normalizedOffsets.flatMap { [$0.row, $0.column] }
        let rightOffsets = right.normalizedOffsets.flatMap { [$0.row, $0.column] }
        if leftOffsets != rightOffsets { return leftOffsets.lexicographicallyPrecedes(rightOffsets) }
        return left.sourceIndex < right.sourceIndex
    }

    private static func templateSequence(_ templates: [FriendlyGroupTemplate]) -> [Int] {
        templates.flatMap { template in
            [template.matchSize,
             OrbType.resolveOrder.firstIndex(of: template.orbType) ?? .max]
                + template.normalizedOffsets.flatMap { [$0.row, $0.column] }
                + [template.sourceIndex]
        }
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
    static func placements(
        for template: FriendlyGroupTemplate,
        in grid: OrbGrid,
        refillSlots: [GridPosition]
    ) -> [FriendlyTemplatePlacement] {
        guard refillSlots == grid.emptyPositions(), !template.normalizedOffsets.isEmpty else { return [] }
        let slotSet = Set(refillSlots)
        let maximumRow = template.normalizedOffsets.map(\.row).max()!
        let maximumColumn = template.normalizedOffsets.map(\.column).max()!
        guard maximumRow < grid.rows, maximumColumn < grid.columns else { return [] }
        var placements: [FriendlyTemplatePlacement] = []
        for originRow in 0..<(grid.rows - maximumRow) {
            for originColumn in 0..<(grid.columns - maximumColumn) {
                let positions = template.normalizedOffsets.map {
                    GridPosition(row: originRow + $0.row, column: originColumn + $0.column)
                }
                let positionSet = Set(positions)
                guard positionSet.count == template.matchSize,
                      positionSet.isSubset(of: slotSet) else { continue }
                let types = (0..<grid.rows).map { row in
                    (0..<grid.columns).map { column in
                        let position = GridPosition(row: row, column: column)
                        return positionSet.contains(position)
                            ? template.orbType : grid.orb(at: position)?.type ?? .fire
                    }
                }
                let partial = OrbGrid(types: types)
                _ = partial.remove(slotSet.subtracting(positionSet))
                guard MatchDetector().detect(in: partial).contains(where: {
                    $0.type == template.orbType && $0.positions == positionSet
                        && template.matches($0)
                }) else { continue }
                placements.append(FriendlyTemplatePlacement(template: template, positions: positions))
            }
        }
        return placements.sorted {
            let left = $0.positions.flatMap { [$0.row, $0.column] }
            let right = $1.positions.flatMap { [$0.row, $0.column] }
            return left.lexicographicallyPrecedes(right)
        }
    }

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

    func selectFriendlyRefillTarget(previousSizes: [Int], removedOrbCount: Int,
                                    emptySlotCount: Int,
                                    roll: (Int) -> Double = { _ in Double.random(in: 0..<1) }) -> FriendlyRefillDecision? {
        guard !hasControlledTarget else { return nil }
        return FriendlyNaturalSkyfallPolicy.selectTarget(previousSizes: previousSizes,
            removedOrbCount: removedOrbCount, emptySlotCount: emptySlotCount, roll: roll)
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
        grid: OrbGrid, refillSlots: [GridPosition], targetGroupCount: Int, matchSize: Int = 3,
        analysis: FriendlyBoardAnalysis? = nil, searchNodeLimit: Int = 20_000,
        using generator: inout R
    ) -> FriendlyRefillPlan? {
        let analyses = analysis.map { [matchSize: $0] }
        return makeFriendlyNaturalRefill(grid: grid, refillSlots: refillSlots,
            requestedSizes: Array(repeating: matchSize, count: max(0, targetGroupCount)),
            analyses: analyses, searchNodeLimit: searchNodeLimit, using: &generator)
    }

    private(set) var lastFriendlySearchNodes = 0
    private(set) var lastFriendlySubsetAttempts = 0
    private(set) var lastFriendlySearchLimited = false
    private(set) var lastFriendlyCandidateMs = 0.0
    private(set) var lastFriendlySearchMs = 0.0
    private(set) var lastFriendlyValidationMs = 0.0

    /// V4 planner entry point. All size buckets have already consumed their
    /// independent probability rolls; this single call searches the merged
    /// concrete-template requests and their ranked partial fallbacks under one
    /// shared wave budget.
    func makeFriendlyNaturalRefill<R: RandomNumberGenerator>(
        grid: OrbGrid, refillSlots: [GridPosition],
        templateAttempts: [[FriendlyGroupTemplate]],
        searchNodeLimit: Int = 20_000, subsetAttemptLimit: Int = 256,
        waveNodeLimit: Int = 100_000, using generator: inout R
    ) -> FriendlyRefillPlan? {
        lastFriendlyPlanningFailure = nil
        lastFriendlySearchNodes = 0
        lastFriendlySubsetAttempts = 0
        lastFriendlySearchLimited = false
        lastFriendlyCandidateMs = 0
        lastFriendlySearchMs = 0
        lastFriendlyValidationMs = 0
        guard !hasControlledTarget, refillSlots == grid.emptyPositions(),
              !templateAttempts.isEmpty else {
            lastFriendlyPlanningFailure = "assignment-failure"
            return nil
        }

        let allTemplates = templateAttempts.flatMap { $0 }.reduce(into: [Int: FriendlyGroupTemplate]()) {
            $0[$1.sourceIndex] = $1
        }.values
        let candidateStart = ProcessInfo.processInfo.systemUptime
        let placementCache = Dictionary(uniqueKeysWithValues: allTemplates.map { template in
            (template.sourceIndex, FriendlyBoardAnalyzer.placements(
                for: template, in: grid, refillSlots: refillSlots))
        })
        lastFriendlyCandidateMs = (ProcessInfo.processInfo.systemUptime - candidateStart) * 1_000
        var failures: [String] = []
        let attemptLimit = max(1, subsetAttemptLimit)
        let waveLimit = max(1, waveNodeLimit)

        for templates in templateAttempts {
            guard lastFriendlySubsetAttempts < attemptLimit,
                  lastFriendlySearchNodes < waveLimit else {
                lastFriendlySearchLimited = true
                break
            }
            lastFriendlySubsetAttempts += 1
            guard templates.reduce(0, { $0 + $1.matchSize }) <= refillSlots.count else {
                failures.append("geometry-impossible")
                continue
            }
            let ordered = templates.sorted {
                let leftCount = placementCache[$0.sourceIndex]?.count ?? 0
                let rightCount = placementCache[$1.sourceIndex]?.count ?? 0
                if leftCount != rightCount { return leftCount < rightCount }
                return $0.sourceIndex < $1.sourceIndex
            }
            guard ordered.allSatisfy({ !(placementCache[$0.sourceIndex]?.isEmpty ?? true) }) else {
                failures.append("geometry-impossible")
                continue
            }

            let perSearchLimit = min(max(1, searchNodeLimit), waveLimit - lastFriendlySearchNodes)
            var visited = 0
            var validations = 0
            var validationSeconds = 0.0
            let validationLimit = 2_048
            var acceptedTypes: [OrbType]?
            var acceptedPlacements: [FriendlyTemplatePlacement] = []

            func search(index: Int, occupied: Set<GridPosition>,
                        forced: [GridPosition: OrbType],
                        placements: [FriendlyTemplatePlacement],
                        using generator: inout R) {
                guard acceptedTypes == nil else { return }
                visited += 1
                guard visited <= perSearchLimit, validations < validationLimit else { return }
                if index == ordered.count {
                    validations += 1
                    let validationStart = ProcessInfo.processInfo.systemUptime
                    defer {
                        validationSeconds += ProcessInfo.processInfo.systemUptime - validationStart
                    }
                    guard let types = planTypes(grid: grid, refillSlots: refillSlots,
                                                forcedTypes: forced, using: &generator) else { return }
                    let matches = MatchDetector().detect(in: simulatedGrid(
                        grid: grid, slots: refillSlots, types: types))
                    guard placements.allSatisfy({ placement in
                        matches.contains(where: { placement.matches($0) })
                    }) else { return }
                    acceptedTypes = types
                    acceptedPlacements = placements
                    return
                }
                let template = ordered[index]
                for placement in placementCache[template.sourceIndex] ?? [] {
                    let positions = Set(placement.positions)
                    guard positions.isDisjoint(with: occupied) else { continue }
                    var nextForced = forced
                    for position in placement.positions { nextForced[position] = template.orbType }
                    search(index: index + 1, occupied: occupied.union(positions),
                           forced: nextForced, placements: placements + [placement],
                           using: &generator)
                    if acceptedTypes != nil || visited >= perSearchLimit
                        || validations >= validationLimit { break }
                }
            }

            let searchStart = ProcessInfo.processInfo.systemUptime
            search(index: 0, occupied: [], forced: [:], placements: [], using: &generator)
            let elapsed = ProcessInfo.processInfo.systemUptime - searchStart
            lastFriendlyValidationMs += validationSeconds * 1_000
            lastFriendlySearchMs += max(0, elapsed - validationSeconds) * 1_000
            lastFriendlySearchNodes += visited
            let limited = visited >= perSearchLimit || validations >= validationLimit
            lastFriendlySearchLimited = lastFriendlySearchLimited || limited
#if DEBUG
            print("[FRIENDLY_V4_SEARCH] templateIDs=\(templates.map(\.sourceIndex)) nodes=\(visited)/\(perSearchLimit) validations=\(validations)/\(validationLimit) limited=\(limited)")
#endif
            if let types = acceptedTypes {
                let forced = Dictionary(uniqueKeysWithValues: acceptedPlacements.flatMap { placement in
                    placement.positions.map { ($0, placement.template.orbType) }
                })
                return FriendlyRefillPlan(types: types, plannedTarget: acceptedPlacements.count,
                    forcedTypes: forced, strategy: "template-backtracking-v4",
                    forcedGroups: acceptedPlacements.map(\.positions),
                    templatePlacements: acceptedPlacements)
            }
            failures.append(limited ? "search-limit" : "assignment-failure")
        }

        if lastFriendlySearchLimited || failures.contains("search-limit") {
            lastFriendlyPlanningFailure = "search-limit"
        } else if !failures.isEmpty && failures.allSatisfy({ $0 == "geometry-impossible" }) {
            lastFriendlyPlanningFailure = "geometry-impossible"
        } else {
            lastFriendlyPlanningFailure = "assignment-failure"
        }
        return nil
    }

    func makeFriendlyNaturalRefill<R: RandomNumberGenerator>(
        grid: OrbGrid, refillSlots: [GridPosition], requestedSizes: [Int],
        analyses supplied: [Int: FriendlyBoardAnalysis]? = nil,
        searchNodeLimit: Int = 20_000, using generator: inout R
    ) -> FriendlyRefillPlan? {
        lastFriendlyPlanningFailure = nil
        lastFriendlySearchNodes = 0
        lastFriendlySubsetAttempts = 0
        lastFriendlySearchLimited = false
        lastFriendlyCandidateMs = 0
        lastFriendlySearchMs = 0
        lastFriendlyValidationMs = 0
        guard !hasControlledTarget, refillSlots == grid.emptyPositions(), !requestedSizes.isEmpty,
              requestedSizes.count <= 10, requestedSizes.allSatisfy({ (3...30).contains($0) }) else {
            lastFriendlyPlanningFailure = "assignment-failure"; return nil
        }
        let sizes = requestedSizes.sorted(by: >)
        let analyses = supplied ?? Dictionary(uniqueKeysWithValues: Set(sizes).map {
            ($0, FriendlyBoardAnalyzer.analyze(grid: grid, matchSize: $0))
        })
        guard sizes.reduce(0, +) <= refillSlots.count else {
            lastFriendlyPlanningFailure = "geometry-impossible"; return nil
        }
        for size in Set(sizes) {
            guard let analysis = analyses[size] else { preconditionFailure("Missing size analysis") }
            precondition(analysis.slots == refillSlots && analysis.matchSize == size)
            precondition(analysis.preservedTypes == grid.cells.map { $0.map { $0?.type } })
            if analysis.provesNoDirectGroup {
                lastFriendlyPlanningFailure = "geometry-impossible"; return nil
            }
        }
        var candidates: [Int: [FriendlyBoardCandidate]] = [:]
        for size in Set(sizes).sorted() {
            candidates[size] = analyses[size]!.candidates.shuffled(using: &generator)
        }
        let nodeLimit = max(1, searchNodeLimit)
        let validationLimit = 2_048
        var visited = 0, checks = 0
        var acceptedForced: [GridPosition: OrbType] = [:]
        var packingFound = false
        func assignColors(_ groups: [FriendlyBoardCandidate], index: Int,
                          forced: [GridPosition: OrbType], using generator: inout R) -> [OrbType]? {
            visited += 1
            guard visited <= nodeLimit, checks < validationLimit else { return nil }
            if index == groups.count {
                checks += 1
                guard let types = planTypes(grid: grid, refillSlots: refillSlots,
                                            forcedTypes: forced, using: &generator) else { return nil }
                let matches = MatchDetector().detect(in: simulatedGrid(grid: grid, slots: refillSlots, types: types))
                guard groups.allSatisfy({ group in
                    matches.contains { $0.positions == Set(group.positions)
                        && $0.matchSize == group.positions.count && $0.type == forced[group.positions[0]] }
                }) else { return nil }
                acceptedForced = forced
                return types
            }
            let group = groups[index]
            let palette = group.allowedColors.shuffled(using: &generator).sorted { lhs, rhs in
                forced.values.filter { $0 == lhs }.count < forced.values.filter { $0 == rhs }.count
            }
            for type in palette {
                if visited >= nodeLimit || checks >= validationLimit { break }
                guard adjacentConflictCount(type: type, group: group.positions, assignments: forced) == 0 else { continue }
                var next = forced
                for position in group.positions { next[position] = type }
                if let types = assignColors(groups, index: index + 1, forced: next, using: &generator) { return types }
            }
            return nil
        }
        func place(_ groups: [FriendlyBoardCandidate], occupied: Set<GridPosition>,
                   previousIndex: Int, using generator: inout R) -> (types: [OrbType], groups: [FriendlyBoardCandidate])? {
            visited += 1
            guard visited <= nodeLimit, checks < validationLimit else { return nil }
            if groups.count == sizes.count {
                packingFound = true
                guard let types = assignColors(groups, index: 0, forced: [:], using: &generator) else { return nil }
                return (types, groups)
            }
            let depth = groups.count
            guard refillSlots.count - occupied.count >= sizes.dropFirst(depth).reduce(0, +) else { return nil }
            let choices = candidates[sizes[depth]] ?? []
            let start = depth > 0 && sizes[depth] == sizes[depth - 1] ? previousIndex + 1 : 0
            for index in choices.indices where index >= start {
                let candidate = choices[index]
                guard Set(candidate.positions).isDisjoint(with: occupied) else { continue }
                if let result = place(groups + [candidate], occupied: occupied.union(candidate.positions),
                                      previousIndex: index, using: &generator) { return result }
                if visited >= nodeLimit || checks >= validationLimit { break }
            }
            return nil
        }
        let result = place([], occupied: [], previousIndex: -1, using: &generator)
        lastFriendlySearchNodes = visited
        let limited = visited >= nodeLimit || checks >= validationLimit
            || sizes.contains { analyses[$0]?.candidateSearchLimited == true }
#if DEBUG
        print("[FRIENDLY_SEARCH] sizes=\(sizes) nodes=\(visited)/\(nodeLimit) validations=\(checks)/\(validationLimit) candidateLimited=\(limited)")
#endif
        guard let result else {
            let colorsRejected = sizes.contains { analyses[$0]?.candidates.isEmpty == true }
            lastFriendlyPlanningFailure = limited ? "search-limit"
                : packingFound || colorsRejected ? "assignment-failure" : "geometry-impossible"
            return nil
        }
        return FriendlyRefillPlan(types: result.types, plannedTarget: sizes.count,
            forcedTypes: acceptedForced, strategy: "size-list-backtracking",
            forcedGroups: result.groups.map { $0.positions })
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
struct FriendlyRefillPreparation: Sendable {
    let slots: [GridPosition]
    let removedOrbCount: Int
    let sourceTemplates: [FriendlyGroupTemplate]
    let decision: FriendlyRefillDecision
    let planCalled: Bool
    let plan: FriendlyRefillPlan?
    let types: [OrbType]
    let validationDetectedGroups: Int?
    let directGroupCount: Int
    let usesFriendlyTypes: Bool
    let fallbackReason: String?
    var plannerTiming: FriendlyPlannerTiming = .zero

    var refillMode: String { usesFriendlyTypes ? "friendly" : "nonForced" }

    var failureCategory: String? {
        guard !usesFriendlyTypes, let fallbackReason else { return nil }
        if fallbackReason.hasPrefix("roll-miss") { return "probability-miss" }
        if fallbackReason.hasPrefix("search-limit") { return "search-limit" }
        if fallbackReason.hasPrefix("geometry-impossible") { return "geometry-impossible" }
        return "assignment-failure"
    }

    var plannedSizes: [Int] { usesFriendlyTypes ? plan?.forcedGroups.map { $0.count } ?? [] : [] }
    var fullSuccess: Bool { usesFriendlyTypes && plannedSizes.sorted() == decision.requestedSizes.sorted() }
    var searchLimited: Bool = false

    func directMatches(_ matches: [MatchResult]) -> [MatchResult] {
        guard usesFriendlyTypes, let plan else { return [] }
        return FriendlyRefillPipeline.directMatches(matches, plan: plan, slots: slots)
    }

    func refill(in grid: OrbGrid) -> [OrbSpawn] {
        precondition(slots == grid.emptyPositions() && types.count == slots.count)
        let spawns = grid.refill(types: types, at: slots)
        let matches = MatchDetector().detect(in: grid)
        let direct = directMatches(matches)
        assert(grid.emptyPositions().isEmpty && spawns.count == slots.count)
        assert(!usesFriendlyTypes || direct.map { $0.matchSize }.sorted() == plannedSizes.sorted())
#if DEBUG
        print("[FRIENDLY_REFILL] emptyBefore=\(slots.count) filled=\(spawns.count) emptyAfter=\(grid.emptyPositions().count)")
        print("[FRIENDLY_VALIDATE] requestedSizes=\(decision.requestedSizes) plannedSizes=\(plannedSizes) actualSizes=\(direct.map { $0.matchSize }) naturalExtraSizes=\(matches.filter { match in !direct.contains { $0.positions == match.positions && $0.type == match.type } }.map { $0.matchSize }) fullRequirementMet=\(usesFriendlyTypes && direct.map { $0.matchSize }.sorted() == decision.requestedSizes.sorted())")
#endif
        return spawns
    }

#if DEBUG
    func logDebug(resolveID: UInt) {
        let status: String
        if fullSuccess { status = "FULL_PLAN_SUCCESS" }
        else if usesFriendlyTypes { status = "PARTIAL_PLAN_SUCCESS" }
        else if failureCategory == "probability-miss" { status = "ALL_PROBABILITY_MISS" }
        else if failureCategory == "geometry-impossible" { status = "GEOMETRY_IMPOSSIBLE" }
        else if failureCategory == "search-limit" { status = "SEARCH_LIMIT_EXHAUSTED" }
        else { status = "ASSIGNMENT_FAILURE" }
        print("[FRIENDLY_PLAN] resolveID=\(resolveID) requestedCount=\(decision.requestedTarget) requestedSizes=\(decision.requestedSizes) plannedSizes=\(plannedSizes) status=\(status) searchLimited=\(searchLimited) reason=\(fallbackReason ?? "none") slots=\(FriendlyRefillPipeline.describe(slots))")
    }
#endif
}

enum FriendlyRefillPipeline {
    /// Captures the exact normalized groups found after a refill. This is the
    /// only input allowed to seed the next Friendly decision and V4 templates;
    /// requested/direct-template matches are validation metadata only.
    static func cascadeResolution(from scan: StableBoardScan) -> ResolveResult? {
        guard !scan.matches.isEmpty else { return nil }
        return ResolveResult(matches: scan.matches)
    }

    static func templates(from resolution: ResolveResult) -> [FriendlyGroupTemplate] {
        resolution.matches.enumerated().map {
            FriendlyGroupTemplate(sourceIndex: $0.offset, match: $0.element)
        }
    }

    static func prepare(
        grid: OrbGrid,
        previousResolution: ResolveResult,
        controller: SkyfallController
    ) -> FriendlyRefillPreparation {
        var generator = SystemRandomNumberGenerator()
        return prepare(grid: grid, previousResolution: previousResolution,
                       controller: controller, using: &generator)
    }

    static func directMatches(_ matches: [MatchResult], plan: FriendlyRefillPlan,
                              slots: [GridPosition]) -> [MatchResult] {
        let slotSet = Set(slots)
        if !plan.templatePlacements.isEmpty {
            return matches.filter { match in
                match.positions.isSubset(of: slotSet)
                    && plan.templatePlacements.contains { $0.matches(match) }
            }
        }
        return matches.filter { match in
            match.positions.isSubset(of: slotSet) && plan.forcedGroups.contains { group in
                Set(group) == match.positions && group.count == match.matchSize
                    && group.allSatisfy { plan.forcedTypes[$0] == match.type }
            }
        }
    }

    static func prepare<R: RandomNumberGenerator>(
        grid: OrbGrid, previousResolution: ResolveResult, controller: SkyfallController,
        using generator: inout R, roll: (Int) -> Double = { _ in Double.random(in: 0..<1) },
        planProvider: ((OrbGrid, [GridPosition], [Int]) -> FriendlyRefillPlan?)? = nil,
        searchNodeLimit: Int = 20_000, subsetAttemptLimit: Int = 256,
        waveNodeLimit: Int = 100_000
    ) -> FriendlyRefillPreparation {
        precondition(!controller.hasControlledTarget)
        let slots = grid.emptyPositions()
        guard var decision = controller.selectFriendlyRefillTarget(
            previousSizes: previousResolution.matches.map { $0.matchSize },
            removedOrbCount: previousResolution.removedOrbCount, emptySlotCount: slots.count, roll: roll)
        else { preconditionFailure("Friendly preparation called in ON mode") }
        let requested = decision.requestedSizes
        let called = decision.friendlyHit && !requested.isEmpty
        let analyzerStart = ProcessInfo.processInfo.systemUptime
        let sourceTemplates = templates(from: previousResolution)
        let templateAttempts = called ? FriendlyNaturalSkyfallPolicy.templateSubsets(
            from: sourceTemplates, bucketDecisions: decision.bucketDecisions) : []
        let analyzerMs = (ProcessInfo.processInfo.systemUptime - analyzerStart) * 1_000
        var reasons: [String] = []
        var limited = false
        var attempts = 0
        var waveNodes = 0
#if DEBUG
        print("[FRIENDLY_V4] mode=\(decision.mode.rawValue) previousSizes=\(decision.previousSizes) buckets=\(decision.bucketDecisions.count) slots=\(slots.count)")
        for template in sourceTemplates {
            print("[FRIENDLY_TEMPLATE] id=\(template.sourceIndex) type=\(template.orbType.rawValue) size=\(template.matchSize) offsets=\(describe(template.normalizedOffsets)) original=\(describe(Array(template.originalPositions)))")
        }
        for bucket in decision.bucketDecisions {
            print("[FRIENDLY_BUCKET] matchSize=\(bucket.matchSize) startingCombo=\(bucket.startingCombo) probability=\(bucket.probability) selectedTarget=\(bucket.selectedTarget)")
            for item in bucket.rolls {
                print("[FRIENDLY_ROLL] size=\(bucket.matchSize) target=\(item.groupCount) roll=\(item.roll) result=\(item.succeeded ? "GO" : "MISS")")
            }
        }
        print("[FRIENDLY_MERGED] status=\(decision.friendlyHit ? "PROBABILITY_GO" : "ALL_PROBABILITY_MISS") requestedSizes=\(requested) requestedGroups=\(requested.count) requestedOrbs=\(requested.reduce(0, +))")
        print("[FRIENDLY_BOARD] snapshot=\(grid.cells.map { $0.map { $0?.type.rawValue ?? "_" } }) slots=\(describe(slots))")
#endif
        if called {
            if planProvider == nil {
                let plan = controller.makeFriendlyNaturalRefill(
                    grid: grid, refillSlots: slots, templateAttempts: templateAttempts,
                    searchNodeLimit: searchNodeLimit, subsetAttemptLimit: subsetAttemptLimit,
                    waveNodeLimit: waveNodeLimit, using: &generator)
                attempts = controller.lastFriendlySubsetAttempts
                waveNodes = controller.lastFriendlySearchNodes
                limited = controller.lastFriendlySearchLimited
                if let plan, plan.types.count == slots.count,
                   plan.templatePlacements.count == plan.plannedTarget {
                    let assignments = Dictionary(uniqueKeysWithValues: zip(slots, plan.types))
                    let complete = (0..<grid.rows).map { row in (0..<grid.columns).map { column in
                        let position = GridPosition(row: row, column: column)
                        return grid.orb(at: position)?.type ?? assignments[position]!
                    } }
                    let matches = scan(in: OrbGrid(types: complete)).matches
                    let direct = directMatches(matches, plan: plan, slots: slots)
                    if direct.count == plan.templatePlacements.count {
                        decision.selectedTarget = direct.count
#if DEBUG
                        let copies = plan.templatePlacements.map {
                            "id=\($0.template.sourceIndex):\($0.template.orbType.rawValue):\($0.template.matchSize):\(describe($0.positions))"
                        }
                        print("[FRIENDLY_V4_RESULT] status=\(direct.map(\.matchSize).sorted() == requested.sorted() ? "FULL" : "PARTIAL") exactCopies=\(copies) requestedSizes=\(requested) detectedSizes=\(direct.map(\.matchSize)) attempts=\(attempts)/\(subsetAttemptLimit) waveNodes=\(waveNodes)/\(waveNodeLimit)")
#endif
                        return FriendlyRefillPreparation(slots: slots, removedOrbCount: previousResolution.removedOrbCount,
                            sourceTemplates: sourceTemplates, decision: decision,
                            planCalled: true, plan: plan, types: plan.types,
                            validationDetectedGroups: matches.count, directGroupCount: direct.count,
                            usesFriendlyTypes: true, fallbackReason: nil,
                            plannerTiming: FriendlyPlannerTiming(analyzerMs: analyzerMs,
                                candidateMs: controller.lastFriendlyCandidateMs,
                                searchMs: controller.lastFriendlySearchMs,
                                validationMs: controller.lastFriendlyValidationMs),
                            searchLimited: limited)
                    }
                }
                reasons.append(controller.lastFriendlyPlanningFailure ?? "assignment-failure")
            } else {
                // Test seam retained for legacy size-policy tests. Production
                // always uses the single exact-template V4 planner above.
                for sizes in FriendlyNaturalSkyfallPolicy.subsets(of: requested) {
                    guard attempts < max(1, subsetAttemptLimit), waveNodes < max(1, waveNodeLimit)
                    else { limited = true; break }
                    attempts += 1
                    let plan = planProvider?(grid, slots, sizes)
                    var reason = "assignment-failure"
                    if let plan, plan.types.count == slots.count,
                       plan.forcedGroups.map({ $0.count }).sorted() == sizes.sorted() {
                        let assignments = Dictionary(uniqueKeysWithValues: zip(slots, plan.types))
                        let complete = (0..<grid.rows).map { row in (0..<grid.columns).map { column in
                            let position = GridPosition(row: row, column: column)
                            return grid.orb(at: position)?.type ?? assignments[position]!
                        } }
                        let matches = scan(in: OrbGrid(types: complete)).matches
                        let direct = directMatches(matches, plan: plan, slots: slots)
                        if direct.map({ $0.matchSize }).sorted() == sizes.sorted() {
                            decision.selectedTarget = sizes.count
                            return FriendlyRefillPreparation(slots: slots,
                                removedOrbCount: previousResolution.removedOrbCount,
                                sourceTemplates: sourceTemplates, decision: decision,
                                planCalled: true, plan: plan, types: plan.types,
                                validationDetectedGroups: matches.count, directGroupCount: direct.count,
                                usesFriendlyTypes: true, fallbackReason: nil, searchLimited: limited)
                        }
                    }
                    if plan == nil { reason = "assignment-failure" }
                    reasons.append(reason)
#if DEBUG
                    print("[FRIENDLY_TRY] sizes=\(sizes) attempt=\(attempts)/\(subsetAttemptLimit) reason=\(reason)")
#endif
                }
            }
        }
        let reason = !decision.friendlyHit ? "roll-miss" : limited ? "search-limit"
            : !reasons.isEmpty && reasons.allSatisfy({ $0 == "geometry-impossible" }) ? "geometry-impossible" : "assignment-failure"
#if DEBUG
        print("[FRIENDLY_RESULT] fullSuccess=false partial=false attempts=\(attempts)/\(subsetAttemptLimit) waveNodes=\(waveNodes)/\(waveNodeLimit) reason=\(reason) refill=NORMAL_REFILL")
#endif
        let types = controller.makeNonForcedRefill(grid: grid, refillSlots: slots, using: &generator)
            ?? slots.map { _ in OrbType.allCases.randomElement(using: &generator) ?? .fire }
        return FriendlyRefillPreparation(slots: slots, removedOrbCount: previousResolution.removedOrbCount,
            sourceTemplates: sourceTemplates, decision: decision,
            planCalled: called, plan: nil, types: types,
            validationDetectedGroups: nil, directGroupCount: 0, usesFriendlyTypes: false,
            fallbackReason: reason,
            plannerTiming: FriendlyPlannerTiming(analyzerMs: analyzerMs,
                candidateMs: controller.lastFriendlyCandidateMs,
                searchMs: controller.lastFriendlySearchMs,
                validationMs: controller.lastFriendlyValidationMs),
            searchLimited: limited)
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
        if !preparation.directMatches(matches).isEmpty { detected += 1 }
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
        let direct = preparation.directMatches(matches).count
        if direct >= preparation.decision.selectedTarget { detectedExactOrMore += 1 }
    }
}
#endif
