struct MatchResult: Equatable, Sendable {
    let type: OrbType
    let positions: Set<GridPosition>
    let count: Int
    let isFiveMatch: Bool

    init(type: OrbType, positions: Set<GridPosition>) {
        self.type = type
        self.positions = positions
        count = positions.count
        isFiveMatch = positions.count >= 5
    }
}
