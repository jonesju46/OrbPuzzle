import Foundation

enum OrbType: String, CaseIterable, Codable, Sendable {
    case fire
    case water
    case wood
    case light
    case dark
    case heart

    /// Gameplay resolve order is explicit and must not depend on declaration,
    /// raw-value, dictionary, or match-detector ordering.
    static let resolveOrder: [OrbType] = [
        .water,
        .fire,
        .wood,
        .light,
        .dark,
        .heart
    ]

    var displayName: String { rawValue.capitalized }
}

struct Orb: Identifiable, Equatable, Sendable {
    let id: UUID
    var type: OrbType

    init(id: UUID = UUID(), type: OrbType) {
        self.id = id
        self.type = type
    }
}

struct GridPosition: Hashable, Sendable {
    let row: Int
    let column: Int

    func isAdjacent(to other: GridPosition) -> Bool {
        let rowDistance = abs(row - other.row)
        let columnDistance = abs(column - other.column)
        return rowDistance <= 1 && columnDistance <= 1 && (rowDistance + columnDistance) > 0
    }
}
