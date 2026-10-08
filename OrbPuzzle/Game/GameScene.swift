import SpriteKit
import UIKit

final class GameScene: SKScene {
    private let grid = OrbGrid()
    private let matchDetector = MatchDetector()
    private let gravityController = GravityController()
    private let refillController = RefillController()
    private let comboController = ComboController()
    private let skyfallController = SkyfallController()
    private var sessionStatistics = SessionStatistics()
    private lazy var turnController = TurnController(duration: GameSettings.effectiveTurnDuration(
        enabled: GameSettings.defaultTurnTimeEnabled,
        configured: GameSettings.defaultTurnDuration
    ))

    private let boardNode = SKNode()
    private let boardBackground = SKShapeNode()
    private let comboLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let timerLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let timerTrack = SKShapeNode()
    private let timerFill = SKSpriteNode(color: .systemGreen, size: .zero)
    private var orbNodes: [UUID: OrbNode] = [:]
    private var debugLabels: [SKLabelNode] = []
    private var orbTypeDebugLabels: [SKLabelNode] = []
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
    private var requestedSkyfallCombos = GameSettings.effectiveSkyfallComboCount(
        enabled: GameSettings.defaultSkyfallComboEnabled,
        configured: GameSettings.defaultSkyfallComboCount
    )
    private var lastUpdateTime: TimeInterval = 0
    private var forcedEndInProgress = false
    private var gameSessionFence = GameSessionFence()
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
        requestedSkyfallCombos = min(max(skyfallComboCount, 0), 99)
        updateDebugOverlay()
    }

    var sessionSnapshot: GameSessionSnapshot {
        GameSessionSnapshot(
            sessionID: gameSessionFence.id,
            orbIDs: Set(grid.cells.flatMap { $0 }.compactMap { $0?.id }),
            state: gameState,
            comboCount: comboController.comboCount,
            generatedSkyfall: skyfallController.generatedCombos,
            requestedSkyfall: requestedSkyfallCombos,
            remainingTime: turnController.remainingTime,
            progress: turnController.progress,
            resolveID: activeResolveID,
            resolveLifecycleState: resolveLifecycle.state,
            completedTurnCount: sessionStatistics.completedTurnCount,
            averageTurnTime: sessionStatistics.averageTurnTime,
            averageTotalCombo: sessionStatistics.averageTotalCombo
        )
    }

    /// Starts a genuinely new session even when SwiftUI retains this scene.
    func startNewGame() {
        let oldOrbIDs = sessionSnapshot.orbIDs
        gameSessionFence.beginNewSession()

        // Invalidate resolve IDs before removing actions so an already-delivered
        // completion cannot mutate the replacement board.
        resolveGeneration &+= 1
        activeResolveID = resolveGeneration
        removeAllActions()
        boardNode.removeAllActions()
        comboLabel.removeAllActions()
        timerLabel.removeAllActions()
        timerTrack.removeAllActions()
        timerFill.removeAllActions()
        for node in orbNodes.values {
            node.removeAllActions()
            node.removeFromParent()
        }
        orbNodes.removeAll(keepingCapacity: true)

        forcedEndInProgress = false
        resolveLifecycle = ResolveLifecycle()
        comboController.reset()
        skyfallController.reset(requestedCombos: requestedSkyfallCombos)
        sessionStatistics.reset()
        turnController.resetSession()
        comboLabel.text = "Combo 0"
        comboLabel.alpha = 1
        comboLabel.setScale(1)

        grid.fillAvoidingInitialMatches { OrbType.allCases.randomElement() ?? .fire }
        layoutAllOrbs(rebuild: true)
        gameState = .idle
        updateTimerUI()
        updateDebugOverlay()

#if DEBUG
        let newOrbIDs = sessionSnapshot.orbIDs
        assert(newOrbIDs.count == OrbGrid.defaultRows * OrbGrid.defaultColumns)
        assert(oldOrbIDs.isDisjoint(with: newOrbIDs))
        assert(matchDetector.detect(in: grid).isEmpty)
#endif
    }

    override func didMove(to view: SKView) {
        view.preferredFramesPerSecond = 60
        guard boardNode.parent == nil else { return }
        addChild(boardNode)
        setupInterface()
        // startNewGame may run from SwiftUI onAppear just before SpriteKit attaches.
        // In that ordering the models already exist and only their nodes need layout.
        layoutAllOrbs(rebuild: true)
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
        for _ in 0..<5 {
            let label = SKLabelNode(fontNamed: "Menlo")
            label.fontSize = 10
            label.fontColor = .white.withAlphaComponent(0.72)
            label.horizontalAlignmentMode = .left
            label.zPosition = 100
            addChild(label)
            debugLabels.append(label)
        }
        for _ in OrbType.resolveOrder {
            let label = SKLabelNode(fontNamed: "Menlo")
            label.fontSize = 10
            label.fontColor = .white.withAlphaComponent(0.72)
            label.horizontalAlignmentMode = .left
            label.zPosition = 100
            addChild(label)
            orbTypeDebugLabels.append(label)
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
        let rightColumnX = horizontalMargin + boardWidth * 0.52
        for (index, label) in orbTypeDebugLabels.enumerated() {
            label.position = CGPoint(x: rightColumnX, y: boardFrame.minY - 18 - CGFloat(index) * 12)
        }
#endif
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
                resetComboDisplay()
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
            finishTurnSession(timerExpired: false)
        }
    }

    private func finishTurnSession(timerExpired: Bool) {
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
        if timerExpired {
            turnController.expireSession()
        } else {
            turnController.completeSession()
        }
        updateTimerUI()
        updateDebugOverlay()
        resolveTurn()
    }

    private func resolveTurn() {
        resolveGeneration &+= 1
        activeResolveID = resolveGeneration
        let resolveID = activeResolveID
        resolveLifecycle.start()
        gameState = .resolving
        skyfallController.reset(requestedCombos: requestedSkyfallCombos)
        let initialMatches = matchDetector.detect(in: grid)
        guard !initialMatches.isEmpty else {
            finishResolution(resolveID: resolveID)
            return
        }
        process(matches: initialMatches, source: .manual, resolveID: resolveID)
    }

    private func process(matches: [MatchResult], source: ComboSource, resolveID: UInt) {
        guard resolveID == activeResolveID, resolveLifecycle.acceptsSkyfallCompletion else {
            logStaleCompletion("process")
            return
        }
        let resolveResult = ResolveResult(matches: matches)
        execute(
            resolveResult.steps,
            at: 0,
            result: resolveResult,
            source: source,
            resolveID: resolveID
        )
    }

    private func execute(
        _ steps: [ResolveStep],
        at index: Int,
        result: ResolveResult,
        source: ComboSource,
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
            let comboNumber = comboController.add(
                type: phase.type,
                groups: phase.comboIncrement,
                source: source
            )
            comboController.animate(label: comboLabel)
            updateDebugOverlay()
            GameAudioManager.shared.playComboSound(comboNumber: comboNumber)
            let removed = grid.remove(phase.removedPositions)
#if DEBUG
            if removed.count != phase.removedOrbCount {
                print("[RESOLVE-BUG] phase=\(phase.type.rawValue) expected=\(phase.removedOrbCount) removed=\(removed.count)")
            }
#endif
            animateRemovalGroup(removed) { [weak self] in
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
#if DEBUG
                print("[RESOLVE] group=\(phase.type.rawValue) orbs=\(phase.removedOrbCount)")
#endif
                self.run(after: GameSettings.Tuning.resolvePhaseDelay) { [weak self] in
                    self?.execute(
                        steps,
                        at: index + 1,
                        result: result,
                        source: source,
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
                    source: source,
                    resolveID: resolveID
                )
            }

        case let .refill(expectedRefillCount: expectedRefillCount):
            refillAndContinue(
                expectedRefillCount: expectedRefillCount,
                previousResolvedGroupCount: result.comboCount,
                resolveID: resolveID
            )
        }
    }

    /// A normalized connected match is one combo. Its orbs animate together,
    /// then the pipeline advances to the next group in attribute order.
    private func animateRemovalGroup(_ removed: [Orb], completion: @escaping () -> Void) {
        let nodes = removed.compactMap { orbNodes[$0.id] }
        guard !nodes.isEmpty else {
            completion()
            return
        }

        let sessionID = gameSessionFence.id
        let action = SKAction.sequence([
            .scale(to: 1.12, duration: GameSettings.Tuning.resolveHighlightDuration),
            .group([
                .fadeOut(withDuration: GameSettings.Tuning.removeDuration),
                .scale(to: 0.2, duration: GameSettings.Tuning.removeDuration)
            ])
        ])
        var remainingNodeCount = nodes.count
        for node in nodes {
            node.run(action) { [weak self] in
                guard let self, self.gameSessionFence.accepts(sessionID) else { return }
                remainingNodeCount -= 1
                if remainingNodeCount == 0 { completion() }
            }
        }
    }

    private func refillAndContinue(
        expectedRefillCount: Int,
        previousResolvedGroupCount: Int,
        resolveID: UInt
    ) {
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

        // ON uses its unchanged exact-total planner. OFF derives this refill's
        // candidate count from the previous snapshot's actual resolved groups.
        let controlledTypes = skyfallController.hasControlledTarget
            && skyfallController.needsAnotherCycle
            ? skyfallController.makeControlledRefill(grid: grid, refillSlots: refillSlots)
            : nil
        let isControlledSkyfallRefill = controlledTypes != nil
        let friendlyDecision = skyfallController.selectFriendlyRefillTarget(
            previousResolvedGroupCount: previousResolvedGroupCount,
            emptySlotCount: refillSlots.count
        )
        let friendlyPlan: FriendlyRefillPlan?
        if let selectedTarget = friendlyDecision?.selectedTarget {
            friendlyPlan = skyfallController.makeFriendlyNaturalRefill(
                grid: grid,
                refillSlots: refillSlots,
                targetGroupCount: selectedTarget
            )
        } else {
            friendlyPlan = nil
        }
        let isFriendlyNaturalRefill = friendlyPlan != nil
        let isSafeRefill = !isControlledSkyfallRefill && !isFriendlyNaturalRefill

#if DEBUG
        if isControlledSkyfallRefill {
            print("[SKYFALL] controlled batch begin progress=\(skyfallController.generatedCombos)/\(skyfallController.requestedCombos) slots=\(refillSlots.count)")
        } else if isFriendlyNaturalRefill {
            print("[SKYFALL] friendly natural begin next=\(skyfallController.generatedCombos + 1) slots=\(refillSlots.count)")
        } else {
            print("[REFILL] safe final begin slots=\(refillSlots.count)")
        }
        if let friendlyDecision {
            print("[FRIENDLY_REFILL] previousGroups=\(friendlyDecision.previousResolvedGroupCount) emptySlots=\(friendlyDecision.emptySlotCount) physicalMax=\(friendlyDecision.physicalMaxGroups) candidateMax=\(friendlyDecision.candidateMaxGroups)")
            for attempt in friendlyDecision.rolls {
                if let roll = attempt.roll {
                    print(String(format: "[FRIENDLY_REFILL] roll%d=%.4f probability=%.2f success=%@", attempt.groupCount, roll, attempt.probability, attempt.succeeded.description))
                } else {
                    print("[FRIENDLY_REFILL] roll\(attempt.groupCount)=guaranteed probability=\(attempt.probability) success=true")
                }
            }
            print("[FRIENDLY_REFILL] selectedTarget=\(friendlyDecision.selectedTarget.map { String($0) } ?? "none") plannedTarget=\(friendlyPlan?.plannedTarget.description ?? "none") actualResolved=\(previousResolvedGroupCount)")
        }
#endif
        let plannedTypes: [OrbType]?
        if skyfallController.hasControlledTarget {
            // Natural and controlled groups share the exact ON target. Once the
            // total reaches it, safe refill prevents an active target + 1 group.
            plannedTypes = controlledTypes
                ?? skyfallController.makeSafeRefill(grid: grid, refillSlots: refillSlots)
        } else if let friendlyPlan {
            plannedTypes = friendlyPlan.types
        } else {
            // One-or-fewer previous groups, insufficient slots, or a planning
            // failure uses non-forced refill. Existing natural matches remain.
            plannedTypes = skyfallController.makeSafeRefill(grid: grid, refillSlots: refillSlots)
        }
        guard let plannedTypes, plannedTypes.count == refillSlots.count else {
#if DEBUG
            print("[REFILL-BUG] unable to plan slot-only refill slots=\(refillSlots.count)")
#endif
            finishResolution(resolveID: resolveID)
            return
        }
#if DEBUG
        let refillMode = isControlledSkyfallRefill
            ? "controlled"
            : (isFriendlyNaturalRefill ? "friendly-natural" : "safe")
        let typeSummary = OrbType.allCases.map { type in
            "\(type.displayName)=\(plannedTypes.filter { $0 == type }.count)"
        }.joined(separator: " ")
        print("[REFILL] mode=\(refillMode) count=\(plannedTypes.count) \(typeSummary)")
#endif

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

            if isControlledSkyfallRefill || isFriendlyNaturalRefill {
                guard self.resolveLifecycle.acceptsSkyfallCompletion else {
                    self.logStaleCompletion("skyfall cycle")
                    return
                }
                self.gameState = .skyfall
            }

            // Initial/manual matches are processed before the first refill and
            // never enter this counter. Every post-refill full-board detection,
            // controlled or natural, contributes its actual normalized groups.
            if self.skyfallController.recordDetectedGroups(matches.count) {
#if DEBUG
                let source = isControlledSkyfallRefill
                    ? "controlled"
                    : (isFriendlyNaturalRefill ? "friendly-natural" : "natural")
                print("[SKYFALL] \(source) groups=\(matches.count) total=\(self.skyfallController.generatedCombos) target=\(self.skyfallController.requestedCombos)")
#endif
            }
#if DEBUG
            if friendlyDecision != nil {
                print("[FRIENDLY_REFILL] actualDetected=\(matches.count)")
            }
            if isSafeRefill {
                print("[NATURAL] detected groups=\(matches.count) cumulative=\(self.skyfallController.generatedCombos)")
            }
#endif

            // Every refill path ends at the same stable-board full-grid scan.
            // Never finish while MatchDetector still reports a 3+ group.
            if !stableBoard.canFinishResolve {
                self.process(matches: matches, source: .skyfall, resolveID: resolveID)
                return
            }

            if isControlledSkyfallRefill || isFriendlyNaturalRefill {
#if DEBUG
                print("[SKYFALL-BUG] match-producing refill produced no match")
#endif
                self.finishResolution(resolveID: resolveID)
                return
            }

            guard !self.skyfallController.hasControlledTarget
                    || !self.skyfallController.needsAnotherCycle else {
#if DEBUG
                print("[MATCH-BUG] controlled target stalled before full-board scan")
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
            process(matches: stableBoard.matches, source: .skyfall, resolveID: resolveID)
            return
        }
        guard resolveLifecycle.finish() else {
#if DEBUG
            print("[RESOLVE] duplicate finish ignored")
#endif
            return
        }
        if let finalTurnMoveTime = turnController.lastCompletedTurnTime {
            sessionStatistics.commitCompletedTurn(
                resolveID: resolveID,
                moveTime: finalTurnMoveTime,
                totalCombo: comboController.comboCount,
                comboTotalByType: comboController.comboTotalByType
            )
        }
#if DEBUG
        print("[RESOLVE] finish begin")
        validateFinalBoard()
#endif
        forcedEndInProgress = false
        turnController.prepareNextSession()
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
        let sessionID = gameSessionFence.id
        let guardedCompletion = { [weak self] in
            guard let self, self.gameSessionFence.accepts(sessionID) else {
                self?.logStaleCompletion("game session")
                return
            }
            completion()
        }
        if delay <= 0 { guardedCompletion(); return }
        run(.sequence([.wait(forDuration: delay), .run(guardedCompletion)]))
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
            finishTurnSession(timerExpired: true)
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

    private func resetComboDisplay() {
        comboController.reset()
        comboLabel.removeAllActions()
        comboLabel.text = "Combo 0"
        comboLabel.alpha = 1
        comboLabel.setScale(1)
        updateDebugOverlay()
    }

    private func updateDebugOverlay() {
#if DEBUG
        guard debugLabels.count == 5,
              orbTypeDebugLabels.count == OrbType.resolveOrder.count else { return }
        debugLabels[0].text = String(format: "FPS %.0f", smoothedFPS)
        debugLabels[1].text = "State \(gameState.rawValue)"
        debugLabels[2].text = GameplayStatusHUDText.time(
            current: turnController.displayedElapsedTurnTime,
            average: sessionStatistics.averageTurnTime
        )
        debugLabels[3].text = GameplayStatusHUDText.combo(
            currentBreakdown: comboController.breakdownText,
            average: sessionStatistics.averageTotalCombo
        )
        debugLabels[4].text = noResolveDuringTurn ? "No Resolve ON" : "No Resolve OFF"
        for (index, type) in OrbType.resolveOrder.enumerated() {
            orbTypeDebugLabels[index].text = GameplayStatusHUDText.orbType(
                currentBreakdown: comboController.breakdownText(for: type),
                average: sessionStatistics.averageCombo(for: type)
            )
        }
#endif
    }
}
