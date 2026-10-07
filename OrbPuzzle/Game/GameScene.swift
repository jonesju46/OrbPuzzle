import SpriteKit
import UIKit

final class GameScene: SKScene {
    private let grid = OrbGrid()
    private let matchDetector = MatchDetector()
    private let gravityController = GravityController()
    private let refillController = RefillController()
    private let comboController = ComboController()
    private let skyfallController = SkyfallController()
    private lazy var turnController = TurnController(duration: GameSettings.defaultTurnDuration)

    private let boardNode = SKNode()
    private let boardBackground = SKShapeNode()
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let timerLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let timerTrack = SKShapeNode()
    private let timerFill = SKSpriteNode(color: .systemGreen, size: .zero)
    private var orbNodes: [UUID: OrbNode] = [:]
    private var debugLabels: [SKLabelNode] = []
    private var boardFrame = CGRect.zero
    private var cellSize = CGSize.zero
    private var gameState: GameState = .idle {
        didSet {
            updateDebugOverlay()
#if DEBUG
            if gameState == .idle { validateIdleBoard() }
#endif
        }
    }
    private var noResolveDuringTurn = GameSettings.defaultNoResolveDuringTurn
    private var requestedSkyfallCombos = GameSettings.defaultSkyfallComboCount
    private var lastUpdateTime: TimeInterval = 0
    private var forcedEndInProgress = false
    private var resolveGeneration: UInt = 0
    private var activeResolveID: UInt = 0
    private var resolveLifecycle = ResolveLifecycle()
#if DEBUG
    private var smoothedFPS = 60.0
#endif

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.055, green: 0.06, blue: 0.10, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(turnDuration: Double, noResolveDuringTurn: Bool, skyfallComboCount: Int) {
        turnController.duration = turnDuration
        self.noResolveDuringTurn = noResolveDuringTurn
        requestedSkyfallCombos = min(max(skyfallComboCount, 1), 99)
        updateDebugOverlay()
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        guard boardNode.parent == nil else { return }
        addChild(boardNode)
        setupInterface()
        createInitialBoard()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0, boardNode.parent != nil else { return }
        layoutInterface()
        layoutAllOrbs()
    }

    private func setupInterface() {
        boardBackground.fillColor = SKColor.white.withAlphaComponent(0.07)
        boardBackground.strokeColor = SKColor.white.withAlphaComponent(0.15)
        boardBackground.lineWidth = 2
        boardBackground.zPosition = -2
        boardNode.addChild(boardBackground)

        comboLabel.fontSize = 28
        comboLabel.horizontalAlignmentMode = .left
        comboLabel.text = "Combo 0"
        addChild(comboLabel)

        timerLabel.fontSize = 16
        timerLabel.horizontalAlignmentMode = .right
        addChild(timerLabel)

        timerTrack.fillColor = .white.withAlphaComponent(0.16)
        timerTrack.strokeColor = .clear
        addChild(timerTrack)
        timerFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        timerFill.zPosition = 1
        addChild(timerFill)

#if DEBUG
        for _ in 0..<6 {
            let label = SKLabelNode(fontNamed: "Menlo")
            label.fontSize = 10
            label.fontColor = .white.withAlphaComponent(0.72)
            label.horizontalAlignmentMode = .left
            label.zPosition = 100
            addChild(label)
            debugLabels.append(label)
        }
#endif
        layoutInterface()
        updateTimerUI()
    }

