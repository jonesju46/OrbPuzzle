import CoreGraphics
import XCTest
@testable import OrbPuzzle

final class OrbPuzzleEngineTests: XCTestCase {
    func testNewGameCreatesThirtyNewOrbIDsAndResetsTransientState() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.configure(turnDuration: 10, noResolveDuringTurn: false, skyfallComboCount: 19)
        scene.startNewGame()
        let before = scene.sessionSnapshot

        scene.startNewGame()
        let after = scene.sessionSnapshot

        XCTAssertEqual(before.orbIDs.count, 30)
        XCTAssertEqual(after.orbIDs.count, 30)
        XCTAssertTrue(before.orbIDs.isDisjoint(with: after.orbIDs))
        XCTAssertEqual(after.state, .idle)
        XCTAssertEqual(after.comboCount, 0)
        XCTAssertEqual(after.generatedSkyfall, 0)
        XCTAssertEqual(after.requestedSkyfall, 19)
        XCTAssertEqual(after.remainingTime, 10, accuracy: 0.001)
        XCTAssertEqual(after.progress, 1, accuracy: 0.001)
        XCTAssertEqual(after.resolveLifecycleState, .idle)
        XCTAssertGreaterThan(after.resolveID, before.resolveID)
    }

    func testComboResetClearsPreviousTwelve() {
        let controller = ComboController()
        let matches = (0..<12).map { makeMatch(type: .fire, group: $0) }
        XCTAssertEqual(controller.add(matches), 12)

        controller.reset()

        XCTAssertEqual(controller.comboCount, 0)
    }

    func testSkyfallResetClearsSevenOfNineteenProgress() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 19)
        for _ in 0..<7 { XCTAssertTrue(controller.recordCycle(matchGroupCount: 1)) }
        XCTAssertEqual(controller.generatedCombos, 7)

        controller.reset(requestedCombos: 19)

        XCTAssertEqual(controller.generatedCombos, 0)
        XCTAssertEqual(controller.requestedCombos, 19)
    }

    func testNewGameUsesConfiguredTurnDuration() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.configure(turnDuration: 20, noResolveDuringTurn: true, skyfallComboCount: 19)

        scene.startNewGame()

        XCTAssertEqual(scene.sessionSnapshot.remainingTime, 20, accuracy: 0.001)
        XCTAssertEqual(scene.sessionSnapshot.progress, 1, accuracy: 0.001)
        XCTAssertEqual(scene.sessionSnapshot.requestedSkyfall, 19)
    }

    func testOldCallbackIsRejectedAfterNewSessionBegins() {
        var fence = GameSessionFence()
        let oldSessionID = fence.beginNewSession()
        XCTAssertTrue(fence.accepts(oldSessionID))

        let currentSessionID = fence.beginNewSession()

        XCTAssertFalse(fence.accepts(oldSessionID))
        XCTAssertTrue(fence.accepts(currentSessionID))
    }

    func testApplyingSettingsDoesNotReplaceCurrentBoard() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.startNewGame()
        let before = scene.sessionSnapshot

        scene.configure(turnDuration: 20, noResolveDuringTurn: true, skyfallComboCount: 19)
        let after = scene.sessionSnapshot

        XCTAssertEqual(after.sessionID, before.sessionID)
        XCTAssertEqual(after.orbIDs, before.orbIDs)
        XCTAssertEqual(after.remainingTime, 20, accuracy: 0.001)
    }

    func testStartingAgainAfterLeavingCreatesEntirelyNewBoard() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.startNewGame()
        let firstGame = scene.sessionSnapshot

        scene.startNewGame()
        let secondGame = scene.sessionSnapshot

        XCTAssertEqual(secondGame.sessionID, firstGame.sessionID + 1)
        XCTAssertTrue(firstGame.orbIDs.isDisjoint(with: secondGame.orbIDs))
    }

    func testGameplaySettingDefaultsAndRanges() {
        XCTAssertEqual(GameSettings.defaultTurnDuration, 10)
        XCTAssertEqual(GameSettings.turnDurationRange, 5...99)
        XCTAssertFalse(GameSettings.defaultTurnTimeEnabled)
        XCTAssertFalse(GameSettings.defaultNoResolveDuringTurn)
        XCTAssertFalse(GameSettings.defaultSkyfallComboEnabled)
        XCTAssertEqual(GameSettings.skyfallComboCountRange, 1...99)
    }

    func testTurnTimeToggleUsesFiveWhenOffAndStoredValueWhenOn() {
        let storedTurnTime = 30.0
        var enabled = true

        XCTAssertEqual(
            GameSettings.effectiveTurnDuration(enabled: enabled, configured: storedTurnTime),
            30
        )
        enabled = false
        XCTAssertEqual(GameSettings.effectiveTurnDuration(enabled: enabled, configured: storedTurnTime), 5)
        enabled = true
        XCTAssertEqual(GameSettings.effectiveTurnDuration(enabled: enabled, configured: storedTurnTime), 30)
        XCTAssertEqual(storedTurnTime, 30)
    }

    func testSkyfallToggleUsesZeroWhenOffAndStoredValueWhenOn() {
        let storedSkyfallCombo = 19
        var enabled = true

        XCTAssertEqual(
            GameSettings.effectiveSkyfallComboCount(enabled: enabled, configured: storedSkyfallCombo),
            19
        )
        enabled = false
        XCTAssertEqual(GameSettings.effectiveSkyfallComboCount(enabled: enabled, configured: storedSkyfallCombo), 0)
        enabled = true
        XCTAssertEqual(GameSettings.effectiveSkyfallComboCount(enabled: enabled, configured: storedSkyfallCombo), 19)
        XCTAssertEqual(storedSkyfallCombo, 19)
    }

    func testSkyfallOffDisablesControlledCyclesButNaturalMatchStillRequiresResolve() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 0)
        var types = matchTestBoardTypes()
        for row in [0, 2, 4] { types[row][0] = .light }
        for row in [1, 3] {
            for column in 0...2 { types[row][column] = .water }
        }
        let grid = OrbGrid(types: types)
        let initialResult = ResolveResult(matches: MatchDetector().detect(in: grid))
        _ = grid.remove(initialResult.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        var generator = SeededGenerator(seed: 317)
        guard let refillTypes = controller.makeSafeRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        ) else {
            XCTFail("Expected a safe refill with controlled skyfall disabled")
            return
        }
        _ = grid.refill(types: refillTypes, at: slots)
        let naturalMatches = MatchDetector().detect(in: grid)

        XCTAssertFalse(controller.needsAnotherCycle)
        XCTAssertTrue(controller.isComplete)
        XCTAssertEqual(controller.requestedCombos, 0)
        XCTAssertEqual(naturalMatches.count, 1)
        XCTAssertEqual(naturalMatches[0].type, .light)
        XCTAssertFalse(StableBoardScan(matches: naturalMatches).canFinishResolve)
    }

    func testNewGameUsesEffectiveToggleValues() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.configure(
            turnDuration: GameSettings.effectiveTurnDuration(enabled: false, configured: 30),
            noResolveDuringTurn: true,
            skyfallComboCount: GameSettings.effectiveSkyfallComboCount(enabled: false, configured: 19)
        )
        scene.startNewGame()
        XCTAssertEqual(scene.sessionSnapshot.remainingTime, 5, accuracy: 0.001)
        XCTAssertEqual(scene.sessionSnapshot.requestedSkyfall, 0)

        scene.configure(
            turnDuration: GameSettings.effectiveTurnDuration(enabled: true, configured: 30),
            noResolveDuringTurn: true,
            skyfallComboCount: GameSettings.effectiveSkyfallComboCount(enabled: true, configured: 19)
        )
        scene.startNewGame()
        XCTAssertEqual(scene.sessionSnapshot.remainingTime, 30, accuracy: 0.001)
        XCTAssertEqual(scene.sessionSnapshot.requestedSkyfall, 19)
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
            XCTAssertEqual(result[0].matchSize, length)
            XCTAssertEqual(result[0].isFiveMatch, length >= 5)
        }
    }

    func testVerticalThreeFourAndFive() {
        for length in 3...5 {
            let grid = OrbGrid(types: Array(repeating: [.water], count: length))
            let result = MatchDetector().detect(in: grid)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0].matchSize, length)
            XCTAssertEqual(result[0].isFiveMatch, length >= 5)
        }
    }

    func testAllSixOrbTypesUseTheSameThreeOrMoreRule() {
        for type in OrbType.allCases {
            let result = MatchDetector().detect(in: OrbGrid(types: [[type, type, type]]))
            XCTAssertEqual(result.count, 1, "type=\(type)")
            XCTAssertEqual(result[0].type, type)
            XCTAssertEqual(result[0].matchSize, 3)
        }
    }

    func testConnectedTAndLShapesNormalizeToOneGroup() {
        let tShape: Set<GridPosition> = [
            GridPosition(row: 2, column: 1),
            GridPosition(row: 2, column: 2),
            GridPosition(row: 2, column: 3),
            GridPosition(row: 3, column: 2),
            GridPosition(row: 4, column: 2)
        ]
        let lShape: Set<GridPosition> = [
            GridPosition(row: 0, column: 1),
            GridPosition(row: 1, column: 1),
            GridPosition(row: 2, column: 1),
            GridPosition(row: 0, column: 2),
            GridPosition(row: 0, column: 3)
        ]

        for positions in [tShape, lShape] {
            let result = MatchDetector().detect(in: gridWithHeart(at: positions))
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0].type, .heart)
            XCTAssertEqual(result[0].matchSize, 5)
            XCTAssertEqual(result[0].positions, positions)
        }
    }

    func testCrossCountsSharedCenterOnce() {
        let positions: Set<GridPosition> = Set(
            (0..<5).map { GridPosition(row: $0, column: 2) }
                + (1...3).map { GridPosition(row: 2, column: $0) }
        )
        let result = MatchDetector().detect(in: gridWithHeart(at: positions))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].matchSize, 7)
        XCTAssertEqual(result[0].positions, positions)
    }

    func testConnectedRunsSupportTenAndThirtyOrbGroups() {
        let tenPositions = Set(
            (1...2).flatMap { row in
                (0..<5).map { GridPosition(row: row, column: $0) }
            }
        )
        let tenResult = MatchDetector().detect(in: gridWithHeart(at: tenPositions))
        XCTAssertEqual(tenResult.count, 1)
        XCTAssertEqual(tenResult[0].matchSize, 10)
        XCTAssertEqual(ResolveResult(matches: tenResult).comboCount, 1)
        XCTAssertEqual(ResolveResult(matches: tenResult).removedOrbCount, 10)

        let fullGrid = OrbGrid(types: Array(
            repeating: Array(repeating: .heart, count: 6),
            count: 5
        ))
        let thirtyResult = MatchDetector().detect(in: fullGrid)
        XCTAssertEqual(thirtyResult.count, 1)
        XCTAssertEqual(thirtyResult[0].matchSize, 30)
        XCTAssertEqual(thirtyResult[0].positions.count, 30)
        XCTAssertEqual(ResolveResult(matches: thirtyResult).comboCount, 1)
        XCTAssertEqual(ResolveResult(matches: thirtyResult).removedOrbCount, 30)
    }

    func testDisconnectedSameColorRunsRemainSeparateCombos() {
        let first = Set((0...2).map { GridPosition(row: 0, column: $0) })
        let second = Set((3...5).map { GridPosition(row: 4, column: $0) })
        let result = MatchDetector().detect(in: gridWithHeart(at: first.union(second)))

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.matchSize), [3, 3])
        XCTAssertTrue(result[0].positions.isDisjoint(with: result[1].positions))
        XCTAssertEqual(ResolveResult(matches: result).comboCount, 2)
        XCTAssertEqual(ResolveResult(matches: result).removedOrbCount, 6)
    }

    func testGravityRefillChainIsDetectedByFullBoardScan() {
        var types = matchTestBoardTypes()
        for row in [0, 2, 4] { types[row][0] = .light }
        for row in [1, 3] {
            for column in 0...2 { types[row][column] = .water }
        }
        let grid = OrbGrid(types: types)
        let initial = MatchDetector().detect(in: grid)
        XCTAssertEqual(initial.filter { $0.type == .water }.count, 2)

        let initialResult = ResolveResult(matches: initial)
        _ = grid.remove(initialResult.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        let gravityMatches = MatchDetector().detect(in: grid)
        XCTAssertEqual(gravityMatches.count, 1)
        XCTAssertEqual(gravityMatches[0].type, .light)
        XCTAssertEqual(gravityMatches[0].matchSize, 3)

        var generator = SeededGenerator(seed: 317)
        let refillTypes = SkyfallController().makeSafeRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        )
        XCTAssertEqual(refillTypes?.count, slots.count)
        guard let refillTypes else { return }
        _ = grid.refill(types: refillTypes, at: slots)

        let stableBoard = StableBoardScan(matches: MatchDetector().detect(in: grid))
        XCTAssertFalse(stableBoard.canFinishResolve)
        XCTAssertEqual(stableBoard.matches.count, 1)
        XCTAssertEqual(stableBoard.matches[0].type, .light)
        XCTAssertEqual(stableBoard.matches[0].matchSize, 3)
    }

    func testStableBoardCannotFinishWhileAnyMatchRemains() {
        let matched = StableBoardScan(matches: MatchDetector().detect(
            in: gridWithHeart(at: Set((0...2).map { GridPosition(row: 0, column: $0) }))
        ))
        let clear = StableBoardScan(matches: MatchDetector().detect(in: OrbGrid(types: matchTestBoardTypes())))

        XCTAssertFalse(matched.canFinishResolve)
        XCTAssertTrue(clear.canFinishResolve)
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

    func testElapsedTimeIsConfiguredDurationMinusRemainingTime() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)

        XCTAssertFalse(timer.update(at: 104.6))

        XCTAssertEqual(timer.remainingTime, 25.4, accuracy: 0.001)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 4.6, accuracy: 0.001)
    }

    func testElapsedTimeShowsThreeSecondsWhenTwentySevenRemain() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)

        XCTAssertFalse(timer.update(at: 103))

        XCTAssertEqual(timer.remainingTime, 27, accuracy: 0.001)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 3, accuracy: 0.001)
    }

    func testFingerUpStoresCompletedElapsedTimeWithoutZeroingRemainingTime() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)
        XCTAssertFalse(timer.update(at: 104.6))

        timer.completeSession()

        XCTAssertFalse(timer.isTiming)
        XCTAssertEqual(timer.remainingTime, 25.4, accuracy: 0.001)
        XCTAssertEqual(timer.lastCompletedTurnTime ?? -1, 4.6, accuracy: 0.001)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 4.6, accuracy: 0.001)
    }

    func testCompletedElapsedTimeDoesNotAdvanceDuringResolve() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)
        XCTAssertFalse(timer.update(at: 104.6))
        timer.completeSession()

        XCTAssertFalse(timer.update(at: 500))

        XCTAssertEqual(timer.displayedElapsedTurnTime, 4.6, accuracy: 0.001)
    }

    func testExpiredTurnShowsFullConfiguredDurationDuringResolve() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)
        XCTAssertTrue(timer.update(at: 130))

        timer.expireSession()

        XCTAssertEqual(timer.remainingTime, 0, accuracy: 0.001)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 30, accuracy: 0.001)
    }

    func testPreparingNextIdleTurnPreservesLastCompletedTime() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)
        XCTAssertFalse(timer.update(at: 104.6))
        timer.completeSession()

        timer.prepareNextSession()

        XCTAssertEqual(timer.remainingTime, 30, accuracy: 0.001)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 4.6, accuracy: 0.001)
    }

    func testNextValidMoveStartsFreshElapsedTimeButTouchAloneDoesNot() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)
        XCTAssertFalse(timer.update(at: 104.6))
        timer.completeSession()
        timer.prepareNextSession()

        timer.select(orbID: UUID(), at: GridPosition(row: 0, column: 0), touchPosition: .zero)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 4.6, accuracy: 0.001)

        timer.beginTiming(at: 200)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 0, accuracy: 0.001)
        XCTAssertFalse(timer.update(at: 203))
        XCTAssertEqual(timer.displayedElapsedTurnTime, 3, accuracy: 0.001)
    }

    func testNewGameResetClearsElapsedTurnTime() {
        let timer = TurnController(duration: 30)
        timer.beginTiming(at: 100)
        XCTAssertFalse(timer.update(at: 104.6))
        timer.completeSession()

        timer.resetSession()

        XCTAssertEqual(timer.remainingTime, 30, accuracy: 0.001)
        XCTAssertEqual(timer.elapsedTurnTime, 0, accuracy: 0.001)
        XCTAssertNil(timer.lastCompletedTurnTime)
        XCTAssertEqual(timer.displayedElapsedTurnTime, 0, accuracy: 0.001)
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

    func testResolveOrderPlacesWaterBeforeFireAndDark() {
        let matches = [
            makeMatch(type: .fire, group: 0),
            makeMatch(type: .water, group: 1),
            makeMatch(type: .dark, group: 2)
        ]

        XCTAssertEqual(
            ResolveResult(matches: matches).phases.map(\.type),
            [.water, .fire, .dark]
        )
    }

    func testResolveOrderContainsAllSixGameplayOrbTypes() {
        let matches = [
            makeMatch(type: .heart, group: 0),
            makeMatch(type: .light, group: 1),
            makeMatch(type: .wood, group: 2),
            makeMatch(type: .water, group: 3),
            makeMatch(type: .fire, group: 4),
            makeMatch(type: .dark, group: 5)
        ]

        XCTAssertEqual(OrbType.allCases.count, 6)
        XCTAssertEqual(OrbType.resolveOrder, [.water, .fire, .wood, .light, .dark, .heart])
        XCTAssertEqual(ResolveResult(matches: matches).phases.map(\.type), OrbType.resolveOrder)
    }

    func testSameTypeGroupsShareOnePhaseButKeepEveryCombo() {
        let matches = [
            makeMatch(type: .heart, group: 0),
            makeMatch(type: .water, group: 1),
            makeMatch(type: .fire, group: 2),
            makeMatch(type: .water, group: 3),
            makeMatch(type: .heart, group: 4)
        ]
        let result = ResolveResult(matches: matches)

        XCTAssertEqual(result.phases.map(\.type), [.water, .fire, .heart])
        XCTAssertEqual(result.phases.map(\.groupCount), [2, 1, 2])
        XCTAssertEqual(result.comboCount, 5)
    }

    func testTwoWaterTriplesFormTwoSequentialRemovalStepsAndTwoCombos() {
        let matches = [
            MatchResult(
                type: .water,
                positions: Set((0..<3).map { GridPosition(row: 0, column: $0) })
            ),
            MatchResult(
                type: .water,
                positions: Set((3..<6).map { GridPosition(row: 1, column: $0) })
            )
        ]

        let result = ResolveResult(matches: matches)
        let removals = removalPhases(in: result)

        XCTAssertEqual(result.phases.count, 1)
        XCTAssertEqual(result.phases[0].type, .water)
        XCTAssertEqual(result.phases[0].comboIncrement, 2)
        XCTAssertEqual(result.phases[0].removedOrbCount, 6)
        XCTAssertEqual(removals.map(\.type), [.water, .water])
        XCTAssertEqual(removals.map(\.comboIncrement), [1, 1])
        XCTAssertEqual(removals.map(\.removedOrbCount), [3, 3])
    }

    func testWaterThreeAndFiveBecomeSeparateThreeThenFiveRemovalSteps() {
        let matches = [
            MatchResult(
                type: .water,
                positions: Set((0..<3).map { GridPosition(row: 0, column: $0) })
            ),
            MatchResult(
                type: .water,
                positions: Set((0..<5).map { GridPosition(row: 2, column: $0) })
            )
        ]

        let result = ResolveResult(matches: matches)
        let removals = removalPhases(in: result)

        XCTAssertEqual(result.phases.count, 1)
        XCTAssertEqual(result.phases[0].comboIncrement, 2)
        XCTAssertEqual(result.phases[0].removedOrbCount, 8)
        XCTAssertEqual(removals.map(\.type), [.water, .water])
        XCTAssertEqual(removals.map(\.comboIncrement), [1, 1])
        XCTAssertEqual(removals.map(\.removedOrbCount), [3, 5])
    }

    func testTwoWaterThenThreeFireGroupsUseSequentialAttributeOrderedSteps() {
        let matches = [
            MatchResult(type: .fire, positions: Set((0..<3).map { GridPosition(row: 1, column: $0) })),
            MatchResult(type: .water, positions: Set((0..<3).map { GridPosition(row: 0, column: $0) })),
            MatchResult(type: .fire, positions: Set((0..<3).map { GridPosition(row: 3, column: $0) })),
            MatchResult(type: .water, positions: Set((0..<3).map { GridPosition(row: 2, column: $0) })),
            MatchResult(type: .fire, positions: Set((0..<3).map { GridPosition(row: 4, column: $0) }))
        ]

        let result = ResolveResult(matches: matches)
        let removals = removalPhases(in: result)

        XCTAssertEqual(result.phases.map(\.type), [.water, .fire])
        XCTAssertEqual(result.phases.map(\.comboIncrement), [2, 3])
        XCTAssertEqual(removals.map(\.type), [.water, .water, .fire, .fire, .fire])
        XCTAssertEqual(removals.map(\.comboIncrement), [1, 1, 1, 1, 1])
    }

    func testNormalizedLightTShapeUsesOneComboAndOneRemovalStep() {
        let positions: Set<GridPosition> = [
            GridPosition(row: 2, column: 1),
            GridPosition(row: 2, column: 2),
            GridPosition(row: 2, column: 3),
            GridPosition(row: 3, column: 2),
            GridPosition(row: 4, column: 2)
        ]
        let matches = MatchDetector().detect(in: gridWith(type: .light, at: positions))

        let result = ResolveResult(matches: matches)
        let removals = removalPhases(in: result)

        XCTAssertEqual(result.phases.count, 1)
        XCTAssertEqual(result.phases[0].type, .light)
        XCTAssertEqual(result.phases[0].comboIncrement, 1)
        XCTAssertEqual(result.phases[0].removedPositions, positions)
        XCTAssertEqual(removals.count, 1)
        XCTAssertEqual(removals[0].removedPositions, positions)
    }

    func testThreeDisconnectedWaterGroupsUseThreeSequentialRemovalSteps() {
        let matches = [0, 2, 4].map { row in
            MatchResult(
                type: .water,
                positions: Set((0..<3).map { GridPosition(row: row, column: $0) })
            )
        }

        let result = ResolveResult(matches: matches)
        let removals = removalPhases(in: result)

        XCTAssertEqual(result.comboCount, 3)
        XCTAssertEqual(removals.count, 3)
        XCTAssertEqual(removals.map(\.type), [.water, .water, .water])
        XCTAssertEqual(removals.map(\.comboIncrement), [1, 1, 1])
    }

    func testResolvePipelineRunsGravityAndRefillExactlyOnceAfterAllPhases() {
        let result = ResolveResult(matches: [
            makeMatch(type: .heart, group: 0),
            makeMatch(type: .fire, group: 1),
            makeMatch(type: .water, group: 2),
            makeMatch(type: .water, group: 3)
        ])
        let gravityCount = result.steps.filter {
            if case .gravity(expectedRemovedOrbCount: _) = $0 { return true }
            return false
        }.count
        let refillCount = result.steps.filter {
            if case .refill(expectedRefillCount: _) = $0 { return true }
            return false
        }.count

        XCTAssertEqual(gravityCount, 1)
        XCTAssertEqual(refillCount, 1)
        XCTAssertEqual(result.steps.count, result.matches.count + 2)
        if case .gravity(expectedRemovedOrbCount: _) = result.steps[result.matches.count] {
            // Expected: all group removals finish before the single gravity step.
        } else {
            XCTFail("Gravity must follow every ordered group removal")
        }
        if let lastStep = result.steps.last,
           case .refill(expectedRefillCount: _) = lastStep {
            // Expected: refill follows gravity exactly once.
        } else {
            XCTFail("Refill must be the final resolve step")
        }
    }

    func testResolveOrderDoesNotDependOnMatchDetectorInputOrder() {
        let ordered = [
            makeMatch(type: .water, group: 0),
            makeMatch(type: .fire, group: 1),
            makeMatch(type: .wood, group: 2),
            makeMatch(type: .dark, group: 3)
        ]
        let shuffled = [ordered[3], ordered[1], ordered[0], ordered[2]]

        XCTAssertEqual(
            ResolveResult(matches: shuffled).phases.map(\.type),
            [.water, .fire, .wood, .dark]
        )
    }

    func testSingleTypeSkyfallMatchUsesTheSameResolvePipeline() {
        let result = ResolveResult(matches: [makeMatch(type: .wood, group: 0)])

        XCTAssertEqual(result.comboCount, 1)
        XCTAssertEqual(result.removedOrbCount, 3)
        XCTAssertEqual(result.phases.map(\.type), [.wood])
        XCTAssertEqual(result.steps.count, 3)
        if case let .remove(phase) = result.steps[0] {
            XCTAssertEqual(phase.type, .wood)
            XCTAssertEqual(phase.groupCount, 1)
        } else {
            XCTFail("Skyfall match must start with its ordered remove phase")
        }
        if case .gravity(expectedRemovedOrbCount: _) = result.steps[1] {} else {
            XCTFail("Gravity step missing")
        }
        if case .refill(expectedRefillCount: _) = result.steps[2] {} else {
            XCTFail("Refill step missing")
        }
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

    func testSkyfallOneFinalizesOnceWithoutStartingAnotherCycle() {
        let outcome = simulateSkyfallFinalization(requested: 1)

        XCTAssertEqual(outcome.cycleCount, 1)
        XCTAssertEqual(outcome.nextCycleCount, 0)
        XCTAssertEqual(outcome.lifecycle.finalRefillCount, 1)
        XCTAssertEqual(outcome.lifecycle.finishCount, 1)
        XCTAssertEqual(outcome.lifecycle.state, .finished)
    }

    func testSkyfallNineteenFinalizesExactlyOnce() {
        let outcome = simulateSkyfallFinalization(requested: 19)

        XCTAssertEqual(outcome.cycleCount, 19)
        XCTAssertEqual(outcome.nextCycleCount, 18)
        XCTAssertEqual(outcome.lifecycle.finalRefillCount, 1)
        XCTAssertEqual(outcome.lifecycle.finishCount, 1)
        XCTAssertEqual(outcome.lifecycle.state, .finished)
    }

    func testSkyfallTwoAndNinetyNineUseTheSameFinalizationBoundary() {
        for requested in [2, 99] {
            let outcome = simulateSkyfallFinalization(requested: requested)
            XCTAssertEqual(outcome.cycleCount, requested)
            XCTAssertEqual(outcome.nextCycleCount, requested - 1)
            XCTAssertEqual(outcome.lifecycle.finalRefillCount, 1)
            XCTAssertEqual(outcome.lifecycle.finishCount, 1)
        }
    }

    func testDuplicateFinishResolveIsSafelyIgnored() {
        var lifecycle = ResolveLifecycle()
        lifecycle.start()
        XCTAssertTrue(lifecycle.beginFinalization())
        XCTAssertTrue(lifecycle.finish())
        XCTAssertFalse(lifecycle.finish())
        XCTAssertEqual(lifecycle.finishCount, 1)
    }

    func testStaleSkyfallCompletionIsRejectedAfterFinalizationStarts() {
        var lifecycle = ResolveLifecycle()
        lifecycle.start()
        let grid = OrbGrid()
        grid.fillAvoidingInitialMatches { OrbType.allCases.randomElement() ?? .fire }
        let IDsBeforeStaleCompletion = allOrbIDs(in: grid)
        XCTAssertTrue(lifecycle.acceptsSkyfallCompletion)
        XCTAssertTrue(lifecycle.beginFinalization())
        XCTAssertFalse(lifecycle.acceptsSkyfallCompletion)
        XCTAssertFalse(lifecycle.beginFinalization())
        XCTAssertEqual(lifecycle.finalRefillCount, 1)

        if lifecycle.acceptsSkyfallCompletion {
            _ = grid.remove([GridPosition(row: 0, column: 0)])
        }
        XCTAssertEqual(allOrbIDs(in: grid), IDsBeforeStaleCompletion)
        XCTAssertEqual(grid.emptyPositions().count, 0)
    }

    func testFinalBoardHasThirtyOccupiedCellsAndNoEmptySlots() {
        let grid = OrbGrid()
        grid.fillAvoidingInitialMatches { OrbType.allCases.randomElement() ?? .fire }

        XCTAssertEqual(grid.cells.flatMap { $0 }.compactMap { $0 }.count, 30)
        XCTAssertEqual(grid.emptyPositions().count, 0)
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

    private func removalPhases(in result: ResolveResult) -> [ResolvePhase] {
        result.steps.compactMap { step in
            guard case let .remove(phase) = step else { return nil }
            return phase
        }
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

    private func matchTestBoardTypes() -> [[OrbType]] {
        let background: [OrbType] = [.fire, .wood, .dark]
        return (0..<OrbGrid.defaultRows).map { row in
            (0..<OrbGrid.defaultColumns).map { column in
                background[(row + column) % background.count]
            }
        }
    }

    private func gridWithHeart(at positions: Set<GridPosition>) -> OrbGrid {
        gridWith(type: .heart, at: positions)
    }

    private func gridWith(type: OrbType, at positions: Set<GridPosition>) -> OrbGrid {
        var types = matchTestBoardTypes()
        for position in positions { types[position.row][position.column] = type }
        return OrbGrid(types: types)
    }

    private func boardWithHorizontalMatch(length: Int) -> [[OrbType]] {
        var types = stableBoardTypes()
        for column in 0..<length { types[4][column] = .fire }
        return types
    }

    private func allOrbIDs(in grid: OrbGrid) -> Set<UUID> {
        Set(grid.cells.flatMap { $0 }.compactMap { $0?.id })
    }

    private func simulateSkyfallFinalization(
        requested: Int
    ) -> (cycleCount: Int, nextCycleCount: Int, lifecycle: ResolveLifecycle) {
        let controller = SkyfallController()
        controller.reset(requestedCombos: requested)
        var lifecycle = ResolveLifecycle()
        lifecycle.start()
        var cycleCount = 0
        var nextCycleCount = 0

        while controller.needsAnotherCycle {
            XCTAssertTrue(controller.recordCycle(matchGroupCount: 1))
            cycleCount += 1
            if controller.needsAnotherCycle {
                nextCycleCount += 1
            } else {
                XCTAssertTrue(lifecycle.beginFinalization())
            }
        }
        XCTAssertTrue(lifecycle.finish())
        return (cycleCount, nextCycleCount, lifecycle)
    }

    private func makeMatch(type: OrbType, group: Int) -> MatchResult {
        MatchResult(
            type: type,
            positions: Set((0..<3).map { GridPosition(row: group, column: $0) })
        )
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
