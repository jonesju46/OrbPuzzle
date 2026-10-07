struct ResolveResult: Equatable, Sendable {
    let matches: [MatchResult]
    let comboCount: Int
    let removedPositions: Set<GridPosition>
    let removedOrbCount: Int

    init(matches: [MatchResult]) {
        self.matches = matches
        comboCount = matches.count
        removedPositions = matches.reduce(into: Set<GridPosition>()) {
            $0.formUnion($1.positions)
        }
        removedOrbCount = removedPositions.count
    }
}
