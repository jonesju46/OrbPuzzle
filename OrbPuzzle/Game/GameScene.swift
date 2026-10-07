import SpriteKit
import UIKit

final class GameScene: SKScene {
    private let grid = OrbGrid()
    private let matchDetector = MatchDetector()
    private let gravityController = GravityController()
    private let refillController = RefillController()
    private let comboController = ComboController()
    private lazy var turnController = TurnController(duration: GameSettings.defaultTurnDuration)
    private lazy var cascadeController = CascadeController(maximumRounds: GameSettings.defaultCascadeRounds)

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
    private var gameState: GameState = .idle { didSet { updateDebugOverlay() } }
    private var dropMode: DropMode = .normal
    private var configuredCascadeRounds = GameSettings.defaultCascadeRounds
    private var lastUpdateTime: TimeInterval = 0
    private var forcedEndInProgress = false
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

    func configure(turnDuration: Double, cascadeRounds: Int, dropMode: DropMode) {
        turnController.duration = turnDuration
        configuredCascadeRounds = min(max(cascadeRounds, 1), 99)
        self.dropMode = dropMode
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
        comboLabel.text = "0 Combo"
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
        guard boardFrame.contains(point) else { return nil }
        return GridPosition(
            row: min(Int((point.y - boardFrame.minY) / cellSize.height), grid.rows - 1),
            column: min(Int((point.x - boardFrame.minX) / cellSize.width), grid.columns - 1)
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState == .idle, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let position = gridPosition(at: location), let orb = grid.orb(at: position), let node = orbNodes[orb.id] else { return }
        gameState = .selected
        turnController.select(orbID: orb.id, at: position, touchPosition: location)
        node.zPosition = 50
        node.run(.scale(to: 1.10, duration: 0.06))
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
                gameState = .dragging
            }
            let displacedNode = orbNodes[displacedOrb.id]
            displacedNode?.removeAction(forKey: "swap")
            displacedNode?.run(.move(to: point(for: current), duration: GameSettings.Tuning.swapDuration), withKey: "swap")
            turnController.advance(to: destination)
        }
        turnController.rememberTouch(clamped)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTurn() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTurn() }

    private func endTurn() {
        guard gameState == .selected || gameState == .dragging else { return }
        let hadMovement = turnController.isTiming
        if let id = turnController.selectedOrbID, let position = turnController.currentPosition, let node = orbNodes[id] {
            node.zPosition = 0
            node.run(.group([
                .move(to: point(for: position), duration: 0.07),
                .scale(to: 1.0, duration: 0.07)
            ]))
        }
        turnController.finish()
        forcedEndInProgress = false
        updateTimerUI()
        if hadMovement {
            resolveTurn()
        } else {
            gameState = .idle
        }
    }

    private func resolveTurn() {
        gameState = .resolving
        comboController.reset()
        cascadeController.reset(maximumRounds: configuredCascadeRounds)
        comboLabel.text = "0 Combo"
        let initialMatches = matchDetector.detect(in: grid)
        guard !initialMatches.isEmpty else {
            gameState = .idle
            return
        }
        process(matches: initialMatches)
    }

    private func process(matches: [MatchResult]) {
        gameState = .removing
        comboController.add(matches)
        comboController.animate(label: comboLabel)
        let positions = matches.reduce(into: Set<GridPosition>()) { $0.formUnion($1.positions) }
        let removed = grid.remove(positions)
        for orb in removed {
            guard let node = orbNodes[orb.id] else { continue }
            node.run(.group([
                .fadeOut(withDuration: GameSettings.Tuning.removeDuration),
                .scale(to: 0.2, duration: GameSettings.Tuning.removeDuration)
            ]))
        }

        run(after: GameSettings.Tuning.removeDuration) { [weak self] in
            guard let self else { return }
            for orb in removed {
                self.orbNodes.removeValue(forKey: orb.id)?.removeFromParent()
            }
            self.gameState = .falling
            let fallDuration = self.gravityController.apply(
                to: self.grid,
                nodes: self.orbNodes,
                pointForPosition: { self.point(for: $0) }
            )
            self.run(after: fallDuration) { [weak self] in self?.refillAndContinue() }
        }
    }

    private func refillAndContinue() {
        gameState = .refilling
        let result = refillController.refill(
            grid: grid,
            mode: dropMode,
            boardNode: boardNode,
            cellSize: cellSize,
            pointForPosition: { [weak self] position in
                self?.point(for: position) ?? .zero
            }
        )
        for node in result.nodes { orbNodes[node.orbID] = node }
        run(after: result.duration) { [weak self] in
            guard let self else { return }
            guard self.cascadeController.beginNextRound() else {
                self.gameState = .idle
                return
            }
            self.gameState = .cascading
            let matches = self.matchDetector.detect(in: self.grid)
            guard !matches.isEmpty else {
                self.gameState = .idle
                return
            }
            self.process(matches: matches)
        }
    }

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
        if gameState == .dragging, turnController.update(at: currentTime) {
            if !forcedEndInProgress {
                forcedEndInProgress = true
                endTurn()
            }
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
        debugLabels[4].text = "Cascade \(cascadeController.completedRounds)/\(configuredCascadeRounds)"
        debugLabels[5].text = "Drop \(dropMode.title)"
#endif
    }
}
