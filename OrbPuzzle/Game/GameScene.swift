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
    private var battleSession = BattleSession(config: .default)
    private var lastDisplayedAttack = 0
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
    private let monsterArea = SKShapeNode()
    private let monsterPlaceholder = SKShapeNode()
    private let monsterPlaceholderLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let monsterTitleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let monsterHPLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let monsterCDLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let battleStatusLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let monsterHPTrack = SKShapeNode()
    private let monsterHPFill = SKSpriteNode(color: .systemRed, size: .zero)
    private let playerHPLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let playerAttackLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let playerHPTrack = SKShapeNode()
    private let playerHPFill = SKSpriteNode(color: .systemGreen, size: .zero)
    private let monsterDamageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let playerFeedbackLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var cardNodes: [SKShapeNode] = []
    private var cardAttributeLabels: [SKLabelNode] = []
    private var cardAttackLabels: [SKLabelNode] = []
    private var cardHealLabels: [SKLabelNode] = []
    private var cardDamageLabels: [SKLabelNode] = []
    private var monsterHPBarFrame = CGRect.zero
    private var playerHPBarFrame = CGRect.zero
    private var orbNodes: [UUID: OrbNode] = [:]
    private var debugLabels: [SKLabelNode] = []
    private var orbTypeDebugLabels: [SKLabelNode] = []
#if DEBUG
    private var friendlyDebugPreparation: FriendlyRefillPreparation?
    private var friendlyDebugDetectedGroups: Int?
    private var friendlyDebugStatistics: [Int: FriendlyRefillDebugStatistics] = [:]
    private var friendlyTargetStatistics: [Int: FriendlyTargetDebugStatistics] = [:]
