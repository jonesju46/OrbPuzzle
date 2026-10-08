import Foundation

enum GameSettings {
    static let turnDurationKey = "turnDuration"
    static let turnTimeEnabledKey = "turnTimeEnabled"
    static let noResolveDuringTurnKey = "noResolveDuringTurn"
    static let skyfallComboCountKey = "skyfallComboCount"
    static let skyfallComboEnabledKey = "skyfallComboEnabled"

    static let defaultTurnDuration = 10.0
    static let defaultTurnTimeEnabled = false
    static let defaultNoResolveDuringTurn = false
    static let defaultSkyfallComboCount = 15
    static let defaultSkyfallComboEnabled = false

    static let turnDurationRange = 5.0...99.0
    static let skyfallComboCountRange = 1...99
    static let disabledTurnDuration = 5.0

    static let playerMaxHPKey = "battle.playerMaxHP"
    static let monsterHPKey = "battle.monsterHP"
    static let monsterCDKey = "battle.monsterCD"
    static let monsterATKKey = "battle.monsterATK"
    static let card1AttributeKey = "battle.card1.attribute"
    static let card1ATKKey = "battle.card1.attack"
    static let card1HeartHealKey = "battle.card1.heartHealPercent"
    static let card2AttributeKey = "battle.card2.attribute"
    static let card2ATKKey = "battle.card2.attack"
    static let card2HeartHealKey = "battle.card2.heartHealPercent"
    static let card3AttributeKey = "battle.card3.attribute"
    static let card3ATKKey = "battle.card3.attack"
    static let card3HeartHealKey = "battle.card3.heartHealPercent"
    static let card4AttributeKey = "battle.card4.attribute"
    static let card4ATKKey = "battle.card4.attack"
    static let card4HeartHealKey = "battle.card4.heartHealPercent"
    static let card5AttributeKey = "battle.card5.attribute"
    static let card5ATKKey = "battle.card5.attack"
    static let card5HeartHealKey = "battle.card5.heartHealPercent"

    static let defaultPlayerMaxHP = 10_000
    static let defaultMonsterHP = 10_000
    static let defaultMonsterCD = 3
    static let defaultMonsterATK = 2_000
    static let defaultCardATK = 1_000
    static let defaultCardHeartHealPercent = 2
    static let battleHPRange = 1...9_999_999
    static let monsterCDRange = 1...99
    static let battleAttackRange = 0...999_999
    static let heartHealPercentRange = 0.0...100.0
    static let battleCardAttributes: [OrbType] = [.water, .fire, .wood, .light, .dark]

    static func effectiveTurnDuration(enabled: Bool, configured: Double) -> Double {
        guard enabled else { return disabledTurnDuration }
        return min(max(configured, turnDurationRange.lowerBound), turnDurationRange.upperBound)
    }

    static func effectiveSkyfallComboCount(enabled: Bool, configured: Int) -> Int {
        guard enabled else { return 0 }
        return min(max(configured, skyfallComboCountRange.lowerBound), skyfallComboCountRange.upperBound)
    }

    static func battleConfig(defaults: UserDefaults = .standard) -> BattleConfig {
        let defaultCards = BattleConfig.defaultCards
        let attributeKeys = [
            card1AttributeKey, card2AttributeKey, card3AttributeKey,
            card4AttributeKey, card5AttributeKey
        ]
        let attackKeys = [card1ATKKey, card2ATKKey, card3ATKKey, card4ATKKey, card5ATKKey]
        let healKeys = [
            card1HeartHealKey, card2HeartHealKey, card3HeartHealKey,
            card4HeartHealKey, card5HeartHealKey
        ]
        let cards = (0..<BattleConfig.cardCount).map { index in
            let fallback = defaultCards[index]
            let rawAttribute = defaults.string(forKey: attributeKeys[index])
            let attribute = rawAttribute.flatMap { OrbType(rawValue: $0) } ?? fallback.attribute
            let attack = storedInt(defaults, key: attackKeys[index]) ?? fallback.attack
            let heal = storedDouble(defaults, key: healKeys[index]) ?? fallback.heartHealPercent
            return CardConfig(attribute: attribute, attack: attack, heartHealPercent: heal)
        }

        return BattleConfig(
            playerMaxHP: storedInt(defaults, key: playerMaxHPKey) ?? defaultPlayerMaxHP,
            monster: MonsterConfig(
                maxHP: storedInt(defaults, key: monsterHPKey) ?? defaultMonsterHP,
                attack: storedInt(defaults, key: monsterATKKey) ?? defaultMonsterATK,
                baseCD: storedInt(defaults, key: monsterCDKey) ?? defaultMonsterCD
            ),
            cards: cards
        )
    }

    private static func storedInt(_ defaults: UserDefaults, key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    private static func storedDouble(_ defaults: UserDefaults, key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    enum Tuning {
        static let swapDuration = 0.08
        static let resolveHighlightDuration = 0.06
        static let removeDuration = 0.18
        static let resolvePhaseDelay = 0.10
        static let fallDuration = 0.20
        static let refillDuration = 0.24
        static let comboDisplayDuration = 0.30
    }
}
