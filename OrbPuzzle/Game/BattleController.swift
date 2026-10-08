import Foundation

private func makeDefaultBattleCards() -> [CardConfig] {
    [
        CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 2),
        CardConfig(attribute: .fire, attack: 1_000, heartHealPercent: 2),
        CardConfig(attribute: .wood, attack: 1_000, heartHealPercent: 2),
        CardConfig(attribute: .light, attack: 1_000, heartHealPercent: 2),
        CardConfig(attribute: .dark, attack: 1_000, heartHealPercent: 2)
    ]
}

struct CardConfig: Equatable, Sendable {
    let attribute: OrbType
    let attack: Int
    let heartHealPercent: Double

    init(attribute: OrbType, attack: Int, heartHealPercent: Double) {
        self.attribute = attribute == .heart ? .water : attribute
        self.attack = min(max(attack, 0), GameSettings.battleAttackRange.upperBound)
        self.heartHealPercent = min(
            max(heartHealPercent, GameSettings.heartHealPercentRange.lowerBound),
            GameSettings.heartHealPercentRange.upperBound
        )
    }

    func damage(comboCount: Int) -> Int {
        attack * max(0, comboCount)
    }

    func healContribution(playerMaxHP: Int, heartComboCount: Int) -> Int {
        let rawHeal = Double(max(0, playerMaxHP))
            * (heartHealPercent / 100)
            * Double(max(0, heartComboCount))
        return max(0, Int(rawHeal.rounded(.down)))
    }
}

struct MonsterConfig: Equatable, Sendable {
    let maxHP: Int
    let attack: Int
    let baseCD: Int

    init(maxHP: Int, attack: Int, baseCD: Int) {
        self.maxHP = min(max(maxHP, GameSettings.battleHPRange.lowerBound), GameSettings.battleHPRange.upperBound)
        self.attack = min(max(attack, GameSettings.battleAttackRange.lowerBound), GameSettings.battleAttackRange.upperBound)
        self.baseCD = min(max(baseCD, GameSettings.monsterCDRange.lowerBound), GameSettings.monsterCDRange.upperBound)
    }
}

struct BattleConfig: Equatable, Sendable {
    static let cardCount = 5

    let playerMaxHP: Int
    let monster: MonsterConfig
    let cards: [CardConfig]

    init(playerMaxHP: Int, monster: MonsterConfig, cards: [CardConfig]) {
        self.playerMaxHP = min(
            max(playerMaxHP, GameSettings.battleHPRange.lowerBound),
            GameSettings.battleHPRange.upperBound
        )
        self.monster = monster
        self.cards = Array((cards + makeDefaultBattleCards()).prefix(Self.cardCount))
    }

    static let defaultCards = makeDefaultBattleCards()

    static let `default` = BattleConfig(
        playerMaxHP: 10_000,
        monster: MonsterConfig(maxHP: 10_000, attack: 2_000, baseCD: 3),
        cards: defaultCards
    )
}

enum BattleOutcome: String, Equatable, Sendable {
    case active
    case defeated
    case gameOver
}

struct BattleState: Equatable, Sendable {
    let playerMaxHP: Int
    var playerCurrentHP: Int
    let monsterMaxHP: Int
    var monsterCurrentHP: Int
    var monsterCurrentCD: Int
    var outcome: BattleOutcome

    var isGameOver: Bool { outcome == .gameOver }
    var isMonsterDefeated: Bool { outcome == .defeated }
    // A defeated MVP monster no longer performs battle actions, but the orb
    // sandbox remains playable. Only player death locks board input.
    var canAcceptInput: Bool { outcome != .gameOver }
}

struct BattleTurnResult: Equatable, Sendable {
    let heartComboCount: Int
    let cardHealContributions: [Int]
    let totalCalculatedHeal: Int
    let appliedHeal: Int
    let cardDamages: [Int]
    let totalMonsterDamage: Int
    let appliedMonsterDamage: Int
    let monsterAttackDamage: Int
    let monsterDidAttack: Bool
    let outcome: BattleOutcome