#endif
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
            averageTotalCombo: sessionStatistics.averageTotalCombo,
            averageManualCombo: sessionStatistics.averageManualCombo,
            averageSkyfallCombo: sessionStatistics.averageSkyfallCombo
        )
    }

    var battleStateSnapshot: BattleState { battleSession.state }
    var battleConfigSnapshot: BattleConfig { battleSession.config }

    /// Starts a genuinely new session even when SwiftUI retains this scene.
    func startNewGame(battleConfig: BattleConfig = .default) {
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
        monsterDamageLabel.removeAllActions()
        playerFeedbackLabel.removeAllActions()
        for label in cardDamageLabels { label.removeAllActions() }
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
        battleSession = BattleSession(config: battleConfig)
        lastDisplayedAttack = 0
#if DEBUG
        friendlyDebugPreparation = nil
        friendlyDebugDetectedGroups = nil
#endif
        turnController.resetSession()
        comboLabel.text = "Combo 0"
        comboLabel.alpha = 1
        comboLabel.setScale(1)
        monsterDamageLabel.text = nil
        monsterDamageLabel.alpha = 0
        playerFeedbackLabel.text = nil
        playerFeedbackLabel.alpha = 0

        grid.fillBalancedInitialBoard()
        layoutAllOrbs(rebuild: true)
        gameState = .idle
        updateTimerUI()
        updateBattleUI()
        updateCardUI()
        updateDebugOverlay()

#if DEBUG
        let newOrbIDs = sessionSnapshot.orbIDs
        assert(newOrbIDs.count == OrbGrid.defaultRows * OrbGrid.defaultColumns)
        assert(oldOrbIDs.isDisjoint(with: newOrbIDs))
        assert(matchDetector.detect(in: grid).isEmpty)
#endif
    }

    override func didMove(to view: SKView) {
        GameAudioManager.shared.preload()
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

        setupBattleInterface()

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
        updateCardUI()
    }

    private func setupBattleInterface() {
        monsterArea.fillColor = SKColor.white.withAlphaComponent(0.055)
        monsterArea.strokeColor = SKColor.white.withAlphaComponent(0.16)
        monsterArea.lineWidth = 1
        monsterArea.zPosition = 1
        addChild(monsterArea)

        monsterPlaceholder.fillColor = SKColor.systemIndigo.withAlphaComponent(0.85)
        monsterPlaceholder.strokeColor = SKColor.white.withAlphaComponent(0.55)
        monsterPlaceholder.lineWidth = 1.5
        monsterPlaceholder.zPosition = 2
        addChild(monsterPlaceholder)

        monsterPlaceholderLabel.text = "M"
        monsterPlaceholderLabel.fontSize = 18
        monsterPlaceholderLabel.verticalAlignmentMode = .center
        monsterPlaceholderLabel.zPosition = 3
        addChild(monsterPlaceholderLabel)

        for label in [monsterTitleLabel, monsterHPLabel, monsterCDLabel, battleStatusLabel, playerHPLabel] {
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .center
            label.fontColor = .white
            label.zPosition = 3
            addChild(label)
        }
        monsterTitleLabel.fontSize = 13
        monsterHPLabel.fontSize = 10
        monsterCDLabel.fontSize = 11
        monsterCDLabel.horizontalAlignmentMode = .right
        battleStatusLabel.fontSize = 11
        battleStatusLabel.horizontalAlignmentMode = .center
        playerHPLabel.fontSize = 11
        playerAttackLabel.fontSize = 11
        playerAttackLabel.fontColor = .white
        playerAttackLabel.horizontalAlignmentMode = .right
        playerAttackLabel.verticalAlignmentMode = .center
        playerAttackLabel.zPosition = 3
        playerAttackLabel.text = "ATK 0"
        addChild(playerAttackLabel)

        for track in [monsterHPTrack, playerHPTrack] {
            track.fillColor = SKColor.white.withAlphaComponent(0.16)
            track.strokeColor = .clear
            track.zPosition = 2
            addChild(track)
        }
        for fill in [monsterHPFill, playerHPFill] {
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.zPosition = 3
            addChild(fill)
        }

        monsterDamageLabel.fontSize = 15
        monsterDamageLabel.fontColor = .systemYellow
        monsterDamageLabel.horizontalAlignmentMode = .center
        monsterDamageLabel.zPosition = 20
        addChild(monsterDamageLabel)
        playerFeedbackLabel.fontSize = 12
        playerFeedbackLabel.horizontalAlignmentMode = .right
        playerFeedbackLabel.verticalAlignmentMode = .center
        playerFeedbackLabel.zPosition = 20
        addChild(playerFeedbackLabel)

        for _ in 0..<BattleConfig.cardCount {
            let card = SKShapeNode()
            card.strokeColor = SKColor.white.withAlphaComponent(0.35)
            card.lineWidth = 1
            card.zPosition = 2
            addChild(card)
            cardNodes.append(card)

            let attribute = SKLabelNode(fontNamed: "AvenirNext-Bold")
            attribute.fontSize = 12
            attribute.verticalAlignmentMode = .center
            attribute.zPosition = 3
            card.addChild(attribute)
            cardAttributeLabels.append(attribute)

            let attack = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            attack.fontSize = 8.5
            attack.fontColor = .white
            attack.verticalAlignmentMode = .center
            attack.zPosition = 3
            card.addChild(attack)
            cardAttackLabels.append(attack)

            let heal = SKLabelNode(fontNamed: "AvenirNext-Regular")
            heal.fontSize = 7.5
            heal.fontColor = SKColor.white.withAlphaComponent(0.8)
            heal.verticalAlignmentMode = .center
            heal.zPosition = 3
            card.addChild(heal)
            cardHealLabels.append(heal)

            let damage = SKLabelNode(fontNamed: "AvenirNext-Bold")
            damage.fontSize = 8
            damage.fontColor = .systemYellow
            damage.verticalAlignmentMode = .center
            damage.zPosition = 4
            card.addChild(damage)
            cardDamageLabels.append(damage)
        }
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

        let cardCenterY = boardFrame.maxY + 27
        let trackFrame = CGRect(
            x: horizontalMargin,
            y: cardCenterY + 27,
            width: boardWidth,
            height: 10
        )
        let headerY = trackFrame.maxY + 22
        comboLabel.position = CGPoint(x: horizontalMargin, y: headerY)
        timerLabel.position = CGPoint(x: size.width - horizontalMargin, y: headerY)
        timerTrack.path = CGPath(roundedRect: trackFrame, cornerWidth: 6, cornerHeight: 6, transform: nil)
        timerFill.position = CGPoint(x: trackFrame.minX, y: trackFrame.midY)
        timerFill.size = CGSize(width: trackFrame.width, height: 8)

        layoutBattleInterface(horizontalMargin: horizontalMargin, boardWidth: boardWidth)

#if DEBUG
        // Fit the diagnostic rows below the board, without moving gameplay UI.
        let debugScale = min(1, max(0.1, (boardFrame.minY - 8) / 88))
        for (index, label) in debugLabels.enumerated() {
            label.fontSize = 10 * debugScale
            label.position = CGPoint(x: horizontalMargin, y: boardFrame.minY - (18 + CGFloat(index) * 12) * debugScale)
        }
        // Leave enough room for the split manual/skyfall averages in the
        // left COMBO line while keeping the six shorter type rows visible.
        let rightColumnX = horizontalMargin + boardWidth * 0.55
        for (index, label) in orbTypeDebugLabels.enumerated() {
            label.fontSize = 10 * debugScale
            label.position = CGPoint(x: rightColumnX, y: boardFrame.minY - (18 + CGFloat(index) * 12) * debugScale)
        }
#endif
    }

    private func layoutBattleInterface(horizontalMargin: CGFloat, boardWidth: CGFloat) {
        let cardCenterY = boardFrame.maxY + 27
        let cardGap: CGFloat = 4
        let cardWidth = (boardWidth - cardGap * CGFloat(BattleConfig.cardCount - 1))
            / CGFloat(BattleConfig.cardCount)
        let cardHeight: CGFloat = 44
        for index in 0..<min(cardNodes.count, BattleConfig.cardCount) {
            let centerX = horizontalMargin + cardWidth / 2 + CGFloat(index) * (cardWidth + cardGap)
            cardNodes[index].path = CGPath(
                roundedRect: CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight),
                cornerWidth: 8,
                cornerHeight: 8,
                transform: nil
            )
            cardNodes[index].position = CGPoint(x: centerX, y: cardCenterY)
            cardAttributeLabels[index].position = CGPoint(x: 0, y: 10)
            cardAttackLabels[index].position = CGPoint(x: 0, y: -3)
            cardHealLabels[index].position = CGPoint(x: 0, y: -14)
            cardDamageLabels[index].position = CGPoint(x: 0, y: 18)
        }

        let headerY = cardCenterY + 59
        // Keep the HP label and bar clear of the large Combo line. The previous
        // 31-point offset placed the bar directly through the Combo glyphs.
        let playerLabelY = headerY + 49
        playerHPLabel.position = CGPoint(x: horizontalMargin, y: playerLabelY)
        playerAttackLabel.position = CGPoint(x: horizontalMargin + boardWidth, y: playerLabelY)
        // Keep transient heal/damage feedback clear of the persistent ATK row.
        playerFeedbackLabel.position = CGPoint(x: horizontalMargin + boardWidth, y: playerLabelY + 15)
        playerHPBarFrame = CGRect(
            x: horizontalMargin,
            y: playerLabelY - 21,
            width: boardWidth,
            height: 7
        )
        playerHPTrack.path = CGPath(
            roundedRect: playerHPBarFrame,
            cornerWidth: 3.5,
            cornerHeight: 3.5,
            transform: nil
        )
        playerHPFill.position = CGPoint(x: playerHPBarFrame.minX, y: playerHPBarFrame.midY)

        let monsterCenterY = min(size.height - 24, playerLabelY + 49)
        let monsterFrame = CGRect(
            x: horizontalMargin,
            y: monsterCenterY - 19,
            width: boardWidth,
            height: 40
        )
        monsterArea.path = CGPath(
            roundedRect: monsterFrame,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        let placeholderCenter = CGPoint(x: monsterFrame.minX + 22, y: monsterFrame.midY)
        monsterPlaceholder.path = CGPath(
            ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32),
            transform: nil
        )
        monsterPlaceholder.position = placeholderCenter
        monsterPlaceholderLabel.position = placeholderCenter
        monsterTitleLabel.position = CGPoint(x: monsterFrame.minX + 45, y: monsterCenterY + 9)
        monsterHPLabel.position = CGPoint(x: monsterFrame.minX + 45, y: monsterCenterY - 5)
        monsterCDLabel.position = CGPoint(x: monsterFrame.maxX - 8, y: monsterCenterY + 9)
        battleStatusLabel.position = CGPoint(x: monsterFrame.midX + 36, y: monsterCenterY + 9)
        monsterHPBarFrame = CGRect(
            x: monsterFrame.minX + 45,
            y: monsterCenterY - 16,
            width: max(20, monsterFrame.width - 55),
            height: 5
        )
        monsterHPTrack.path = CGPath(
            roundedRect: monsterHPBarFrame,
            cornerWidth: 2.5,
            cornerHeight: 2.5,
            transform: nil
        )
        monsterHPFill.position = CGPoint(x: monsterHPBarFrame.minX, y: monsterHPBarFrame.midY)
        monsterDamageLabel.position = CGPoint(x: monsterFrame.midX, y: monsterFrame.maxY + 4)
        updateBattleUI()
    }

    private func updateCardUI() {
        let cards = battleSession.config.cards
        guard cards.count == BattleConfig.cardCount,
              cardNodes.count == BattleConfig.cardCount else { return }
        for (index, card) in cards.enumerated() {
            cardNodes[index].fillColor = battleColor(for: card.attribute).withAlphaComponent(0.62)
            cardAttributeLabels[index].text = card.attribute.hudDisplayName
            cardAttackLabels[index].text = "ATK \(card.attack)"
            cardHealLabels[index].text = "H \(Int(card.heartHealPercent))%"
            cardDamageLabels[index].text = nil
        }
    }

    private func updateBattleUI() {
        let state = battleSession.state
        monsterTitleLabel.text = "Monster"
        monsterHPLabel.text = "HP \(state.monsterCurrentHP) / \(state.monsterMaxHP)"
        monsterCDLabel.text = "CD \(state.monsterCurrentCD)"
        playerHPLabel.text = "Player HP \(state.playerCurrentHP) / \(state.playerMaxHP)"
        playerAttackLabel.text = "ATK \(lastDisplayedAttack)"
        fitPlayerHPRow()
        switch state.outcome {
        case .active:
            battleStatusLabel.text = nil
        case .defeated:
            battleStatusLabel.text = "DEFEATED"
            battleStatusLabel.fontColor = .systemYellow
        case .gameOver:
            battleStatusLabel.text = "GAME OVER"
            battleStatusLabel.fontColor = .systemRed
        }

        let monsterRatio = state.monsterMaxHP > 0
            ? CGFloat(state.monsterCurrentHP) / CGFloat(state.monsterMaxHP)
            : 0
        monsterHPFill.size = CGSize(
            width: monsterHPBarFrame.width * min(max(monsterRatio, 0), 1),
            height: monsterHPBarFrame.height
        )
        let playerRatio = state.playerMaxHP > 0
            ? CGFloat(state.playerCurrentHP) / CGFloat(state.playerMaxHP)
            : 0
        playerHPFill.size = CGSize(
            width: playerHPBarFrame.width * min(max(playerRatio, 0), 1),
            height: playerHPBarFrame.height
        )
    }

    private func fitPlayerHPRow() {
        guard playerHPBarFrame.width > 0 else { return }
        // Separate width budgets preserve an eight-point gap even for long values.
        let availableWidth = max(0, playerHPBarFrame.width - 8)
        for (label, width) in [
            (playerHPLabel, availableWidth * 0.60),
            (playerAttackLabel, availableWidth * 0.40)
        ] {
            label.setScale(1)
            if label.frame.width > width {
                label.setScale(width / label.frame.width)
            }
        }
    }

    private func showBattleFeedback(_ result: BattleTurnResult) {
        for (index, damage) in result.cardDamages.enumerated()
        where cardDamageLabels.indices.contains(index) {
            animateBattleFeedback(cardDamageLabels[index], text: damage > 0 ? "DMG \(damage)" : nil)
        }
        animateBattleFeedback(
            monsterDamageLabel,
            text: result.appliedMonsterDamage > 0 ? "-\(result.appliedMonsterDamage)" : nil
        )

        var playerParts: [String] = []
        if result.appliedHeal > 0 { playerParts.append("+\(result.appliedHeal)") }
        if result.monsterAttackDamage > 0 { playerParts.append("-\(result.monsterAttackDamage)") }
        playerFeedbackLabel.fontColor = result.monsterAttackDamage > 0 ? .systemRed : .systemGreen
        animateBattleFeedback(
            playerFeedbackLabel,
            text: playerParts.isEmpty ? nil : playerParts.joined(separator: "  ")
        )
    }

    private func animateBattleFeedback(_ label: SKLabelNode, text: String?) {
        label.removeAllActions()
        label.text = text
        label.alpha = text == nil ? 0 : 1
        guard text != nil else { return }
        label.run(.sequence([
            .wait(forDuration: 0.8),
            .fadeOut(withDuration: 0.35)
        ]))
    }

    private func battleColor(for type: OrbType) -> SKColor {
        switch type {
        case .fire: return SKColor(red: 0.94, green: 0.23, blue: 0.18, alpha: 1)
        case .water: return SKColor(red: 0.15, green: 0.54, blue: 0.96, alpha: 1)
        case .wood: return SKColor(red: 0.19, green: 0.76, blue: 0.35, alpha: 1)
        case .light: return SKColor(red: 0.98, green: 0.79, blue: 0.16, alpha: 1)
        case .dark: return SKColor(red: 0.46, green: 0.24, blue: 0.72, alpha: 1)
        case .heart: return SKColor(red: 0.96, green: 0.35, blue: 0.67, alpha: 1)
        }
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
        guard battleSession.state.canAcceptInput,
              gameState == .idle || gameState == .turnActive,
              let touch = touches.first else { return }
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
#if DEBUG
        if initialMatches.isEmpty {
            print("[MANUAL_RESOLVE] resolveID=\(resolveID) groupCount=0 groupSizes=[] removedPositions=[] removedCount=0")
        }
#endif
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
#if DEBUG
        let traceTag = source == .manual ? "MANUAL_RESOLVE" : "SKYFALL_RESOLVE"
        print("[\(traceTag)] resolveID=\(resolveID) groupCount=\(resolveResult.comboCount) groupSizes=\(matches.map { $0.positions.count }) removedPositions=\(FriendlyRefillPipeline.describe(Array(resolveResult.removedPositions))) removedCount=\(resolveResult.removedOrbCount)")
#endif
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
            let emptyPositionsBefore = grid.emptyPositions()
            let emptyCount = emptyPositionsBefore.count
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
#if DEBUG
            let emptyPositionsAfterCollapse = grid.emptyPositions()
            print("[GRAVITY] resolveID=\(resolveID) emptyPositionsBefore=\(FriendlyRefillPipeline.describe(emptyPositionsBefore)) emptyPositionsAfterCollapse=\(FriendlyRefillPipeline.describe(emptyPositionsAfterCollapse)) emptyCount=\(emptyPositionsAfterCollapse.count)")
#endif
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
                previousResolution: result,
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
        previousResolution: ResolveResult,
        resolveID: UInt
    ) {
        guard resolveID == activeResolveID, resolveLifecycle.acceptsSkyfallCompletion else {
            logStaleCompletion("refill entry")
            return
        }
        gameState = .refilling
        // Always query after gravity; never reuse slots captured by an older cycle.
        let refillSlots = grid.emptyPositions()
        if refillSlots.count != expectedRefillCount {
#if DEBUG
            print("[REFILL-BUG] expected=\(expectedRefillCount) slots=\(refillSlots.count)")
#endif
            // Preserve the existing exact-target failure boundary for ON mode.
            // OFF mode can safely use the actual empty positions as its source
            // of truth because it has no configured target to satisfy.
            if skyfallController.hasControlledTarget {
                finishResolution(resolveID: resolveID)
                return
            }
        }

        // ON uses its unchanged exact-total planner. OFF derives this refill's
        // candidate count from the previous snapshot's actual resolved groups.
        let controlledTypes = skyfallController.hasControlledTarget
            && skyfallController.needsAnotherCycle
            ? skyfallController.makeControlledRefill(grid: grid, refillSlots: refillSlots)
            : nil
        let isControlledSkyfallRefill = controlledTypes != nil
        let friendlyPreparation = skyfallController.hasControlledTarget ? nil
            : FriendlyRefillPipeline.prepare(
                grid: grid, previousResolution: previousResolution, controller: skyfallController
            )
        let friendlyDecision = friendlyPreparation?.decision
        let isFriendlyNaturalRefill = friendlyPreparation?.usesFriendlyTypes == true
        let isSafeRefill = !isControlledSkyfallRefill && !isFriendlyNaturalRefill

#if DEBUG
        if isControlledSkyfallRefill {
            print("[SKYFALL] controlled batch begin progress=\(skyfallController.generatedCombos)/\(skyfallController.requestedCombos) slots=\(refillSlots.count)")
        } else if isFriendlyNaturalRefill {
            print("[SKYFALL] friendly natural begin next=\(skyfallController.generatedCombos + 1) slots=\(refillSlots.count)")
        } else {
            print("[REFILL] safe final begin slots=\(refillSlots.count)")
        }
        friendlyPreparation?.logDebug(resolveID: resolveID)
        friendlyDebugPreparation = friendlyPreparation
        friendlyDebugDetectedGroups = nil
        if let friendlyPreparation {
            friendlyDebugStatistics[friendlyPreparation.slots.count, default: FriendlyRefillDebugStatistics()]
                .record(friendlyPreparation)
            if friendlyPreparation.decision.selectedTarget > 0 {
                friendlyTargetStatistics[friendlyPreparation.decision.selectedTarget, default: FriendlyTargetDebugStatistics()]
                    .record(friendlyPreparation)
            }
        }
#endif
        var plannedTypes: [OrbType]?
        if skyfallController.hasControlledTarget {
            // Natural and controlled groups share the exact ON target. Once the
            // total reaches it, safe refill prevents an active target + 1 group.
            plannedTypes = controlledTypes
                ?? skyfallController.makeSafeRefill(grid: grid, refillSlots: refillSlots)
        } else {
            // The same preparation is consumed by RefillController and shape
            // tests. No second roll or safe assignment may replace a valid plan.
            plannedTypes = friendlyPreparation?.types
        }
        if !skyfallController.hasControlledTarget,
           plannedTypes?.count != refillSlots.count {
#if DEBUG
            print("[REFILL][ERROR] assignmentCount mismatch emptyBefore=\(refillSlots.count) assignmentCount=\(plannedTypes?.count ?? -1)")
#endif
            plannedTypes = skyfallController.makeNaturalRefill(
                grid: grid,
                refillSlots: refillSlots
            )
        }
        guard let plannedTypes, plannedTypes.count == refillSlots.count else {
#if DEBUG
            print("[REFILL][ERROR] assignmentCount mismatch emptyBefore=\(refillSlots.count) assignmentCount=\(plannedTypes?.count ?? -1)")
#endif
            finishResolution(resolveID: resolveID)
            return
        }
#if DEBUG
        let refillMode = isControlledSkyfallRefill
            ? "controlled"
            : (friendlyPreparation?.refillMode ?? "safe")
        let typeSummary = OrbType.allCases.map { type in
            "\(type.displayName)=\(plannedTypes.filter { $0 == type }.count)"
        }.joined(separator: " ")
        print("[REFILL] resolveID=\(resolveID) refillMode=\(refillMode) slotCount=\(refillSlots.count) assignmentCount=\(plannedTypes.count) \(typeSummary)")
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
            },
            friendlyPreparation: friendlyPreparation
        )
