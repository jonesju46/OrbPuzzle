import CoreGraphics
import XCTest
@testable import OrbPuzzle

final class OrbPuzzleEngineTests: XCTestCase {
    func testIdleTimerPolicyDisablesOnlyForActiveScene() {
        XCTAssertTrue(AppIdleTimerPolicy.shouldDisableIdleTimer(for: .active))
        XCTAssertFalse(AppIdleTimerPolicy.shouldDisableIdleTimer(for: .inactive))
        XCTAssertFalse(AppIdleTimerPolicy.shouldDisableIdleTimer(for: .background))
    }

    func testActiveSceneKeepsIdleTimerDisabledAcrossInAppDestinations() {
        for destination in ["Gameplay", "Settings", "Home"] {
            XCTAssertTrue(
                AppIdleTimerPolicy.shouldDisableIdleTimer(for: .active),
                "destination=\(destination)"
            )
        }
    }

    func testBattleCardsKeepIndependentAttributeAttackAndHealConfig() {
        let cards = [
            CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 3),
            CardConfig(attribute: .water, attack: 500, heartHealPercent: 5)
        ]
        let config = BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 10_000, attack: 2_000, baseCD: 3),
            cards: cards
        )

        XCTAssertEqual(config.cards[0], cards[0])
        XCTAssertEqual(config.cards[1], cards[1])
        XCTAssertNotEqual(config.cards[0].attack, config.cards[1].attack)
        XCTAssertNotEqual(config.cards[0].heartHealPercent, config.cards[1].heartHealPercent)
    }

    func testBattleMVPDefaultsAndRanges() {
        let config = BattleConfig.default

        XCTAssertEqual(config.playerMaxHP, 10_000)
        XCTAssertEqual(config.monster, MonsterConfig(maxHP: 10_000, attack: 2_000, baseCD: 3))
        XCTAssertEqual(config.cards.map(\.attribute), [.water, .fire, .wood, .light, .dark])
        XCTAssertEqual(config.cards.map(\.attack), Array(repeating: 1_000, count: 5))
        XCTAssertEqual(config.cards.map(\.heartHealPercent), Array(repeating: 2.0, count: 5))
        XCTAssertEqual(GameSettings.battleHPRange, 1...9_999_999)
        XCTAssertEqual(GameSettings.monsterCDRange, 1...99)
        XCTAssertEqual(GameSettings.battleAttackRange, 0...999_999)
        XCTAssertEqual(GameSettings.heartHealPercentRange, 0.0...100.0)
        XCTAssertFalse(GameSettings.battleCardAttributes.contains(.heart))
    }

    func testDuplicateAttributeCardsAttackIndependently() {
        let cards = [
            CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 0),
            CardConfig(attribute: .water, attack: 500, heartHealPercent: 0),
            CardConfig(attribute: .fire, attack: 0, heartHealPercent: 0),
            CardConfig(attribute: .wood, attack: 0, heartHealPercent: 0),
            CardConfig(attribute: .light, attack: 0, heartHealPercent: 0)
        ]
        var session = BattleSession(config: BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 10_000, attack: 0, baseCD: 3),
            cards: cards
        ))

        let result = session.resolveTurn(comboByType: [.water: 3])

        XCTAssertEqual(result.cardDamages[0], 3_000)
        XCTAssertEqual(result.cardDamages[1], 1_500)
        XCTAssertEqual(result.totalMonsterDamage, 4_500)
        XCTAssertEqual(session.state.monsterCurrentHP, 5_500)
    }

    func testFiveCardsUseTheirOwnAttributeAndAttack() {
        let cards = [
            CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 0),
            CardConfig(attribute: .fire, attack: 800, heartHealPercent: 0),
            CardConfig(attribute: .wood, attack: 900, heartHealPercent: 0),
            CardConfig(attribute: .light, attack: 1_200, heartHealPercent: 0),
            CardConfig(attribute: .dark, attack: 1_100, heartHealPercent: 0)
        ]
        var session = BattleSession(config: BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 10_000, attack: 0, baseCD: 3),
            cards: cards
        ))

        let result = session.resolveTurn(comboByType: [
            .water: 2, .fire: 1, .wood: 0, .light: 2, .dark: 1
        ])

        XCTAssertEqual(result.cardDamages, [2_000, 800, 0, 2_400, 1_100])
        XCTAssertEqual(result.totalMonsterDamage, 6_300)
        XCTAssertEqual(session.state.monsterCurrentHP, 3_700)
    }

    func testFiveCardsHealIndividuallyAndZeroPercentContributesZero() {
        let cards = zip(
            GameSettings.battleCardAttributes,
            [3.0, 5.0, 0.0, 6.0, 2.0]
        ).map { CardConfig(attribute: $0.0, attack: 0, heartHealPercent: $0.1) }
        var session = BattleSession(
            config: BattleConfig(
                playerMaxHP: 10_000,
                monster: MonsterConfig(maxHP: 10_000, attack: 0, baseCD: 99),
                cards: cards
            ),
            playerCurrentHP: 1_000
        )

        let result = session.resolveTurn(comboByType: [.heart: 2])

        XCTAssertEqual(result.cardHealContributions, [600, 1_000, 0, 1_200, 400])
        XCTAssertEqual(result.totalCalculatedHeal, 3_200)
        XCTAssertEqual(result.appliedHeal, 3_200)
        XCTAssertEqual(session.state.playerCurrentHP, 4_200)
        XCTAssertEqual(cards[2].healContribution(playerMaxHP: 10_000, heartComboCount: 5), 0)
    }

    func testHeartHealUsesAllCardsRegardlessOfAttributeAndCapsAtMaxHP() {
        let cards = [
            CardConfig(attribute: .water, attack: 0, heartHealPercent: 3),
            CardConfig(attribute: .fire, attack: 0, heartHealPercent: 5),
            CardConfig(attribute: .wood, attack: 0, heartHealPercent: 4),
            CardConfig(attribute: .light, attack: 0, heartHealPercent: 6),
            CardConfig(attribute: .dark, attack: 0, heartHealPercent: 2)
        ]
        var session = BattleSession(
            config: BattleConfig(
                playerMaxHP: 10_000,
                monster: MonsterConfig(maxHP: 10_000, attack: 0, baseCD: 99),
                cards: cards
            ),
            playerCurrentHP: 9_500
        )

        let result = session.resolveTurn(comboByType: [.heart: 2])

        XCTAssertEqual(result.cardHealContributions, [600, 1_000, 800, 1_200, 400])
        XCTAssertEqual(result.totalCalculatedHeal, 4_000)
        XCTAssertEqual(result.appliedHeal, 500)
        XCTAssertEqual(session.state.playerCurrentHP, 10_000)
    }

    func testBattlePlayerConfigInitializesCurrentHP() {
        let session = BattleSession(config: BattleConfig(
            playerMaxHP: 25_000,
            monster: MonsterConfig(maxHP: 10_000, attack: 2_000, baseCD: 3),
            cards: BattleConfig.defaultCards
        ))

        XCTAssertEqual(session.state.playerMaxHP, 25_000)
        XCTAssertEqual(session.state.playerCurrentHP, 25_000)
    }

    func testMonsterCDDecrementsOncePerTurnAttacksAndResets() {
        var session = BattleSession(config: BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 10_000, attack: 2_000, baseCD: 3),
            cards: BattleConfig.defaultCards.map {
                CardConfig(attribute: $0.attribute, attack: 0, heartHealPercent: 0)
            }
        ))

        XCTAssertFalse(session.resolveTurn(comboByType: [:]).monsterDidAttack)
        XCTAssertEqual(session.state.monsterCurrentCD, 2)
        XCTAssertFalse(session.resolveTurn(comboByType: [:]).monsterDidAttack)
        XCTAssertEqual(session.state.monsterCurrentCD, 1)
        let third = session.resolveTurn(comboByType: [:])
        XCTAssertTrue(third.monsterDidAttack)
        XCTAssertEqual(third.monsterAttackDamage, 2_000)
        XCTAssertEqual(session.state.monsterCurrentCD, 3)
        XCTAssertEqual(session.state.playerCurrentHP, 8_000)
    }

    func testDefeatedMonsterDoesNotReduceCDOrCounterattack() {
        var session = BattleSession(config: BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 1_000, attack: 9_000, baseCD: 1),
            cards: [
                CardConfig(attribute: .water, attack: 1_500, heartHealPercent: 0),
                CardConfig(attribute: .fire, attack: 0, heartHealPercent: 0),
                CardConfig(attribute: .wood, attack: 0, heartHealPercent: 0),
                CardConfig(attribute: .light, attack: 0, heartHealPercent: 0),
                CardConfig(attribute: .dark, attack: 0, heartHealPercent: 0)
            ]
        ))

        let result = session.resolveTurn(comboByType: [.water: 1])

        XCTAssertEqual(session.state.monsterCurrentHP, 0)
        XCTAssertEqual(session.state.monsterCurrentCD, 1)
        XCTAssertEqual(session.state.outcome, .defeated)
        XCTAssertFalse(result.monsterDidAttack)
        XCTAssertEqual(session.state.playerCurrentHP, 10_000)
        XCTAssertFalse(session.state.canAcceptInput)
    }

    func testMonsterAttackCanCauseGameOverAndDisableInput() {
        var session = BattleSession(
            config: BattleConfig(
                playerMaxHP: 10_000,
                monster: MonsterConfig(maxHP: 10_000, attack: 5_000, baseCD: 1),
                cards: BattleConfig.defaultCards.map {
                    CardConfig(attribute: $0.attribute, attack: 0, heartHealPercent: 0)
                }
            ),
            playerCurrentHP: 2_000
        )

        let result = session.resolveTurn(comboByType: [:])

        XCTAssertTrue(result.monsterDidAttack)
        XCTAssertEqual(session.state.playerCurrentHP, 0)
        XCTAssertEqual(session.state.outcome, .gameOver)
        XCTAssertFalse(session.state.canAcceptInput)
        XCTAssertEqual(session.state.monsterCurrentCD, 1)
    }

    func testHeartHealIsAppliedBeforeMonsterAttack() {
        var session = BattleSession(
            config: BattleConfig(
                playerMaxHP: 10_000,
                monster: MonsterConfig(maxHP: 10_000, attack: 3_000, baseCD: 1),
                cards: BattleConfig.defaultCards.map {
                    CardConfig(attribute: $0.attribute, attack: 0, heartHealPercent: 2)
                }
            ),
            playerCurrentHP: 2_000
        )

        let result = session.resolveTurn(comboByType: [.heart: 2])

        XCTAssertEqual(result.totalCalculatedHeal, 2_000)
        XCTAssertEqual(result.appliedHeal, 2_000)
        XCTAssertEqual(result.monsterAttackDamage, 3_000)
        XCTAssertEqual(session.state.playerCurrentHP, 1_000)
    }

    func testBattleSessionFreezesConfigUntilNextNewSession() {
        var initialCards = BattleConfig.defaultCards
        initialCards[0] = CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 2)
        let initialConfig = BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 20_000, attack: 0, baseCD: 3),
            cards: initialCards
        )
        let currentSession = BattleSession(config: initialConfig)

        var changedCards = initialCards
        changedCards[0] = CardConfig(attribute: .water, attack: 5_000, heartHealPercent: 9)
        let changedConfig = BattleConfig(
            playerMaxHP: 20_000,
            monster: MonsterConfig(maxHP: 30_000, attack: 3_000, baseCD: 5),
            cards: changedCards
        )

        XCTAssertEqual(currentSession.config.cards[0].attack, 1_000)
        XCTAssertEqual(currentSession.config.playerMaxHP, 10_000)
        let nextSession = BattleSession(config: changedConfig)
        XCTAssertEqual(nextSession.config.cards[0].attack, 5_000)
        XCTAssertEqual(nextSession.config.playerMaxHP, 20_000)
    }

    func testGameSceneAppliesBattleSettingsOnlyWhenNewGameStarts() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        var firstCards = BattleConfig.defaultCards
        firstCards[0] = CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 2)
        let first = BattleConfig(
            playerMaxHP: 10_000,
            monster: MonsterConfig(maxHP: 10_000, attack: 2_000, baseCD: 3),
            cards: firstCards
        )
        scene.startNewGame(battleConfig: first)

        var changedCards = firstCards
        changedCards[0] = CardConfig(attribute: .water, attack: 5_000, heartHealPercent: 8)
        let changed = BattleConfig(
            playerMaxHP: 25_000,
            monster: MonsterConfig(maxHP: 30_000, attack: 4_000, baseCD: 5),
            cards: changedCards
        )

        XCTAssertEqual(scene.battleConfigSnapshot, first)
        XCTAssertEqual(scene.battleStateSnapshot.playerCurrentHP, 10_000)
        scene.startNewGame(battleConfig: changed)
        XCTAssertEqual(scene.battleConfigSnapshot, changed)
        XCTAssertEqual(scene.battleStateSnapshot.playerCurrentHP, 25_000)
        XCTAssertEqual(scene.battleStateSnapshot.monsterCurrentHP, 30_000)
        XCTAssertEqual(scene.battleStateSnapshot.monsterCurrentCD, 5)
    }

    func testBattleSettingsPersistEveryCardFieldIndependently() {
        let suiteName = "OrbPuzzleTests.BattleSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(25_000, forKey: GameSettings.playerMaxHPKey)
        defaults.set(50_000, forKey: GameSettings.monsterHPKey)
        defaults.set(4, forKey: GameSettings.monsterCDKey)
        defaults.set(3_000, forKey: GameSettings.monsterATKKey)
        defaults.set(OrbType.water.rawValue, forKey: GameSettings.card1AttributeKey)
        defaults.set(1_000, forKey: GameSettings.card1ATKKey)
        defaults.set(3, forKey: GameSettings.card1HeartHealKey)
        defaults.set(OrbType.water.rawValue, forKey: GameSettings.card2AttributeKey)
        defaults.set(500, forKey: GameSettings.card2ATKKey)
        defaults.set(5, forKey: GameSettings.card2HeartHealKey)
        defaults.set(OrbType.wood.rawValue, forKey: GameSettings.card3AttributeKey)
        defaults.set(700, forKey: GameSettings.card3ATKKey)
        defaults.set(4, forKey: GameSettings.card3HeartHealKey)
        defaults.set(OrbType.light.rawValue, forKey: GameSettings.card4AttributeKey)
        defaults.set(1_200, forKey: GameSettings.card4ATKKey)
        defaults.set(6, forKey: GameSettings.card4HeartHealKey)
        defaults.set(OrbType.dark.rawValue, forKey: GameSettings.card5AttributeKey)
        defaults.set(1_100, forKey: GameSettings.card5ATKKey)
        defaults.set(2, forKey: GameSettings.card5HeartHealKey)

        let config = GameSettings.battleConfig(defaults: defaults)

        XCTAssertEqual(config.playerMaxHP, 25_000)
        XCTAssertEqual(config.monster, MonsterConfig(maxHP: 50_000, attack: 3_000, baseCD: 4))
        XCTAssertEqual(config.cards[0], CardConfig(attribute: .water, attack: 1_000, heartHealPercent: 3))
        XCTAssertEqual(config.cards[1], CardConfig(attribute: .water, attack: 500, heartHealPercent: 5))
        XCTAssertEqual(config.cards[2], CardConfig(attribute: .wood, attack: 700, heartHealPercent: 4))
        XCTAssertEqual(config.cards[3], CardConfig(attribute: .light, attack: 1_200, heartHealPercent: 6))
        XCTAssertEqual(config.cards[4], CardConfig(attribute: .dark, attack: 1_100, heartHealPercent: 2))
        XCTAssertEqual(config.cards.count, 5)
    }

    func testComboSoundIndexLoopsEverySevenCombos() {
        let expected: [Int: Int] = [
            1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7,
            8: 1, 9: 2, 10: 3, 14: 7, 15: 1, 99: 1
        ]

        for (comboNumber, soundIndex) in expected {
            XCTAssertEqual(
                ComboSoundSequence.soundIndex(for: comboNumber),
                Optional(soundIndex)
            )
        }
        XCTAssertNil(ComboSoundSequence.soundIndex(for: 0))
        XCTAssertNil(ComboSoundSequence.soundIndex(for: -1))
    }

    func testManualAndSkyfallUseOneTotalComboSoundSequence() {
        let controller = ComboController()
        var soundIndices: [Int] = []

        for _ in 0..<5 {
            let comboNumber = controller.add(type: .water, groups: 1, source: .manual)
            soundIndices.append(ComboSoundSequence.soundIndex(for: comboNumber) ?? 0)
        }
        for _ in 0..<3 {
            let comboNumber = controller.add(type: .fire, groups: 1, source: .skyfall)
            soundIndices.append(ComboSoundSequence.soundIndex(for: comboNumber) ?? 0)
        }

        XCTAssertEqual(soundIndices, [1, 2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(controller.comboCount, 8)
    }

    func testDisconnectedSameColorGroupsReceiveSeparateComboSounds() {
        let controller = ComboController()
        _ = controller.add(type: .fire, groups: 1, source: .manual)
        _ = controller.add(type: .wood, groups: 1, source: .manual)
        let waterGroups = [
            makeMatch(type: .water, group: 0),
            makeMatch(type: .water, group: 2)
        ]

        let soundIndices = waterGroups.map { match -> Int in
            let comboNumber = controller.add(type: match.type, groups: 1, source: .manual)
            return ComboSoundSequence.soundIndex(for: comboNumber) ?? 0
        }

        XCTAssertEqual(soundIndices, [3, 4])
        XCTAssertEqual(controller.manualComboByType[.water], 2)
    }

    func testNormalizedTShapeReceivesOneComboSound() {
        let tShape = Set(
            (0...2).map { GridPosition(row: 1, column: $0) }
                + (0...2).map { GridPosition(row: $0, column: 1) }
        )
        let matches = MatchDetector().detect(in: gridWith(type: .water, at: tShape))
        let controller = ComboController()
        let soundIndices = matches.map { match -> Int in
            let comboNumber = controller.add(type: match.type, groups: 1, source: .manual)
            return ComboSoundSequence.soundIndex(for: comboNumber) ?? 0
        }

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(soundIndices, [1])
    }

    func testMissingComboSoundAssetFailsSafely() {
        var requestedResource: (name: String, fileExtension: String)?
        let audioManager = GameAudioManager { name, fileExtension in
            requestedResource = (name, fileExtension)
            return nil
        }

        XCTAssertFalse(audioManager.playComboSound(comboNumber: 5))
        XCTAssertEqual(requestedResource?.name, "combo_5")
        XCTAssertEqual(requestedResource?.fileExtension, "wav")
    }

    func testNewTurnRestartsComboSoundAtOne() {
        let controller = ComboController()
        var lastSoundIndex = 0

        for _ in 0..<12 {
            let comboNumber = controller.add(type: .heart, groups: 1, source: .skyfall)
            lastSoundIndex = ComboSoundSequence.soundIndex(for: comboNumber) ?? 0
        }
        XCTAssertEqual(lastSoundIndex, 5)

        controller.reset()
        let firstCombo = controller.add(type: .heart, groups: 1, source: .manual)
        XCTAssertEqual(ComboSoundSequence.soundIndex(for: firstCombo), Optional(1))
    }

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
        XCTAssertEqual(controller.manualComboCount, 12)
        XCTAssertEqual(controller.skyfallComboCount, 0)

        controller.reset()

        XCTAssertEqual(controller.comboCount, 0)
        XCTAssertEqual(controller.manualComboCount, 0)
        XCTAssertEqual(controller.skyfallComboCount, 0)
        XCTAssertEqual(controller.breakdownText, "COMBO 0 (0 + 0)")
        for type in OrbType.allCases {
            XCTAssertEqual(controller.manualComboByType[type], 0)
            XCTAssertEqual(controller.skyfallComboByType[type], 0)
        }
    }

    func testComboHUDBreakdownShowsManualFiveAndSkyfallTwo() {
        let controller = ComboController()

        XCTAssertEqual(controller.add(type: .fire, groups: 5, source: .manual), 5)
        XCTAssertEqual(controller.add(type: .water, groups: 2, source: .skyfall), 7)

        XCTAssertEqual(controller.manualComboCount, 5)
        XCTAssertEqual(controller.skyfallComboCount, 2)
        XCTAssertEqual(controller.comboCount, 7)
        XCTAssertEqual(controller.breakdownText, "COMBO 7 (5 + 2)")
    }

    func testNaturalAndControlledSkyfallShareOneSkyfallTotal() {
        let controller = ComboController()

        _ = controller.add(type: .wood, groups: 3, source: .manual)
        _ = controller.add(type: .water, groups: 2, source: .skyfall)
        _ = controller.add(type: .dark, groups: 4, source: .skyfall)

        XCTAssertEqual(controller.manualComboCount, 3)
        XCTAssertEqual(controller.skyfallComboCount, 6)
        XCTAssertEqual(controller.comboCount, 9)
        XCTAssertEqual(controller.breakdownText, "COMBO 9 (3 + 6)")
    }

    func testSkyfallSettingOffStillDisplaysNaturalSkyfallBreakdown() {
        let effectiveTarget = GameSettings.effectiveSkyfallComboCount(
            enabled: false,
            configured: 19
        )
        let controller = ComboController()

        _ = controller.add(type: .fire, groups: 5, source: .manual)
        _ = controller.add(type: .heart, groups: 2, source: .skyfall)

        XCTAssertEqual(effectiveTarget, 0)
        XCTAssertEqual(controller.breakdownText, "COMBO 7 (5 + 2)")
    }

    func testInitialTShapeAddsExactlyOneManualCombo() {
        let tShape = Set(
            (0...2).map { GridPosition(row: 1, column: $0) }
                + (0...2).map { GridPosition(row: $0, column: 1) }
        )
        let matches = MatchDetector().detect(in: gridWithHeart(at: tShape))
        let controller = ComboController()

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(controller.add(matches, source: .manual), 1)
        XCTAssertEqual(controller.manualComboCount, 1)
        XCTAssertEqual(controller.skyfallComboCount, 0)
        XCTAssertEqual(controller.breakdownText, "COMBO 1 (1 + 0)")
        XCTAssertEqual(controller.manualComboByType[.heart], 1)
    }

    func testSkyfallResetClearsSevenOfNineteenProgress() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 19)
        XCTAssertTrue(controller.recordDetectedGroups(7))
        XCTAssertEqual(controller.generatedCombos, 7)

        controller.reset(requestedCombos: 19)

        XCTAssertEqual(controller.generatedCombos, 0)
        XCTAssertEqual(controller.requestedCombos, 19)
    }

    func testFriendlyRefillProbabilityTableUsesGroupCount() {
        let expected = [0.50, 0.45, 0.40, 0.35, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05]

        XCTAssertEqual(FriendlyNaturalSkyfallPolicy.maximumGroupCount, 10)
        for (offset, probability) in expected.enumerated() {
            XCTAssertEqual(
                FriendlyNaturalSkyfallPolicy.refillProbability(for: offset + 1),
                Optional(probability)
            )
        }
        XCTAssertNil(FriendlyNaturalSkyfallPolicy.refillProbability(for: 0))
        XCTAssertNil(FriendlyNaturalSkyfallPolicy.refillProbability(for: 11))
    }

    func testFriendlyCandidateMaxUsesPreviousGroupsAndPhysicalLimit() {
        let cases = [
            (previous: 8, slots: 24, physical: 8, candidate: 8),
            (previous: 8, slots: 17, physical: 5, candidate: 5),
            (previous: 3, slots: 24, physical: 8, candidate: 3)
        ]

        for item in cases {
            var attemptedGroups: [Int] = []
            let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
                previousResolvedGroupCount: item.previous,
                emptySlotCount: item.slots,
                roll: { groupCount in attemptedGroups.append(groupCount); return 0.0 }
            )
            XCTAssertEqual(decision.physicalMaxGroups, item.physical)
            XCTAssertEqual(decision.candidateMaxGroups, item.candidate)
            XCTAssertEqual(decision.rolls.first?.groupCount, item.candidate)
            XCTAssertFalse(attemptedGroups.contains { $0 > item.candidate })
        }
    }

    func testFriendlyDescendingFirstSuccessSelectsThreeAndStops() {
        var attemptedGroups: [Int] = []
        let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 5,
            emptySlotCount: 15,
            roll: { groupCount in
                attemptedGroups.append(groupCount)
                switch groupCount {
                case 5, 4: return 0.99
                case 3: return 0.10
                default: return 0.0
                }
            }
        )

        XCTAssertEqual(decision.selectedTarget, 3)
        XCTAssertEqual(attemptedGroups, [5, 4, 3])
        XCTAssertEqual(decision.rolls.map(\.groupCount), [5, 4, 3])
    }

    func testFriendlyAllCandidatesCanFailAndSelectZero() {
        var attemptedGroups: [Int] = []
        let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 5,
            emptySlotCount: 15,
            roll: { groupCount in
                attemptedGroups.append(groupCount)
                return 0.999
            }
        )

        XCTAssertEqual(decision.selectedTarget, 0)
        XCTAssertEqual(attemptedGroups, [5, 4, 3, 2, 1])
        XCTAssertEqual(decision.rolls.last?.groupCount, 1)
        XCTAssertEqual(decision.rolls.last?.roll, 0.999)
        XCTAssertFalse(decision.rolls.last?.succeeded == true)
    }

    func testFriendlyOneGroupCanContinueOrStop() {
        let success = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 1,
            emptySlotCount: 3,
            roll: { _ in 0.49 }
        )
        let failure = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 1,
            emptySlotCount: 3,
            roll: { _ in 0.50 }
        )

        XCTAssertEqual(success.candidateMaxGroups, 1)
        XCTAssertEqual(success.selectedTarget, 1)
        XCTAssertEqual(success.rolls.map(\.groupCount), [1])
        XCTAssertEqual(failure.candidateMaxGroups, 1)
        XCTAssertEqual(failure.selectedTarget, 0)
        XCTAssertEqual(failure.rolls.map(\.groupCount), [1])
    }

    func testFriendlySelectionWithNoCandidateSelectsZeroWithoutRolling() {
        var didRoll = false
        let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 0,
            emptySlotCount: 3,
            roll: { _ in didRoll = true; return 0.0 }
        )

        XCTAssertEqual(decision.candidateMaxGroups, 0)
        XCTAssertEqual(decision.selectedTarget, 0)
        XCTAssertTrue(decision.rolls.isEmpty)
        XCTAssertFalse(didRoll)
    }

    func testFriendlySelectionSkipsWhenFewerThanThreeSlotsExist() {
        let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 8,
            emptySlotCount: 2,
            roll: { _ in XCTFail("Should not roll"); return 0.0 }
        )

        XCTAssertEqual(decision.physicalMaxGroups, 0)
        XCTAssertEqual(decision.candidateMaxGroups, 0)
        XCTAssertEqual(decision.selectedTarget, 0)
    }

    func testZeroTargetRefillsEveryEmptySlotForMatchSizesThreeThroughSix() {
        for matchSize in 3...6 {
            var generator = SeededGenerator(seed: UInt64(700 + matchSize))
            var board = stableBoardTypes()
            for column in 0..<matchSize { board[4][column] = .fire }
            if matchSize < OrbGrid.defaultColumns { board[4][matchSize] = .water }
            let grid = OrbGrid(types: board)
            let result = ResolveResult(matches: MatchDetector().detect(in: grid))

            XCTAssertEqual(result.comboCount, 1, "size=\(matchSize)")
            XCTAssertEqual(result.removedOrbCount, matchSize, "size=\(matchSize)")
            XCTAssertEqual(grid.remove(result.removedPositions).count, matchSize, "size=\(matchSize)")
            _ = grid.collapse()
            let slots = grid.emptyPositions()
            let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
                previousResolvedGroupCount: result.comboCount,
                emptySlotCount: slots.count,
                roll: { _ in 0.99 }
            )
            XCTAssertEqual(decision.selectedTarget, 0, "size=\(matchSize)")

            guard let assignments = SkyfallController().makeNonForcedRefill(
                grid: grid,
                refillSlots: slots,
                using: &generator
            ) else {
                XCTFail("Expected complete non-forced refill for size \(matchSize)")
                continue
            }
            let spawns = grid.refill(types: assignments, at: slots)

            XCTAssertEqual(slots.count, matchSize, "size=\(matchSize)")
            XCTAssertEqual(assignments.count, matchSize, "size=\(matchSize)")
            XCTAssertEqual(spawns.count, matchSize, "size=\(matchSize)")
            XCTAssertEqual(grid.emptyPositions().count, 0, "size=\(matchSize)")
            XCTAssertEqual(allOrbIDs(in: grid).count, 30, "size=\(matchSize)")
        }
    }

    func testOneTargetWithFiveRemovedOrbsStillRefillsAllFiveSlots() {
        var generator = SeededGenerator(seed: 805)
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 5))
        let result = ResolveResult(matches: MatchDetector().detect(in: grid))
        _ = grid.remove(result.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        let controller = SkyfallController()
        let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: result.comboCount,
            emptySlotCount: slots.count,
            roll: { _ in 0.49 }
        )

        XCTAssertEqual(decision.selectedTarget, 1)
        guard let plan = controller.makeFriendlyNaturalRefill(
            grid: grid,
            refillSlots: slots,
            targetGroupCount: decision.selectedTarget,
            using: &generator
        ) else {
            XCTFail("Expected one-group friendly plan for five empty slots")
            return
        }
        let spawns = grid.refill(types: plan.types, at: slots)

        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(plan.types.count, 5)
        XCTAssertEqual(spawns.count, 5)
        XCTAssertEqual(grid.emptyPositions().count, 0)
        XCTAssertEqual(allOrbIDs(in: grid).count, 30)
    }

    func testNormalizedFiveOrbShapesRefillFiveSlotsAtZeroTarget() {
        let shapes: [Set<GridPosition>] = [
            [
                GridPosition(row: 2, column: 1), GridPosition(row: 2, column: 2),
                GridPosition(row: 2, column: 3), GridPosition(row: 1, column: 2),
                GridPosition(row: 0, column: 2)
            ],
            [
                GridPosition(row: 0, column: 0), GridPosition(row: 1, column: 0),
                GridPosition(row: 2, column: 0), GridPosition(row: 2, column: 1),
                GridPosition(row: 2, column: 2)
            ],
            [
                GridPosition(row: 2, column: 1), GridPosition(row: 2, column: 2),
                GridPosition(row: 2, column: 3), GridPosition(row: 1, column: 2),
                GridPosition(row: 3, column: 2)
            ]
        ]

        for (index, positions) in shapes.enumerated() {
            var generator = SeededGenerator(seed: UInt64(900 + index))
            let grid = OrbGrid(types: stableBoardTypes())
            let result = ResolveResult(matches: [MatchResult(type: .light, positions: positions)])
            XCTAssertEqual(result.comboCount, 1)
            XCTAssertEqual(result.removedOrbCount, 5)
            _ = grid.remove(result.removedPositions)
            _ = grid.collapse()
            let slots = grid.emptyPositions()
            let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
                previousResolvedGroupCount: result.comboCount,
                emptySlotCount: slots.count,
                roll: { _ in 0.99 }
            )
            XCTAssertEqual(decision.selectedTarget, 0, "shape=\(index)")
            guard let assignments = SkyfallController().makeNonForcedRefill(
                grid: grid,
                refillSlots: slots,
                using: &generator
            ) else {
                XCTFail("Expected complete shape refill index=\(index)")
                continue
            }
            let spawns = grid.refill(types: assignments, at: slots)
            XCTAssertEqual(assignments.count, 5, "shape=\(index)")
            XCTAssertEqual(spawns.count, 5, "shape=\(index)")
            XCTAssertEqual(grid.emptyPositions().count, 0, "shape=\(index)")
            XCTAssertEqual(allOrbIDs(in: grid).count, 30, "shape=\(index)")
        }
    }

    func testMultipleGroupsRefillUnionOfAllEightRemovedPositions() {
        var generator = SeededGenerator(seed: 1_008)
        let grid = OrbGrid(types: stableBoardTypes())
        let matches = [
            MatchResult(
                type: .water,
                positions: Set((0..<3).map { GridPosition(row: 0, column: $0) })
            ),
            MatchResult(
                type: .fire,
                positions: Set((0..<5).map { GridPosition(row: 2, column: $0) })
            )
        ]
        let result = ResolveResult(matches: matches)
        XCTAssertEqual(result.comboCount, 2)
        XCTAssertEqual(result.removedOrbCount, 8)
        _ = grid.remove(result.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        let decision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: result.comboCount,
            emptySlotCount: slots.count,
            roll: { _ in 0.99 }
        )
        XCTAssertEqual(decision.selectedTarget, 0)
        guard let assignments = SkyfallController().makeNonForcedRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        ) else {
            XCTFail("Expected complete eight-slot non-forced refill")
            return
        }
        let spawns = grid.refill(types: assignments, at: slots)
        XCTAssertEqual(slots.count, 8)
        XCTAssertEqual(assignments.count, 8)
        XCTAssertEqual(spawns.count, 8)
        XCTAssertEqual(grid.emptyPositions().count, 0)
        XCTAssertEqual(allOrbIDs(in: grid).count, 30)
    }

    func testControlledModeNeverUsesFriendlyRefillProbability() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 3)
        var didRoll = false

        XCTAssertNil(controller.selectFriendlyRefillTarget(
            previousResolvedGroupCount: 8,
            emptySlotCount: 24,
            roll: { _ in didRoll = true; return 0.0 }
        ))
        XCTAssertFalse(didRoll)
    }

    func testActualResolvedGroupsDetermineNextFriendlyCandidateMaximum() {
        let manualDecision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 8,
            emptySlotCount: 24,
            roll: { groupCount in groupCount == 5 ? 0.0 : 0.99 }
        )
        let nextDecision = FriendlyNaturalSkyfallPolicy.selectTarget(
            previousResolvedGroupCount: 5,
            emptySlotCount: 24,
            roll: { _ in 0.0 }
        )

        XCTAssertEqual(manualDecision.selectedTarget, 5)
        XCTAssertEqual(nextDecision.candidateMaxGroups, 5)
        XCTAssertEqual(nextDecision.rolls.first?.groupCount, 5)
    }

    func testFriendlyNaturalRefillCreatesPlannedRealMatchWithoutChangingExistingOrbs() {
        var generator = SeededGenerator(seed: 410)
        let grid = OrbGrid(types: boardWithHorizontalMatch(length: 3))
        let result = ResolveResult(matches: MatchDetector().detect(in: grid))
        _ = grid.remove(result.removedPositions)
        _ = grid.collapse()
        let existing = Dictionary(uniqueKeysWithValues: grid.cells
            .flatMap { $0 }
            .compactMap { $0 }
            .map { ($0.id, $0.type) })
        let slots = grid.emptyPositions()
        let controller = SkyfallController()
        controller.reset(requestedCombos: 0)

        guard let plan = controller.makeFriendlyNaturalRefill(
            grid: grid,
            refillSlots: slots,
            targetGroupCount: 1,
            using: &generator
        ) else {
            XCTFail("Expected Friendly Natural refill plan")
            return
        }
        _ = grid.refill(types: plan.types, at: slots)
        let detected = MatchDetector().detect(in: grid)
        let after = Dictionary(uniqueKeysWithValues: grid.cells
            .flatMap { $0 }
            .compactMap { $0 }
            .filter { existing[$0.id] != nil }
            .map { ($0.id, $0.type) })

        XCTAssertEqual(detected.count, 1)
        XCTAssertEqual(plan.plannedTarget, 1)
        XCTAssertEqual(after, existing)
    }

    func testPerElementHUDCountsNormalizedManualAndSkyfallGroups() {
        let controller = ComboController()
        let manualCounts: [OrbType: Int] = [
            .water: 1, .fire: 2, .wood: 1,
            .light: 2, .dark: 1, .heart: 1
        ]
        let skyfallCounts: [OrbType: Int] = [
            .water: 1, .fire: 0, .wood: 1,
            .light: 0, .dark: 1, .heart: 0
        ]

        for type in OrbType.resolveOrder {
            _ = controller.add(type: type, groups: manualCounts[type, default: 0], source: .manual)
            _ = controller.add(type: type, groups: skyfallCounts[type, default: 0], source: .skyfall)
        }

        XCTAssertEqual(controller.manualComboCount, 8)
        XCTAssertEqual(controller.skyfallComboCount, 3)
        XCTAssertEqual(controller.comboCount, 11)
        XCTAssertEqual(controller.breakdownText, "COMBO 11 (8 + 3)")
        XCTAssertEqual(controller.breakdownText(for: .water), "水：1 + 1")
        XCTAssertEqual(controller.breakdownText(for: .fire), "火：2 + 0")
        XCTAssertEqual(controller.breakdownText(for: .wood), "木：1 + 1")
        XCTAssertEqual(controller.breakdownText(for: .light), "光：2 + 0")
        XCTAssertEqual(controller.breakdownText(for: .dark), "暗：1 + 1")
        XCTAssertEqual(controller.breakdownText(for: .heart), "心：1 + 0")
        XCTAssertEqual(controller.manualComboByType.values.reduce(0, +), controller.manualComboCount)
        XCTAssertEqual(controller.skyfallComboByType.values.reduce(0, +), controller.skyfallComboCount)
    }

    func testDisconnectedSameTypeGroupsIncrementThatTypeTwice() {
        let controller = ComboController()
        let waterGroups = [
            makeMatch(type: .water, group: 0),
            makeMatch(type: .water, group: 2)
        ]

        XCTAssertEqual(controller.add(waterGroups, source: .manual), 2)
        XCTAssertEqual(controller.manualComboByType[.water], 2)
        XCTAssertEqual(controller.breakdownText(for: .water), "水：2 + 0")
    }

    func testSessionStatisticsAveragesCompletedTurnsAndFormatsHUD() {
        var statistics = SessionStatistics()
        let turns: [(time: TimeInterval, manual: Int, skyfall: Int, water: Int)] = [
            (8.0, 6, 2, 2),
            (10.0, 5, 2, 0),
            (10.5, 7, 1, 1)
        ]

        for (index, turn) in turns.enumerated() {
            XCTAssertTrue(statistics.commitCompletedTurn(
                resolveID: UInt(index + 1),
                moveTime: turn.time,
                manualCombo: turn.manual,
                skyfallCombo: turn.skyfall,
                comboTotalByType: [.water: turn.water]
            ))
        }

        XCTAssertEqual(statistics.completedTurnCount, 3)
        XCTAssertEqual(statistics.averageTurnTime, 9.5, accuracy: 0.000_1)
        XCTAssertEqual(statistics.averageTotalCombo, 7.666_666, accuracy: 0.000_1)
        XCTAssertEqual(statistics.averageManualCombo, 6.0, accuracy: 0.000_1)
        XCTAssertEqual(statistics.averageSkyfallCombo, 1.666_666, accuracy: 0.000_1)
        XCTAssertEqual(statistics.averageCombo(for: .water), 1.0, accuracy: 0.000_1)
        XCTAssertEqual(GameplayStatusHUDText.game(completedTurnCount: 3), "Game 3")
        XCTAssertEqual(
            GameplayStatusHUDText.time(current: 10.5, average: statistics.averageTurnTime),
            "Time 10.5 [9.5]"
        )
        XCTAssertEqual(
            GameplayStatusHUDText.combo(
                currentBreakdown: "COMBO 8 (6 + 2)",
                averageManual: statistics.averageManualCombo,
                averageSkyfall: statistics.averageSkyfallCombo
            ),
            "COMBO 8 (6 + 2) [6.0 + 1.7]"
        )
        XCTAssertEqual(
            GameplayStatusHUDText.combo(
                currentBreakdown: "COMBO 20 (5 + 15)",
                averageManual: 5.8,
                averageSkyfall: 16.8
            ),
            "COMBO 20 (5 + 15) [5.8 + 16.8]"
        )
        XCTAssertEqual(
            GameplayStatusHUDText.orbType(
                currentBreakdown: "水：1 + 0",
                average: statistics.averageCombo(for: .water)
            ),
            "水：1 + 0 [1.0]"
        )
    }

    func testSessionStatisticsCommitsEachResolveOnlyOnce() {
        var statistics = SessionStatistics()

        XCTAssertTrue(statistics.commitCompletedTurn(
            resolveID: 7,
            moveTime: 4.0,
            manualCombo: 7,
            skyfallCombo: 7,
            comboTotalByType: [.water: 3]
        ))
        XCTAssertFalse(statistics.commitCompletedTurn(
            resolveID: 7,
            moveTime: 4.0,
            manualCombo: 7,
            skyfallCombo: 7,
            comboTotalByType: [.water: 3]
        ))

        XCTAssertEqual(statistics.completedTurnCount, 1)
        XCTAssertEqual(statistics.averageTurnTime, 4.0)
        XCTAssertEqual(statistics.averageTotalCombo, 14.0)
        XCTAssertEqual(statistics.averageManualCombo, 7.0)
        XCTAssertEqual(statistics.averageSkyfallCombo, 7.0)
        XCTAssertEqual(statistics.averageCombo(for: .water), 3.0)
    }

    func testSessionStatisticsZeroSampleAndNewGameResetAreSafe() {
        var statistics = SessionStatistics()

        XCTAssertEqual(statistics.completedTurnCount, 0)
        XCTAssertEqual(statistics.averageTurnTime, 0)
        XCTAssertEqual(statistics.averageTotalCombo, 0)
        XCTAssertEqual(statistics.averageManualCombo, 0)
        XCTAssertEqual(statistics.averageSkyfallCombo, 0)
        XCTAssertEqual(statistics.averageCombo(for: .water), 0)
        XCTAssertEqual(
            GameplayStatusHUDText.time(current: 0, average: statistics.averageTurnTime),
            "Time 0.0 [0.0]"
        )
        XCTAssertEqual(GameplayStatusHUDText.game(completedTurnCount: 0), "Game 0")
        XCTAssertEqual(
            GameplayStatusHUDText.combo(
                currentBreakdown: "COMBO 0 (0 + 0)",
                averageManual: statistics.averageManualCombo,
                averageSkyfall: statistics.averageSkyfallCombo
            ),
            "COMBO 0 (0 + 0) [0.0 + 0.0]"
        )

        XCTAssertTrue(statistics.commitCompletedTurn(
            resolveID: 1,
            moveTime: 8,
            manualCombo: 4,
            skyfallCombo: 2,
            comboTotalByType: [.fire: 2]
        ))
        statistics.reset()

        XCTAssertEqual(statistics.completedTurnCount, 0)
        XCTAssertEqual(statistics.turnTimeSum, 0)
        XCTAssertEqual(statistics.totalComboSum, 0)
        XCTAssertEqual(statistics.manualComboSum, 0)
        XCTAssertEqual(statistics.skyfallComboSum, 0)
        XCTAssertTrue(statistics.comboTotalSumByType.values.allSatisfy { $0 == 0 })
        XCTAssertEqual(statistics.averageTurnTime, 0)
        XCTAssertEqual(statistics.averageTotalCombo, 0)
        XCTAssertEqual(statistics.averageManualCombo, 0)
        XCTAssertEqual(statistics.averageSkyfallCombo, 0)
        XCTAssertEqual(statistics.averageCombo(for: .fire), 0)
    }

    func testTouchWithoutValidMovementDoesNotCreateSessionAverageSample() {
        let timer = TurnController(duration: 30)
        var statistics = SessionStatistics()

        timer.select(orbID: UUID(), at: GridPosition(row: 0, column: 0), touchPosition: .zero)
        timer.endGesture()
        if let moveTime = timer.lastCompletedTurnTime {
            statistics.commitCompletedTurn(
                resolveID: 1,
                moveTime: moveTime,
                manualCombo: 0,
                skyfallCombo: 0,
                comboTotalByType: [:]
            )
        }

        XCTAssertEqual(statistics.completedTurnCount, 0)
        XCTAssertEqual(statistics.averageTurnTime, 0)
        XCTAssertEqual(statistics.averageTotalCombo, 0)
    }

    func testNewGameUsesConfiguredTurnDuration() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.configure(turnDuration: 20, noResolveDuringTurn: true, skyfallComboCount: 19)

        scene.startNewGame()

        XCTAssertEqual(scene.sessionSnapshot.remainingTime, 20, accuracy: 0.001)
        XCTAssertEqual(scene.sessionSnapshot.progress, 1, accuracy: 0.001)
        XCTAssertEqual(scene.sessionSnapshot.requestedSkyfall, 19)
        XCTAssertEqual(scene.sessionSnapshot.completedTurnCount, 0)
        XCTAssertEqual(scene.sessionSnapshot.averageTurnTime, 0)
        XCTAssertEqual(scene.sessionSnapshot.averageTotalCombo, 0)
        XCTAssertEqual(scene.sessionSnapshot.averageManualCombo, 0)
        XCTAssertEqual(scene.sessionSnapshot.averageSkyfallCombo, 0)
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

    func testSkyfallOffNaturalMatchStillRequiresResolve() {
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
        let friendlyDecision = controller.selectFriendlyRefillTarget(
            previousResolvedGroupCount: 1,
            emptySlotCount: slots.count,
            roll: { _ in 0.99 }
        )
        XCTAssertEqual(friendlyDecision?.selectedTarget, 0)
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
        XCTAssertTrue(controller.recordDetectedGroups(naturalMatches.count))
        XCTAssertEqual(controller.generatedCombos, 1)
        XCTAssertEqual(controller.remainingCombos, 0)
        XCTAssertFalse(controller.needsAnotherCycle)
    }

    func testSkyfallOffNaturalRefillWithNoMatchCanFinish() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 0)
        let grid = OrbGrid()
        let slots = grid.emptyPositions()
        let stableTypes = matchTestBoardTypes()
        var typeIndex = 0
        guard let refillTypes = controller.makeNaturalRefill(
            grid: grid,
            refillSlots: slots,
            typeProvider: {
                let position = slots[typeIndex]
                typeIndex += 1
                return stableTypes[position.row][position.column]
            }
        ) else {
            XCTFail("Expected an unfiltered natural refill")
            return
        }
        _ = grid.refill(types: refillTypes, at: slots)
        let stableBoard = StableBoardScan(matches: MatchDetector().detect(in: grid))

        XCTAssertFalse(controller.hasControlledTarget)
        XCTAssertFalse(controller.needsAnotherCycle)
        XCTAssertTrue(stableBoard.canFinishResolve)
        XCTAssertEqual(controller.generatedCombos, 0)
    }

    func testSkyfallOffNaturalRefillResolvesTwoDetectedGroups() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 0)
        let grid = OrbGrid()
        let slots = grid.emptyPositions()
        var naturalTypes = matchTestBoardTypes()
        for column in 0...2 { naturalTypes[0][column] = .water }
        for column in 3...5 { naturalTypes[4][column] = .fire }
        var typeIndex = 0
        guard let refillTypes = controller.makeNaturalRefill(
            grid: grid,
            refillSlots: slots,
            typeProvider: {
                let position = slots[typeIndex]
                typeIndex += 1
                return naturalTypes[position.row][position.column]
            }
        ) else {
            XCTFail("Expected an unfiltered natural refill")
            return
        }
        _ = grid.refill(types: refillTypes, at: slots)
        let naturalMatches = MatchDetector().detect(in: grid)
        let result = ResolveResult(matches: naturalMatches)

        XCTAssertEqual(naturalMatches.count, 2)
        XCTAssertFalse(StableBoardScan(matches: naturalMatches).canFinishResolve)
        XCTAssertEqual(result.comboCount, 2)
        XCTAssertEqual(result.phases.map(\.type), [.water, .fire])
        XCTAssertTrue(controller.recordDetectedGroups(naturalMatches.count))
        XCTAssertEqual(controller.generatedCombos, 2)
    }

    func testSkyfallOffNaturalChainAccumulatesUntilStable() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 0)
        let snapshots = [
            [makeMatch(type: .water, group: 0), makeMatch(type: .fire, group: 1)],
            [makeMatch(type: .wood, group: 2)],
            []
        ]
        var didFinish = false

        for matches in snapshots {
            let stableBoard = StableBoardScan(matches: matches)
            if stableBoard.canFinishResolve {
                didFinish = true
            } else {
                XCTAssertTrue(controller.recordDetectedGroups(matches.count))
            }
        }

        XCTAssertEqual(controller.generatedCombos, 3)
        XCTAssertTrue(didFinish)
        XCTAssertFalse(controller.needsAnotherCycle)
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
        let preservedTypes = Dictionary(uniqueKeysWithValues: grid.cells
            .flatMap { $0 }
            .compactMap { $0 }
            .filter { preservedIDs.contains($0.id) }
            .map { ($0.id, $0.type) })

        XCTAssertEqual(preservedIDs.count, 27)
        _ = grid.remove(result.removedPositions)
        _ = grid.collapse()
        let slots = grid.emptyPositions()
        let controller = SkyfallController()
        controller.reset(requestedCombos: 5)
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
        for row in grid.cells {
            for orb in row.compactMap({ $0 }) where preservedIDs.contains(orb.id) {
                XCTAssertEqual(orb.type, preservedTypes[orb.id])
            }
        }
    }

    func testControlledPlannerUsesSameGeneralAlgorithmAcrossSupportedTargets() {
        for requested in [1, 3, 5, 10, 19, 99] {
            var generator = SeededGenerator(seed: UInt64(requested))
            let grid = OrbGrid()
            let slots = grid.emptyPositions()
            let controller = SkyfallController()
            controller.reset(requestedCombos: requested)

            guard let types = controller.makeControlledRefill(
                grid: grid,
                refillSlots: slots,
                using: &generator
            ) else {
                XCTFail("Expected a controlled plan for target \(requested)")
                continue
            }
            XCTAssertEqual(types.count, slots.count)
            _ = grid.refill(types: types, at: slots)
            let matches = MatchDetector().detect(in: grid)

            XCTAssertGreaterThan(matches.count, 0)
            XCTAssertLessThanOrEqual(matches.count, requested)
            if requested == 1 {
                XCTAssertEqual(matches.count, 1)
            } else {
                XCTAssertGreaterThan(matches.count, 1)
            }
            XCTAssertTrue(controller.recordDetectedGroups(matches.count))
            XCTAssertEqual(controller.generatedCombos, matches.count)
        }
    }

    func testDetectedMultiGroupBatchesAdvanceByActualNormalizedCount() {
        let targetFive = SkyfallController()
        targetFive.reset(requestedCombos: 5)
        XCTAssertTrue(targetFive.recordDetectedGroups(2))
        XCTAssertEqual(targetFive.generatedCombos, 2)

        let targetTen = SkyfallController()
        targetTen.reset(requestedCombos: 10)
        XCTAssertTrue(targetTen.recordDetectedGroups(4))
        XCTAssertTrue(targetTen.recordDetectedGroups(3))
        XCTAssertEqual(targetTen.generatedCombos, 7)

        let targetNineteen = SkyfallController()
        targetNineteen.reset(requestedCombos: 19)
        XCTAssertTrue(targetNineteen.recordDetectedGroups(16))
        XCTAssertTrue(targetNineteen.recordDetectedGroups(3))
        XCTAssertEqual(targetNineteen.generatedCombos, 19)
        XCTAssertTrue(targetNineteen.isComplete)
    }

    func testTargetNinetyNinePlannerCanProduceMultiGroupBatchInOneCall() {
        var generator = SeededGenerator(seed: 99)
        let grid = OrbGrid()
        let slots = grid.emptyPositions()
        let controller = SkyfallController()
        controller.reset(requestedCombos: 99)

        guard let types = controller.makeControlledRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        ) else {
            XCTFail("Expected a bounded controlled plan")
            return
        }
        _ = grid.refill(types: types, at: slots)
        let matches = MatchDetector().detect(in: grid)

        XCTAssertGreaterThan(matches.count, 1)
        XCTAssertTrue(controller.recordDetectedGroups(matches.count))
        XCTAssertEqual(controller.generatedCombos, matches.count)
        XCTAssertLessThan(controller.generatedCombos, 99)
        XCTAssertTrue(controller.needsAnotherCycle)
    }

    func testExistingNaturalMatchCountsTowardExactControlledTarget() {
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
        let naturalMatches = MatchDetector().detect(in: grid)
        let controller = SkyfallController()
        controller.reset(requestedCombos: 10)
        var generator = SeededGenerator(seed: 10)

        XCTAssertEqual(naturalMatches.count, 1)
        XCTAssertEqual(naturalMatches.first?.type, .light)
        XCTAssertNil(controller.makeControlledRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        ))
        XCTAssertTrue(controller.recordDetectedGroups(naturalMatches.count))
        XCTAssertEqual(controller.generatedCombos, 1)
        XCTAssertEqual(controller.remainingCombos, 9)
        XCTAssertTrue(controller.needsAnotherCycle)
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

        XCTAssertEqual(outcome.cycleCount, 7)
        XCTAssertEqual(outcome.nextCycleCount, 6)
        XCTAssertEqual(outcome.lifecycle.finalRefillCount, 1)
        XCTAssertEqual(outcome.lifecycle.finishCount, 1)
        XCTAssertEqual(outcome.lifecycle.state, .finished)
    }

    func testSkyfallTwoAndNinetyNineUseTheSameFinalizationBoundary() {
        for (requested, expectedCycles) in [(2, 1), (99, 33)] {
            let outcome = simulateSkyfallFinalization(requested: requested)
            XCTAssertEqual(outcome.cycleCount, expectedCycles)
            XCTAssertEqual(outcome.nextCycleCount, expectedCycles - 1)
            XCTAssertEqual(outcome.lifecycle.finalRefillCount, 1)
            XCTAssertEqual(outcome.lifecycle.finishCount, 1)
        }
    }

    func testControlledTargetsFinishAtExactConfiguredTotal() {
        for target in [1, 3, 5, 10, 19, 99] {
            let controller = SkyfallController()
            controller.reset(requestedCombos: target)

            while controller.needsAnotherCycle {
                XCTAssertTrue(controller.recordDetectedGroups(
                    min(3, controller.remainingCombos)
                ))
            }

            XCTAssertEqual(controller.generatedCombos, target, "target=\(target)")
            XCTAssertEqual(controller.remainingCombos, 0, "target=\(target)")
            XCTAssertTrue(controller.isComplete, "target=\(target)")
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

    func testNaturalMatchesReduceRemainingExactTarget() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 3)

        XCTAssertTrue(controller.recordDetectedGroups(2))
        XCTAssertEqual(controller.generatedCombos, 2)
        XCTAssertEqual(controller.remainingCombos, 1)
        XCTAssertTrue(controller.needsAnotherCycle)

        XCTAssertTrue(controller.recordDetectedGroups(1))
        XCTAssertEqual(controller.generatedCombos, 3)
        XCTAssertEqual(controller.remainingCombos, 0)
        XCTAssertFalse(controller.needsAnotherCycle)
        XCTAssertTrue(controller.isComplete)
    }

    func testCompletedControlledTargetUsesSafeFinalizationBoundary() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 3)

        XCTAssertTrue(controller.recordDetectedGroups(3))
        XCTAssertTrue(controller.isComplete)
        XCTAssertFalse(controller.needsAnotherCycle)
        XCTAssertEqual(controller.generatedCombos, 3)
        XCTAssertEqual(controller.remainingCombos, 0)
    }

    func testSkyfallOffDoesNotPlanControlledGroupsButRecordsNaturalGroups() {
        let controller = SkyfallController()
        controller.reset(requestedCombos: 0)
        let grid = OrbGrid()
        let slots = grid.emptyPositions()
        var generator = SeededGenerator(seed: 0)

        XCTAssertFalse(controller.hasControlledTarget)
        XCTAssertNil(controller.makeControlledRefill(
            grid: grid,
            refillSlots: slots,
            using: &generator
        ))
        XCTAssertTrue(controller.recordDetectedGroups(2))
        XCTAssertEqual(controller.generatedCombos, 2)
    }

    func testEffectiveSkyfallZeroCannotFinishWhileNaturalMatchesRemain() {
        let effectiveTarget = GameSettings.effectiveSkyfallComboCount(
            enabled: false,
            configured: 19
        )
        var types = matchTestBoardTypes()
        for column in 0...2 { types[0][column] = .water }
        let stableBoard = StableBoardScan(matches: MatchDetector().detect(
            in: OrbGrid(types: types)
        ))

        XCTAssertEqual(effectiveTarget, 0)
        XCTAssertFalse(stableBoard.matches.isEmpty)
        XCTAssertFalse(stableBoard.canFinishResolve)
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
            XCTAssertTrue(controller.recordDetectedGroups(skyfall))
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
            XCTAssertTrue(controller.recordDetectedGroups(min(3, controller.remainingCombos)))
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