    static func ignored(outcome: BattleOutcome, cardCount: Int) -> BattleTurnResult {
        BattleTurnResult(
            heartComboCount: 0,
            cardHealContributions: Array(repeating: 0, count: cardCount),
            totalCalculatedHeal: 0,
            appliedHeal: 0,
            cardDamages: Array(repeating: 0, count: cardCount),
            totalMonsterDamage: 0,
            appliedMonsterDamage: 0,
            monsterAttackDamage: 0,
            monsterDidAttack: false,
            outcome: outcome
        )
    }
}

struct BattleSession: Equatable, Sendable {
    let config: BattleConfig
    private(set) var state: BattleState

    init(
        config: BattleConfig,
        playerCurrentHP: Int? = nil,
        monsterCurrentHP: Int? = nil,
        monsterCurrentCD: Int? = nil
    ) {
        self.config = config
        let initialPlayerHP = min(max(playerCurrentHP ?? config.playerMaxHP, 0), config.playerMaxHP)
        let initialMonsterHP = min(max(monsterCurrentHP ?? config.monster.maxHP, 0), config.monster.maxHP)
        state = BattleState(
            playerMaxHP: config.playerMaxHP,
            playerCurrentHP: initialPlayerHP,
            monsterMaxHP: config.monster.maxHP,
            monsterCurrentHP: initialMonsterHP,
            monsterCurrentCD: min(
                max(monsterCurrentCD ?? config.monster.baseCD, 0),
                config.monster.baseCD
            ),
            outcome: initialMonsterHP == 0 ? .defeated : (initialPlayerHP == 0 ? .gameOver : .active)
        )
    }

    mutating func resolveTurn(comboByType: [OrbType: Int]) -> BattleTurnResult {
        guard state.outcome == .active else {
            return .ignored(outcome: state.outcome, cardCount: config.cards.count)
        }

        let heartComboCount = max(0, comboByType[.heart, default: 0])
        let healContributions = config.cards.map {
            $0.healContribution(
                playerMaxHP: state.playerMaxHP,
                heartComboCount: heartComboCount
            )
        }
        let totalCalculatedHeal = healContributions.reduce(0, +)
        let missingPlayerHP = max(0, state.playerMaxHP - state.playerCurrentHP)
        let appliedHeal = min(totalCalculatedHeal, missingPlayerHP)
        state.playerCurrentHP += appliedHeal

        let cardDamages = config.cards.map { card in
            card.damage(comboCount: comboByType[card.attribute, default: 0])
        }
        let totalMonsterDamage = cardDamages.reduce(0, +)
        let appliedMonsterDamage = min(totalMonsterDamage, state.monsterCurrentHP)
        state.monsterCurrentHP = max(0, state.monsterCurrentHP - totalMonsterDamage)

        if state.monsterCurrentHP == 0 {
            state.outcome = .defeated
            return BattleTurnResult(
                heartComboCount: heartComboCount,
                cardHealContributions: healContributions,
                totalCalculatedHeal: totalCalculatedHeal,
                appliedHeal: appliedHeal,
                cardDamages: cardDamages,
                totalMonsterDamage: totalMonsterDamage,
                appliedMonsterDamage: appliedMonsterDamage,
                monsterAttackDamage: 0,
                monsterDidAttack: false,
                outcome: state.outcome
            )
        }

        state.monsterCurrentCD = max(0, state.monsterCurrentCD - 1)
        var monsterAttackDamage = 0
        var monsterDidAttack = false
        if state.monsterCurrentCD == 0 {
            monsterDidAttack = true
            monsterAttackDamage = min(config.monster.attack, state.playerCurrentHP)
            state.playerCurrentHP = max(0, state.playerCurrentHP - config.monster.attack)
            state.monsterCurrentCD = config.monster.baseCD
            if state.playerCurrentHP == 0 {
                state.outcome = .gameOver
            }
        }

        return BattleTurnResult(
            heartComboCount: heartComboCount,
            cardHealContributions: healContributions,
            totalCalculatedHeal: totalCalculatedHeal,
            appliedHeal: appliedHeal,
            cardDamages: cardDamages,
            totalMonsterDamage: totalMonsterDamage,
            appliedMonsterDamage: appliedMonsterDamage,
            monsterAttackDamage: monsterAttackDamage,
            monsterDidAttack: monsterDidAttack,
            outcome: state.outcome
        )
    }
}