    private func layoutInterface() {
        let horizontalMargin = max(14, size.width * 0.035)
        let boardWidth = size.width - horizontalMargin * 2
        let calculatedCell = boardWidth / CGFloat(grid.columns)
        let boardHeight = calculatedCell * CGFloat(grid.rows)
        let boardBottom = max(44, (size.height - boardHeight) * 0.37)
        boardFrame = CGRect(x: horizontalMargin, y: boardBottom, width: boardWidth, height: boardHeight)
        cellSize = CGSize(width: calculatedCell, height: calculatedCell)
        boardBackground.path = CGPath(roundedRect: boardFrame.insetBy(dx: -5, dy: -5), cornerWidth: 14, cornerHeight: 14, transform: nil)

        let headerY = min(size.height - 44, boardFrame.maxY + 72)
        comboLabel.position = CGPoint(x: horizontalMargin, y: headerY)
        timerLabel.position = CGPoint(x: size.width - horizontalMargin, y: headerY)
        let trackFrame = CGRect(x: horizontalMargin, y: headerY - 34, width: boardWidth, height: 12)
        timerTrack.path = CGPath(roundedRect: trackFrame, cornerWidth: 6, cornerHeight: 6, transform: nil)
        timerFill.position = CGPoint(x: trackFrame.minX, y: trackFrame.midY)
        timerFill.size = CGSize(width: trackFrame.width, height: 8)

#if DEBUG
        for (index, label) in debugLabels.enumerated() {
            label.position = CGPoint(x: horizontalMargin, y: boardFrame.minY - 18 - CGFloat(index) * 12)
        }
#endif
    }

    private func createInitialBoard() {
        grid.fillAvoidingInitialMatches { OrbType.allCases.randomElement() ?? .fire }
        layoutAllOrbs(rebuild: true)
    }

