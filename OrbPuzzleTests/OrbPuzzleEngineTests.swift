import CoreGraphics
import XCTest
@testable import OrbPuzzle

final class OrbPuzzleEngineTests: XCTestCase {
    func testBoardDimensionsAndInitialBoardHasNoMatch() {
        let grid = OrbGrid()
        grid.fillAvoidingInitialMatches { OrbType.allCases.randomElement()! }
        XCTAssertEqual(grid.rows, 5)
        XCTAssertEqual(grid.columns, 6)
        XCTAssertEqual(grid.cells.flatMap { $0 }.compactMap { $0 }.count, 30)
        XCTAssertTrue(MatchDetector().detect(in: grid).isEmpty)
    }

    func testHorizontalThreeFourFiveAndSix() {
        for length in 3...6 {
            let row = Array(repeating: OrbType.fire, count: length)
            let grid = OrbGrid(types: [row])
            let result = MatchDetector().detect(in: grid)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0].count, length)
            XCTAssertEqual(result[0].isFiveMatch, length >= 5)
        }
    }

    func testVerticalThreeFourAndFive() {
        for length in 3...5 {
            let grid = OrbGrid(types: Array(repeating: [.water], count: length))
            let result = MatchDetector().detect(in: grid)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0].count, length)
            XCTAssertEqual(result[0].isFiveMatch, length >= 5)
        }
    }

    func testSeparateGroupsAreMultipleCombos() {
        let grid = OrbGrid(types: [
            [.fire, .fire, .fire, .water, .wood, .light],
            [.water, .wood, .light, .dark, .heart, .water],
            [.wood, .water, .wood, .light, .light, .light]
        ])
        XCTAssertEqual(MatchDetector().detect(in: grid).count, 2)
    }

    func testAllEightDirectionsSwapAndEdgesRejectOutOfBounds() {
        let center = GridPosition(row: 1, column: 1)
        for rowDelta in -1...1 {
            for columnDelta in -1...1 where rowDelta != 0 || columnDelta != 0 {
                XCTAssertTrue(center.isAdjacent(to: GridPosition(row: 1 + rowDelta, column: 1 + columnDelta)))
            }
        }
        let grid = OrbGrid(types: [
            [.fire, .water],
            [.wood, .light]
        ])
        XCTAssertTrue(grid.swap(GridPosition(row: 0, column: 0), GridPosition(row: 1, column: 1)))
        XCTAssertEqual(grid.orb(at: GridPosition(row: 1, column: 1))?.type, .fire)
        XCTAssertFalse(grid.swap(GridPosition(row: 0, column: 0), GridPosition(row: -1, column: 0)))

        let directDiagonal = TurnController.traversedPositions(
            from: CGPoint(x: 80, y: 70),
            to: CGPoint(x: 110, y: 130),
            boardFrame: CGRect(x: 0, y: 0, width: 600, height: 500),
            rows: 5,
            columns: 6
        )
        XCTAssertEqual(directDiagonal, [
            GridPosition(row: 0, column: 0),
            GridPosition(row: 1, column: 1)
        ])
    }

    func testFastTraversalHorizontalVerticalAndDiagonalDoesNotSkip() {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        for (start, end, expectedColumns) in [
            (CGPoint(x: 50, y: 50), CGPoint(x: 550, y: 50), [0, 1, 2, 3, 4, 5]),
            (CGPoint(x: 550, y: 50), CGPoint(x: 50, y: 50), [5, 4, 3, 2, 1, 0])
        ] {
            let path = TurnController.traversedPositions(
                from: start, to: end, boardFrame: frame, rows: 5, columns: 6
            )
            XCTAssertEqual(path.map(\.column), expectedColumns)
        }

        for (start, end, expectedRows) in [
            (CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 450), [0, 1, 2, 3, 4]),
            (CGPoint(x: 50, y: 450), CGPoint(x: 50, y: 50), [4, 3, 2, 1, 0])
        ] {
            let path = TurnController.traversedPositions(
                from: start, to: end, boardFrame: frame, rows: 5, columns: 6
            )
            XCTAssertEqual(path.map(\.row), expectedRows)
        }

        let diagonal = TurnController.traversedPositions(
            from: CGPoint(x: 50, y: 50), to: CGPoint(x: 450, y: 450),
            boardFrame: frame, rows: 5, columns: 6
        )
        XCTAssertTrue(zip(diagonal, diagonal.dropFirst()).allSatisfy { pair in
            pair.0.isAdjacent(to: pair.1)
        })
        XCTAssertEqual(diagonal.last, GridPosition(row: 4, column: 4))

        let reverseDiagonal = TurnController.traversedPositions(
            from: CGPoint(x: 450, y: 450), to: CGPoint(x: 50, y: 50),
            boardFrame: frame, rows: 5, columns: 6
        )
        XCTAssertTrue(zip(reverseDiagonal, reverseDiagonal.dropFirst()).allSatisfy { pair in
            pair.0.isAdjacent(to: pair.1)
        })
        XCTAssertEqual(reverseDiagonal.last, GridPosition(row: 0, column: 0))
    }

    func testTimerStartsExplicitlyAndClamps() {
        for duration in [5.0, 10.0, 20.0] {
            let timer = TurnController(duration: duration)
            timer.select(orbID: UUID(), at: GridPosition(row: 0, column: 0), touchPosition: .zero)
            XCTAssertFalse(timer.isTiming)
            timer.beginTiming(at: 100)
            XCTAssertFalse(timer.update(at: 100 + duration / 2))
            XCTAssertEqual(timer.remainingTime, duration / 2, accuracy: 0.001)
            XCTAssertEqual(timer.progress, 0.5, accuracy: 0.001)
            XCTAssertTrue(timer.update(at: 101 + duration))
            XCTAssertEqual(timer.remainingTime, 0)
            XCTAssertEqual(timer.progress, 0)
        }
    }

    func testGravityLeavesNoGaps() {
        let grid = OrbGrid(types: [
            [.fire], [.water], [.wood], [.light], [.dark]
        ])
        _ = grid.remove([GridPosition(row: 1, column: 0), GridPosition(row: 3, column: 0)])
        _ = grid.collapse()
        XCTAssertEqual(grid.orb(at: GridPosition(row: 0, column: 0))?.type, .fire)
        XCTAssertEqual(grid.orb(at: GridPosition(row: 1, column: 0))?.type, .wood)
        XCTAssertEqual(grid.orb(at: GridPosition(row: 2, column: 0))?.type, .dark)
        XCTAssertNil(grid.orb(at: GridPosition(row: 3, column: 0)))
        XCTAssertNil(grid.orb(at: GridPosition(row: 4, column: 0)))
    }

    func testCascadeBoundsAtOneTenThirtyAndNinetyNine() {
        for maximum in [1, 10, 30, 99] {
            let controller = CascadeController(maximumRounds: maximum)
            var count = 0
            while controller.beginNextRound() { count += 1 }
            XCTAssertEqual(count, maximum)
        }
    }
}