#if DEBUG
        if result.spawns.count != expectedRefillCount {
            print("[REFILL-BUG] expected=\(expectedRefillCount) new=\(result.spawns.count)")
        }
#endif
        for node in result.nodes { orbNodes[node.orbID] = node }
#if DEBUG
        let emptyAfter = grid.emptyPositions().count
        let occupiedAfter = grid.cells.flatMap { $0 }.compactMap { $0 }.count
        let selectedTargetDescription = friendlyDecision.map { String($0.selectedTarget) } ?? "n/a"
        print("[REFILL] resolveID=\(resolveID) refillMode=\(refillMode) slotCount=\(refillSlots.count) removedOrbs=\(expectedRefillCount) emptyBefore=\(refillSlots.count) selectedTarget=\(selectedTargetDescription) assignmentCount=\(plannedTypes.count) spawnCount=\(result.spawns.count) emptyAfter=\(emptyAfter) occupiedAfter=\(occupiedAfter)")
        if plannedTypes.count != refillSlots.count
            || result.spawns.count != refillSlots.count
            || emptyAfter != 0
            || occupiedAfter != grid.rows * grid.columns {
            print("[REFILL][ERROR] assignmentCount mismatch emptyBefore=\(refillSlots.count) assignmentCount=\(plannedTypes.count) spawnCount=\(result.spawns.count) emptyAfter=\(emptyAfter) occupiedAfter=\(occupiedAfter)")
        }
        print("[SKYFALL] removed=\(expectedRefillCount) existingPreserved=\(preservedCount) newOrbs=\(result.spawns.count)")
