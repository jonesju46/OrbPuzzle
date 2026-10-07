import Foundation

/// Tracks guaranteed skyfall combos and creates boards containing an exact number
/// of disconnected match groups. It never advances animations synchronously.
final class SkyfallController {
    static let maximumGroupsPerBoard = 10

    private(set) var requestedCombos = GameSettings.defaultSkyfallComboCount
    private(set) var generatedCombos = 0

    var remainingCombos: Int { max(0, requestedCombos - generatedCombos) }
    var isComplete: Bool { generatedCombos == requestedCombos }

    func reset(requestedCombos: Int) {
        self.requestedCombos = min(max(requestedCombos, 1), 99)
        generatedCombos = 0
    }

    func nextBatchSize() -> Int {
        min(remainingCombos, Self.maximumGroupsPerBoard)
    }

    @discardableResult
    func recordGenerated(_ count: Int) -> Bool {
        guard count > 0, count <= remainingCombos else { return false }
        generatedCombos += count
        return true
    }

    /// Returns a stable 6×5 board with exactly `matchGroupCount` horizontal groups.
    /// Two groups fit in each row; their types are chosen so adjacent and vertical
    /// groups never merge. A count of zero is the final no-match refill board.
    static func makeBoardTypes(matchGroupCount: Int) -> [[OrbType]] {
        precondition((0...maximumGroupsPerBoard).contains(matchGroupCount))
        let types = OrbType.allCases
        var board = (0..<OrbGrid.defaultRows).map { row in
            (0..<OrbGrid.defaultColumns).map { column in
                types[(row * 2 + column) % types.count]
            }
        }

        guard matchGroupCount > 0 else { return board }
        for group in 0..<matchGroupCount {
            let row = group / 2
            let half = group % 2
            let firstColumn = half * 3
            let type = types[(row * 2 + half * 3 + 5) % types.count]
            for column in firstColumn..<(firstColumn + 3) {
                board[row][column] = type
            }
        }
        return board
    }
}
