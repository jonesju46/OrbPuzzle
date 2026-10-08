struct ResolvePhase: Equatable, Sendable {
    let type: OrbType
    let matches: [MatchResult]

    var groupCount: Int { matches.count }
    var comboIncrement: Int { groupCount }
    var removedPositions: Set<GridPosition> {
        matches.reduce(into: Set<GridPosition>()) {
            $0.formUnion($1.positions)
        }
    }
    var removedOrbCount: Int { removedPositions.count }
}

enum ResolveStep: Equatable, Sendable {
    case remove(ResolvePhase)
    case gravity(expectedRemovedOrbCount: Int)
    case refill(expectedRefillCount: Int)
}

struct StableBoardScan: Equatable, Sendable {
    let matches: [MatchResult]

    var canFinishResolve: Bool { matches.isEmpty }
}

struct ResolveResult: Equatable, Sendable {
    let matches: [MatchResult]
    let phases: [ResolvePhase]
    let comboCount: Int
    let removedPositions: Set<GridPosition>
    let removedOrbCount: Int

    var steps: [ResolveStep] {
        phases.flatMap { phase in
            phase.matches.map { match in
                ResolveStep.remove(ResolvePhase(type: phase.type, matches: [match]))
            }
        } + [
            .gravity(expectedRemovedOrbCount: removedOrbCount),
            .refill(expectedRefillCount: removedOrbCount)
        ]
    }

    init(matches: [MatchResult]) {
        self.matches = matches
        let grouped = Dictionary(grouping: matches, by: \.type)
        phases = OrbType.resolveOrder.compactMap { type in
            guard let matches = grouped[type], !matches.isEmpty else { return nil }
            return ResolvePhase(type: type, matches: matches)
        }
        comboCount = matches.count
        removedPositions = matches.reduce(into: Set<GridPosition>()) {
            $0.formUnion($1.positions)
        }
        removedOrbCount = removedPositions.count
    }
}
