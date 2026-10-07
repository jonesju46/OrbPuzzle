import Foundation

/// Advances guaranteed skyfall one visible match cycle at a time.
final class SkyfallController {
    private(set) var requestedCombos = GameSettings.defaultSkyfallComboCount
    private(set) var generatedCombos = 0

    var remainingCombos: Int { max(0, requestedCombos - generatedCombos) }
    var needsAnotherCycle: Bool { generatedCombos < requestedCombos }
    var isComplete: Bool { generatedCombos == requestedCombos }

    func reset(requestedCombos: Int) {
        self.requestedCombos = min(max(requestedCombos, 1), 99)
        generatedCombos = 0
    }

    /// A controlled cycle is valid only when MatchDetector found exactly one group.
    @discardableResult
    func recordCycle(matchGroupCount: Int) -> Bool {
        guard needsAnotherCycle, matchGroupCount == 1 else { return false }
        generatedCombos += 1
        return true
    }

    static func makeSingleMatchBoardTypes() -> [[OrbType]] {
        var generator = SystemRandomNumberGenerator()
        return makeSingleMatchBoardTypes(using: &generator)
    }

    static func makeSafeBoardTypes() -> [[OrbType]] {
        var generator = SystemRandomNumberGenerator()
        return makeSafeBoardTypes(using: &generator)
    }

    static func makeSingleMatchBoardTypes<R: RandomNumberGenerator>(using generator: inout R) -> [[OrbType]] {
        let detector = MatchDetector()

        // Bounded retries prevent generation work from stalling the main thread.
        for _ in 0..<64 {
            var board = makeSafeBoardTypes(using: &generator)
            let horizontal = Bool.random(using: &generator)
            let maximumLength = horizontal ? min(5, OrbGrid.defaultColumns) : min(5, OrbGrid.defaultRows)
            let length = Int.random(in: 3...maximumLength, using: &generator)
            let type = OrbType.allCases.randomElement(using: &generator) ?? .fire

            if horizontal {
                let row = Int.random(in: 0..<OrbGrid.defaultRows, using: &generator)
                let start = Int.random(in: 0...(OrbGrid.defaultColumns - length), using: &generator)
                for column in start..<(start + length) { board[row][column] = type }
            } else {
                let column = Int.random(in: 0..<OrbGrid.defaultColumns, using: &generator)
                let start = Int.random(in: 0...(OrbGrid.defaultRows - length), using: &generator)
                for row in start..<(start + length) { board[row][column] = type }
            }

            let matches = detector.detect(in: OrbGrid(types: board))
            if matches.count == 1, matches[0].count == length { return board }
        }

        // Deterministic fallback: exactly one horizontal three-match.
        var fallback = deterministicSafeBoardTypes()
        let type = OrbType.allCases.last ?? .heart
        for column in 0..<3 { fallback[0][column] = type }
        return fallback
    }

    static func makeSafeBoardTypes<R: RandomNumberGenerator>(using generator: inout R) -> [[OrbType]] {
        var board = Array(
            repeating: Array(repeating: OrbType.fire, count: OrbGrid.defaultColumns),
            count: OrbGrid.defaultRows
        )

        for row in 0..<OrbGrid.defaultRows {
            for column in 0..<OrbGrid.defaultColumns {
                let candidates = OrbType.allCases.shuffled(using: &generator)
                if let type = candidates.first(where: { candidate in
                    let makesHorizontal = column >= 2
                        && board[row][column - 1] == candidate
                        && board[row][column - 2] == candidate
                    let makesVertical = row >= 2
                        && board[row - 1][column] == candidate
                        && board[row - 2][column] == candidate
                    return !makesHorizontal && !makesVertical
                }) {
                    board[row][column] = type
                }
            }
        }
        return board
    }

    private static func deterministicSafeBoardTypes() -> [[OrbType]] {
        let types = OrbType.allCases
        return (0..<OrbGrid.defaultRows).map { row in
            (0..<OrbGrid.defaultColumns).map { column in
                types[(row * 2 + column) % types.count]
            }
        }
    }
}
