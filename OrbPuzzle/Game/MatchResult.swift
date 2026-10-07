struct MatchResult: Equatable, Sendable {
    let type: OrbType
    let positions: Set<GridPosition>

    var matchSize: Int { positions.count }
    var count: Int { matchSize }
    var isFiveMatch: Bool { matchSize >= 5 }

    init(type: OrbType, positions: Set<GridPosition>) {
        self.type = type
        self.positions = positions
    }
}