    private func layoutAllOrbs(rebuild: Bool = false) {
        if rebuild {
            for node in orbNodes.values { node.removeFromParent() }
            orbNodes.removeAll(keepingCapacity: true)
        }
        guard cellSize.width > 0 else { return }
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let position = GridPosition(row: row, column: column)
                guard let orb = grid.orb(at: position) else { continue }
                let node: OrbNode
                if let existing = orbNodes[orb.id] {
                    node = existing
                } else {
                    node = OrbNode(orb: orb, diameter: min(cellSize.width, cellSize.height) * 0.82)
                    orbNodes[orb.id] = node
                    boardNode.addChild(node)
                }
                node.position = point(for: position)
            }
        }
    }

    private func point(for position: GridPosition) -> CGPoint {
        CGPoint(
            x: boardFrame.minX + (CGFloat(position.column) + 0.5) * cellSize.width,
            y: boardFrame.minY + (CGFloat(position.row) + 0.5) * cellSize.height
        )
    }

    private func gridPosition(at point: CGPoint) -> GridPosition? {
        TurnController.gridPosition(
            for: point,
            boardFrame: boardFrame,
            rows: grid.rows,
            columns: grid.columns
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState == .idle || gameState == .turnActive, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let position = gridPosition(at: location), let orb = grid.orb(at: position), let node = orbNodes[orb.id] else { return }
        gameState = .selected
        turnController.select(orbID: orb.id, at: position, touchPosition: location)
        node.zPosition = 50
        node.run(.scale(to: 1.10, duration: 0.06))
#if DEBUG
        print("[INPUT] began row=\(position.row) col=\(position.column)")
#endif
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState == .selected || gameState == .dragging,
              let touch = touches.first,
              let selectedID = turnController.selectedOrbID,
              let selectedNode = orbNodes[selectedID],
              let previousTouch = turnController.previousTouchPosition else { return }
        let location = touch.location(in: self)
        let clamped = CGPoint(
            x: min(max(location.x, boardFrame.minX.nextUp), boardFrame.maxX.nextDown),
            y: min(max(location.y, boardFrame.minY.nextUp), boardFrame.maxY.nextDown)
        )
        selectedNode.position = clamped

        let traversed = TurnController.traversedPositions(
            from: previousTouch,
            to: clamped,
            boardFrame: boardFrame,
            rows: grid.rows,
            columns: grid.columns
        )
        for destination in traversed.dropFirst() {
            guard let current = turnController.currentPosition,
                  current.isAdjacent(to: destination),
                  let displacedOrb = grid.orb(at: destination),
                  grid.swap(current, destination) else { continue }
            if !turnController.isTiming {
                turnController.beginTiming(at: lastUpdateTime)
            }
            gameState = .dragging
            let displacedNode = orbNodes[displacedOrb.id]
            displacedNode?.removeAction(forKey: "swap")
            displacedNode?.run(.move(to: point(for: current), duration: GameSettings.Tuning.swapDuration), withKey: "swap")
            turnController.advance(to: destination)
        }
        turnController.rememberTouch(clamped)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endGesture(cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endGesture(cancelled: true) }

    private func endGesture(cancelled: Bool) {
        guard gameState == .selected || gameState == .dragging else { return }
#if DEBUG
        if let position = turnController.currentPosition {
            print("[INPUT] \(cancelled ? "cancelled" : "ended") row=\(position.row) col=\(position.column)")
        } else {
            print("[INPUT] \(cancelled ? "cancelled" : "ended") outside-board")
        }
#endif
        if let id = turnController.selectedOrbID, let position = turnController.currentPosition, let node = orbNodes[id] {
            node.zPosition = 0
            node.run(.group([
                .move(to: point(for: position), duration: 0.07),
                .scale(to: 1.0, duration: 0.07)
            ]))
        }
        turnController.endGesture()
        updateTimerUI()
        if noResolveDuringTurn, turnController.isTiming {
            // Finger-up ends only this drag. The board and timer remain live until expiry.
            gameState = .turnActive
        } else if !turnController.isTiming {
            gameState = .idle
        } else {
            expireTurnSession()
        }
    }

    private func expireTurnSession() {
        guard !forcedEndInProgress else { return }
        forcedEndInProgress = true
        gameState = .resolving
        if let id = turnController.selectedOrbID,
           let position = turnController.currentPosition,
           let node = orbNodes[id] {
            node.zPosition = 0
            node.removeAllActions()
            node.position = point(for: position)
            node.setScale(1)
        }
        turnController.expireSession()
        updateTimerUI()
        resolveTurn()
    }

    private func resolveTurn() {
        resolveGeneration &+= 1
        activeResolveID = resolveGeneration
        let resolveID = activeResolveID
        resolveLifecycle.start()
        gameState = .resolving
        comboController.reset()
        skyfallController.reset(requestedCombos: requestedSkyfallCombos)
        comboLabel.text = "Combo 0"
        let initialMatches = matchDetector.detect(in: grid)
        guard !initialMatches.isEmpty else {
            finishResolution(resolveID: resolveID)
            return
        }
        process(matches: initialMatches, resolveID: resolveID)
    }

    private func process(matches: [MatchResult], resolveID: UInt) {
        guard resolveID == activeResolveID, resolveLifecycle.acceptsSkyfallCompletion else {
            logStaleCompletion("process")
            return
        }
        let resolveResult = ResolveResult(matches: matches)
        execute(resolveResult.steps, at: 0, result: resolveResult, resolveID: resolveID)
    }

    private func execute(
        _ steps: [ResolveStep],
        at index: Int,
        result: ResolveResult,
        resolveID: UInt
    ) {
        guard resolveID == activeResolveID, resolveLifecycle.acceptsSkyfallCompletion else {
            logStaleCompletion("resolve step")
            return
        }
        guard steps.indices.contains(index) else { return }

        switch steps[index] {
        case let .remove(phase):
            gameState = .removing
            let removed = grid.remove(phase.removedPositions)
#if DEBUG
            if removed.count != phase.removedOrbCount {
                print("[RESOLVE-BUG] phase=\(phase.type.rawValue) expected=\(phase.removedOrbCount) removed=\(removed.count)")
            }
#endif
            for orb in removed {
                guard let node = orbNodes[orb.id] else { continue }
                node.run(.sequence([
                    .scale(to: 1.12, duration: GameSettings.Tuning.resolveHighlightDuration),
                    .group([
                        .fadeOut(withDuration: GameSettings.Tuning.removeDuration),
                        .scale(to: 0.2, duration: GameSettings.Tuning.removeDuration)
                    ])
                ]))
            }

            let phaseDuration = GameSettings.Tuning.resolveHighlightDuration
                + GameSettings.Tuning.removeDuration
            run(after: phaseDuration) { [weak self] in
                guard let self else { return }
                guard resolveID == self.activeResolveID,
                      self.resolveLifecycle.acceptsSkyfallCompletion,
                      self.gameState == .removing else {
                    self.logStaleCompletion("remove phase")
                    return
                }
                for orb in removed {
                    self.orbNodes.removeValue(forKey: orb.id)?.removeFromParent()
                }
                self.comboController.add(phase.matches)
                self.comboController.animate(label: self.comboLabel)
#if DEBUG
                print("[RESOLVE] phase=\(phase.type.rawValue) groups=\(phase.groupCount)")
#endif
                self.run(after: GameSettings.Tuning.resolvePhaseDelay) { [weak self] in
                    self?.execute(
                        steps,
                        at: index + 1,
                        result: result,
                        resolveID: resolveID
                    )
                }
            }

        case let .gravity(expectedRemovedOrbCount: expectedRemovedOrbCount):
#if DEBUG
            let emptyCount = grid.emptyPositions().count
            if emptyCount != expectedRemovedOrbCount {
                print("[RESOLVE-BUG] gravity expected=\(expectedRemovedOrbCount) empty=\(emptyCount)")
            }
#endif
            gameState = .falling
#if DEBUG
            print("[RESOLVE] gravity removed=\(expectedRemovedOrbCount)")
#endif
            let fallDuration = gravityController.apply(
                to: grid,
                nodes: orbNodes,
                pointForPosition: { self.point(for: $0) }
            )
            run(after: fallDuration) { [weak self] in
                guard let self else { return }
                guard resolveID == self.activeResolveID,
                      self.resolveLifecycle.acceptsSkyfallCompletion,
                      self.gameState == .falling else {
                    self.logStaleCompletion("gravity")
                    return
                }
                self.execute(
                    steps,
                    at: index + 1,
                    result: result,
                    resolveID: resolveID
                )
            }

        case let .refill(expectedRefillCount: expectedRefillCount):
            refillAndContinue(expectedRefillCount: expectedRefillCount, resolveID: resolveID)
        }
    }

    private func refillAndContinue(expectedRefillCount: Int, resolveID: UInt) {
        guard resolveID == activeResolveID, resolveLifecycle.acceptsSkyfallCompletion else {
            logStaleCompletion("refill entry")
            return
        }
        gameState = .refilling
        // Always query after gravity; never reuse slots captured by an older cycle.
        let refillSlots = grid.emptyPositions()
        guard refillSlots.count == expectedRefillCount else {
#if DEBUG
            print("[REFILL-BUG] expected=\(expectedRefillCount) slots=\(refillSlots.count)")
#endif
            finishResolution(resolveID: resolveID)
            return
        }

        // Try a controlled refill only while quota remains. If the preserved
        // board already contains a gravity-created match, controlled planning
        // cannot prove exactly one group and safely falls back to a normal slot
        // refill. Actual resolve detection happens only after fall completion.
        let controlledTypes = skyfallController.needsAnotherCycle
            ? skyfallController.makeControlledRefill(grid: grid, refillSlots: refillSlots)
            : nil
        let isControlledSkyfallRefill = controlledTypes != nil
        let isNaturalChainRefill = skyfallController.needsAnotherCycle
            && controlledTypes == nil
        let isFinalRefill = !skyfallController.needsAnotherCycle

#if DEBUG
        let cycleNumber = skyfallController.generatedCombos + 1
        if isControlledSkyfallRefill {
            print("[SKYFALL] cycle \(cycleNumber)/\(skyfallController.requestedCombos) begin")
        } else if isNaturalChainRefill {
            print("[MATCH] safe chain refill before stable-board scan")
        } else {
            print("[REFILL] final begin slots=\(refillSlots.count)")
        }
#endif
        let plannedTypes = controlledTypes
            ?? skyfallController.makeSafeRefill(grid: grid, refillSlots: refillSlots)
        guard let plannedTypes, plannedTypes.count == refillSlots.count else {
#if DEBUG
            print("[REFILL-BUG] unable to plan slot-only refill slots=\(refillSlots.count)")
#endif
            finishResolution(resolveID: resolveID)
            return
        }

        let preservedCount = orbNodes.count
        let result = refillController.refillEmptySlots(
            grid: grid,
            slots: refillSlots,
            types: plannedTypes,
            boardNode: boardNode,
            cellSize: cellSize,
            pointForPosition: { [weak self] position in
                self?.point(for: position) ?? .zero
            }
        )
#if DEBUG
        if result.spawns.count != expectedRefillCount {
            print("[REFILL-BUG] expected=\(expectedRefillCount) new=\(result.spawns.count)")
        }
#endif
        for node in result.nodes { orbNodes[node.orbID] = node }
#if DEBUG
        print("[SKYFALL] removed=\(expectedRefillCount) existingPreserved=\(preservedCount) newOrbs=\(result.spawns.count)")
#endif
        run(after: result.duration) { [weak self] in
            guard let self else { return }
            guard resolveID == self.activeResolveID,
                  self.gameState == .refilling else {
                self.logStaleCompletion("refill animation")
                return
            }
            let stableBoard = StableBoardScan(matches: self.matchDetector.detect(in: self.grid))
            let matches = stableBoard.matches

            if isControlledSkyfallRefill {
                guard self.resolveLifecycle.acceptsSkyfallCompletion else {
                    self.logStaleCompletion("skyfall cycle")
                    return
                }
                self.gameState = .skyfall
                if matches.count == 1,
                   matches[0].matchSize == 3,
                   self.skyfallController.recordCycle(matchGroupCount: matches.count) {
#if DEBUG
                    print("[SKYFALL] cycle \(self.skyfallController.generatedCombos)/\(self.skyfallController.requestedCombos) complete")
#endif
                } else {
#if DEBUG
                    print("[SKYFALL-BUG] controlled refill groups=\(matches.count); resolving detected board without skipping matches")
#endif
                }
            }

            // Every refill path ends at the same stable-board full-grid scan.
            // Never finish while MatchDetector still reports a 3+ group.
            if !stableBoard.canFinishResolve {
                self.process(matches: matches, resolveID: resolveID)
                return
            }

            if isControlledSkyfallRefill {
#if DEBUG
                print("[SKYFALL-BUG] controlled refill produced no match")
#endif
                self.finishResolution(resolveID: resolveID)
                return
            }

            guard isFinalRefill || !self.skyfallController.needsAnotherCycle else {
#if DEBUG
                print("[MATCH-BUG] natural chain disappeared before full-board scan")
#endif
                self.finishResolution(resolveID: resolveID)
                return
            }
            guard self.resolveLifecycle.beginFinalization() else {
                self.logStaleCompletion("duplicate finalization")
                return
            }
#if DEBUG
            print("[SKYFALL] entering finalization")
            print("[REFILL] final complete new=\(result.spawns.count)")
#endif
            self.finishResolution(resolveID: resolveID)
        }
    }

    private func finishResolution(resolveID: UInt) {
        guard resolveID == activeResolveID else {
            logStaleCompletion("finish")
            return
        }
        let stableBoard = StableBoardScan(matches: matchDetector.detect(in: grid))
        guard stableBoard.canFinishResolve else {
#if DEBUG
            print("[MATCH-BUG] finish requested with matches count=\(stableBoard.matches.count); continuing resolve")
#endif
            process(matches: stableBoard.matches, resolveID: resolveID)
            return
        }
        guard resolveLifecycle.finish() else {
#if DEBUG
            print("[RESOLVE] duplicate finish ignored")
#endif
            return
        }
#if DEBUG
        print("[RESOLVE] finish begin")
        validateFinalBoard()
#endif
        forcedEndInProgress = false
        turnController.resetSession()
        gameState = .completed
        updateTimerUI()
#if DEBUG
        print("[RESOLVE] finish complete")
#endif
        run(after: 0.12) { [weak self] in
            guard let self else { return }
            guard resolveID == self.activeResolveID,
                  self.resolveLifecycle.state == .finished,
                  self.gameState == .completed else {
                self.logStaleCompletion("idle transition")
                return
            }
            self.gameState = .idle
#if DEBUG
            print("[STATE] -> idle")
#endif
        }
    }

    private func logStaleCompletion(_ source: String) {
#if DEBUG
        print("[SKYFALL] stale completion ignored source=\(source)")
#endif
    }

#if DEBUG
    private func validateIdleBoard() {
        let matches = matchDetector.detect(in: grid)
        if !matches.isEmpty {
            print("[MATCH-BUG] idle board still contains matches count=\(matches.count)")
        }
    }

    private func validateFinalBoard() {
        let gridOrbs = grid.cells.flatMap { $0 }.compactMap { $0 }
        let gridIDs = Set(gridOrbs.map(\.id))
        let nodeIDs = Set(orbNodes.keys)
        let occupiedCount = gridOrbs.count
        let emptyCount = grid.emptyPositions().count
        if occupiedCount == 30,
           orbNodes.count == 30,
           emptyCount == 0,
           gridIDs == nodeIDs {
            print("[FINAL] grid=\(occupiedCount) nodes=\(orbNodes.count) empty=\(emptyCount)")
        } else {
            print("[FINAL-BUG] grid=\(occupiedCount) nodes=\(orbNodes.count) empty=\(emptyCount) missingNodes=\(gridIDs.subtracting(nodeIDs).count) orphanNodes=\(nodeIDs.subtracting(gridIDs).count)")
        }
    }
#endif

    private func run(after delay: TimeInterval, completion: @escaping () -> Void) {
        if delay <= 0 { completion(); return }
        run(.sequence([.wait(forDuration: delay), .run(completion)]))
    }

    override func update(_ currentTime: TimeInterval) {
#if DEBUG
        if lastUpdateTime > 0 {
            let delta = max(currentTime - lastUpdateTime, 0.000_1)
            smoothedFPS = smoothedFPS * 0.9 + (1 / delta) * 0.1
        }
#endif
        lastUpdateTime = currentTime
        if turnController.isTiming, turnController.update(at: currentTime) {
            expireTurnSession()
        }
        updateTimerUI()
        updateDebugOverlay()
    }

    private func updateTimerUI() {
        let remaining = turnController.remainingTime
        timerLabel.text = String(format: "Turn Time  %.1fs", remaining)
        let availableWidth = max(boardFrame.width, 0)
        timerFill.size.width = availableWidth * CGFloat(turnController.progress)
        let ratio = turnController.progress
        timerFill.color = ratio > 0.5 ? .systemGreen : (ratio > 0.2 ? .systemOrange : .systemRed)
    }

    private func updateDebugOverlay() {
#if DEBUG
        guard debugLabels.count == 6 else { return }
        debugLabels[0].text = String(format: "FPS %.0f", smoothedFPS)
        debugLabels[1].text = "State \(gameState.rawValue)"
        debugLabels[2].text = String(format: "Time %.1f", turnController.remainingTime)
        debugLabels[3].text = "Combo \(comboController.comboCount)"
        debugLabels[4].text = "Skyfall \(skyfallController.generatedCombos)/\(requestedSkyfallCombos)"
        debugLabels[5].text = noResolveDuringTurn ? "No Resolve ON" : "No Resolve OFF"
#endif
    }
}
