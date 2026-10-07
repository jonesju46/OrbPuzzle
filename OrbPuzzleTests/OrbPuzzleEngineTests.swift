import CoreGraphics
import XCTest
@testable import OrbPuzzle

final class OrbPuzzleEngineTests: XCTestCase {
    func testGameplaySettingDefaultsAndRanges() {
        XCTAssertEqual(GameSettings.defaultTurnDuration, 10)
        XCTAssertEqual(GameSettings.turnDurationRange, 5...99)
        XCTAssertFalse(GameSettings.defaultNoResolveDuringTurn)
        XCTAssertEqual(GameSettings.skyfallComboCountRange, 1...99)
    }

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
        for duration in [5.0, 10.0, 20.0, 99.0] {
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

    func testFingerUpKeepsTimedSessionAliveUntilExpiry() {
        let timer = TurnController(duration: 10)
        timer.select(orbID: UUID(), at: GridPosition(row: 0, column: 0), touchPosition: .zero)
        timer.beginTiming(at: 100)
        XCTAssertFalse(timer.update(at: 102))
        timer.endGesture()
        XCTAssertTrue(timer.isTiming)
        XCTAssertFalse(timer.hasActiveGesture)
        XCTAssertEqual(timer.remainingTime, 8, accuracy: 0.001)

        timer.select(orbID: UUID(), at: GridPosition(row: 4, column: 5), touchPosition: .zero)
        XCTAssertTrue(timer.isTiming)
        XCTAssertFalse(timer.update(at: 105))
        XCTAssertEqual(timer.remainingTime, 5, accuracy: 0.001)
        XCTAssertTrue(timer.update(at: 111))
        timer.expireSession()
        XCTAssertEqual(timer.remainingTime, 0)
        XCTAssertFalse(timer.isTiming)

        timer.resetSession()
        XCTAssertEqual(timer.remainingTime, 10)
    }

    func testEveryLeftAndRightEdgeOrbMapsInsideBoard() {
        let frame = CGRect(x: 14, y: 100, width: 600, height: 500)
        let cellWidth = frame.width / 6
        let cellHeight = frame.height / 5
        for row in 0..<5 {
            let y = frame.minY + (CGFloat(row) + 0.5) * cellHeight
            let left = TurnController.gridPosition(
                for: CGPoint(x: frame.minX + cellWidth * 0.5, y: y),
                boardFrame: frame,
                rows: 5,
                columns: 6
            )
            let right = TurnController.gridPosition(
                for: CGPoint(x: frame.maxX - cellWidth * 0.5, y: y),
                boardFrame: frame,
                rows: 5,
                columns: 6
            )
            XCTAssertEqual(left, GridPosition(row: row, column: 0))
            XCTAssertEqual(right, GridPosition(row: row, column: 5))
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

    func testHorizontalThreeRemovesAndRefillsExactlyThree() {
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 3))
        assertResolveCounts(grid: grid, combos: 1, removed: 3)
    }

    func testVerticalThreeRemovesAndRefillsExactlyThree() {
        var types = stableBoardTypes()
        for row in 2...4 { types[row][5] = .fire }
        let grid = OrbGrid(types: types)
        assertResolveCounts(grid: grid, combos: 1, removed: 3)
    }

    func testTwoSeparateThreeMatchesRemoveAndRefillExactlySix() {
        var types = stableBoardTypes()
        for column in 0...2 { types[4][column] = .fire }
        for column in 3...5 { types[4][column] = .water }
        let grid = OrbGrid(types: types)
        assertResolveCounts(grid: grid, combos: 2, removed: 6)
    }

    func testFiveMatchRemovesAndRefillsExactlyFive() {
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 5))
        assertResolveCounts(grid: grid, combos: 1, removed: 5)
    }

    func testSafeFinalRefillOnlyFillsEmptySlotsAndContainsNoMatch() {
        var generator = SeededGenerator(seed: 7)
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 3))
        let result = ResolveResult(matches: MatchDetector().detect(in: grid))
        _ = grid.remove(result.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()

        let types = SkyfallController().makeSafeRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        )
        XCTAssertEqual(types?.count, 3)
        guard let types else { return }
        let spawns = grid.refill(types: types, at: slots)
        XCTAssertEqual(spawns.count, 3)
        XCTAssertTrue(MatchDetector().detect(in: grid).isEmpty)
    }

    func testControlledCyclePreservesAllTwentySevenUnmatchedOrbIDs() {
        var generator = SeededGenerator(seed: 27)
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 3))
        let matches = MatchDetector().detect(in: grid)
        let result = ResolveResult(matches: matches)
        let removedIDs = Set(result.removedPositions.compactMap { grid.orb(at: $0)?.id })
        let preservedIDs = allOrbIDs(in: grid).subtracting(removedIDs)

        XCTAssertEqual(preservedIDs.count, 27)
        _ = grid.remove(result.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        let controller = SkyfallController()
        guard let types = controller.makeControlledRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        ) else {
            XCTFail("Expected a three-slot controlled refill")
            return
        }
        let spawns = grid.refill(types: types, at: slots)

        XCTAssertEqual(spawns.count, 3)
        XCTAssertTrue(preservedIDs.isSubset(of: allOrbIDs(in: grid)))
        XCTAssertEqual(allOrbIDs(in: grid).intersection(removedIDs).count, 0)
    }

    func testGuaranteedSkyfallUsesOneThreeOrbRefillPerCycleThroughNinetyNine() {
        for requested in [1, 10, 19, 99] {
            assertPersistentSkyfallCycles(requested: requested)
        }
    }

    func testSkyfallControllerRejectsOvershoot() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 1)
        XCTAssertFalse(controller.recordCycle(matchGroupCount: 0))
        XCTAssertFalse(controller.recordCycle(matchGroupCount: 2))
        XCTAssertTrue(controller.recordCycle(matchGroupCount: 1))
        XCTAssertFalse(controller.recordCycle(matchGroupCount: 1))
        XCTAssertEqual(controller.generatedCombos, 1)
    }

    func testInitialPlusSkyfallExamplesHaveNoComboCap() {
        for (initial, skyfall, expectedTotal) in [
            (3, 1, 4),
            (4, 10, 14),
            (2, 15, 17),
            (5, 99, 104)
        ] {
            let controller = SkyfallController()
            controller.reset(requestedCombos: skyfall)
            while controller.needsAnotherCycle {
                XCTAssertTrue(controller.recordCycle(matchGroupCount: 1))
            }
            XCTAssertEqual(initial + controller.generatedCombos, expectedTotal)
        }
    }

    private func assertResolveCounts(
        grid: OrbGrid,
        combos expectedCombos: Int,
        removed expectedRemoved: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = ResolveResult(matches: MatchDetector().detect(in: grid))
        XCTAssertEqual(result.comboCount, expectedCombos, file: file, line: line)
        XCTAssertEqual(result.removedOrbCount, expectedRemoved, file: file, line: line)
        XCTAssertEqual(grid.remove(result.removedPositions).count, expectedRemoved, file: file, line: line)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        XCTAssertEqual(slots.count, expectedRemoved, file: file, line: line)
        let refillTypes = slots.enumerated().map { OrbType.allCases[$0.offset % OrbType.allCases.count] }
        XCTAssertEqual(grid.refill(types: refillTypes, at: slots).count, expectedRemoved, file: file, line: line)
        XCTAssertEqual(allOrbIDs(in: grid).count, 30, file: file, line: line)
    }

    private func assertPersistentSkyfallCycles(
        requested: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var generator = SeededGenerator(seed: UInt64(requested))
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 3))
        let controller = SkyfallController()
        controller.reset(requestedCombos: requested)
        var cycleCount = 0

        while controller.needsAnotherCycle {
            let matches = MatchDetector().detect(in: grid)
            let result = ResolveResult(matches: matches)
            XCTAssertEqual(result.comboCount, 1, file: file, line: line)
            XCTAssertEqual(result.removedOrbCount, 3, file: file, line: line)
            XCTAssertEqual(matches.first?.count, 3, file: file, line: line)
            XCTAssertTrue(controller.recordCycle(matchGroupCount: result.comboCount), file: file, line: line)

            let removedIDs = Set(result.removedPositions.compactMap { grid.orb(at: $0)?.id })
            let preservedIDs = allOrbIDs(in: grid).subtracting(removedIDs)
            XCTAssertEqual(grid.remove(result.removedPositions).count, 3, file: file, line: line)
            _ = grid.collapse()
            let slots = grid.emptyPositions()
            XCTAssertEqual(slots.count, 3, file: file, line: line)

            let refillTypes: [OrbType]?
            if controller.needsAnotherCycle {
                refillTypes = controller.makeControlledRefill(
                    grid: grid,
                    refillSlots: slots,
                    using: &generator
                )
            } else {
                refillTypes = controller.makeSafeRefill(
                    grid: grid,
                    refillSlots: slots,
                    using: &generator
                )
            }
            guard let refillTypes else {
                XCTFail("Unable to plan slot-only refill", file: file, line: line)
                return
            }
            XCTAssertEqual(refillTypes.count, 3, file: file, line: line)
            let spawns = grid.refill(types: refillTypes, at: slots)
            XCTAssertEqual(spawns.count, 3, file: file, line: line)
            XCTAssertTrue(preservedIDs.isSubset(of: allOrbIDs(in: grid)), file: file, line: line)

            let nextMatches = MatchDetector().detect(in: grid)
            if controller.needsAnotherCycle {
                XCTAssertEqual(nextMatches.count, 1, file: file, line: line)
                XCTAssertEqual(nextMatches.first?.count, 3, file: file, line: line)
            } else {
                XCTAssertTrue(nextMatches.isEmpty, file: file, line: line)
            }
            cycleCount += 1
        }

        XCTAssertEqual(cycleCount, requested, file: file, line: line)
        XCTAssertEqual(controller.generatedCombos, requested, file: file, line: line)
        XCTAssertEqual(controller.remainingCombos, 0, file: file, line: line)
    }

    private func stableBoardTypes() -> [[OrbType]] {
        let types = OrbType.allCases
        return (0..<OrbGrid.defaultRows).map { row in
            (0..<OrbGrid.defaultColumns).map { column in
                types[(row * 2 + column) % types.count]
            }
        }
    }

    private func boardWithHorizontalMatch(length: Int) -> [[OrbType]] {
        var types = stableBoardTypes()
        for column in 0..<length { types[4][column] = .fire }
        return types
    }

    private func allOrbIDs(in grid: OrbGrid) -> Set<UUID> {
        Set(grid.cells.flatMap { $0 }.compactMap { $0?.id })
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