#endif
        run(after: result.duration) { [weak self] in
            guard let self else { return }
            guard resolveID == self.activeResolveID,
                  self.gameState == .refilling else {
                self.logStaleCompletion("refill animation")
                return
            }
            let stableBoard = friendlyPreparation != nil
                ? FriendlyRefillPipeline.scan(in: self.grid)
                : StableBoardScan(matches: self.matchDetector.detect(in: self.grid))
            let matches = stableBoard.matches
#if DEBUG
            print("[POST_REFILL_MATCH] resolveID=\(resolveID) detectedGroupCount=\(matches.count) groupSizes=\(matches.map { $0.positions.count }) groupTypes=\(matches.map { $0.type.rawValue }) refillMode=\(friendlyPreparation?.refillMode ?? (isControlledSkyfallRefill ? "controlled" : "safe"))")
            if friendlyPreparation != nil {
                self.friendlyDebugDetectedGroups = matches.count
                if let preparation = friendlyPreparation {
                    self.friendlyDebugStatistics[preparation.slots.count, default: FriendlyRefillDebugStatistics()]
                        .recordPostRefill(matches, preparation: preparation)
                    if preparation.decision.selectedTarget > 0 {
                        let target = preparation.decision.selectedTarget
                        self.friendlyTargetStatistics[target, default: FriendlyTargetDebugStatistics()]
                            .recordPostRefill(matches, preparation: preparation)
                        let targetStats = self.friendlyTargetStatistics[target] ?? FriendlyTargetDebugStatistics()
                        print("[FRIENDLY_TARGET_STATS] selected=\(target) attempts=\(targetStats.attempts) plannedExact=\(targetStats.plannedExact) detectedExactOrMore=\(targetStats.detectedExactOrMore)")
                    }
                    let stats = self.friendlyDebugStatistics[preparation.slots.count] ?? FriendlyRefillDebugStatistics()
                    print("[FRIENDLY_STATS] slots=\(preparation.slots.count) eligible=\(stats.eligible) target=\(stats.targets) plan=\(stats.plans) detected=\(stats.detected)")
                }
            }
#endif

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
            let battleResult = battleSession.resolveTurn(
                comboByType: comboController.comboTotalByType
            )
            lastDisplayedAttack = battleResult.totalMonsterDamage
            updateBattleUI()
            showBattleFeedback(battleResult)
            sessionStatistics.commitCompletedTurn(
                resolveID: resolveID,
                moveTime: finalTurnMoveTime,
                manualCombo: comboController.manualComboCount,
                skyfallCombo: comboController.skyfallComboCount,
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
        guard debugLabels.count == 6,
              orbTypeDebugLabels.count == OrbType.resolveOrder.count else { return }
        debugLabels[0].text = String(format: "FPS %.0f", smoothedFPS)
        debugLabels[1].text = "State \(gameState.rawValue)"
        debugLabels[2].text = GameplayStatusHUDText.game(
            completedTurnCount: sessionStatistics.completedTurnCount
        )
        debugLabels[3].text = GameplayStatusHUDText.time(
            current: turnController.displayedElapsedTurnTime,
            average: sessionStatistics.averageTurnTime
        )
        debugLabels[4].text = GameplayStatusHUDText.combo(
            currentBreakdown: comboController.breakdownText,
            averageManual: sessionStatistics.averageManualCombo,
            averageSkyfall: sessionStatistics.averageSkyfallCombo
        )
        debugLabels[5].text = noResolveDuringTurn ? "No Resolve ON" : "No Resolve OFF"
        for (index, type) in OrbType.resolveOrder.enumerated() {
            orbTypeDebugLabels[index].text = GameplayStatusHUDText.orbType(
                currentBreakdown: comboController.breakdownText(for: type),
                average: sessionStatistics.averageCombo(for: type)
            )
        }
#endif
    }
}
