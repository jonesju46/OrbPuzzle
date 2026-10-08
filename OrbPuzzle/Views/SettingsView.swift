import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case gameplay = "Gameplay"
    case battle = "Battle"

    var id: String { rawValue }
}

struct SettingsView: View {
    @State private var selectedTab = SettingsTab.gameplay

    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.turnTimeEnabledKey) private var turnTimeEnabled = GameSettings.defaultTurnTimeEnabled
    @AppStorage(GameSettings.noResolveDuringTurnKey) private var noResolveDuringTurn = GameSettings.defaultNoResolveDuringTurn
    @AppStorage(GameSettings.skyfallComboCountKey) private var skyfallComboCount = GameSettings.defaultSkyfallComboCount
    @AppStorage(GameSettings.skyfallComboEnabledKey) private var skyfallComboEnabled = GameSettings.defaultSkyfallComboEnabled

    @AppStorage(GameSettings.playerMaxHPKey) private var playerMaxHP = GameSettings.defaultPlayerMaxHP
    @AppStorage(GameSettings.monsterHPKey) private var monsterHP = GameSettings.defaultMonsterHP
    @AppStorage(GameSettings.monsterCDKey) private var monsterCD = GameSettings.defaultMonsterCD
    @AppStorage(GameSettings.monsterATKKey) private var monsterATK = GameSettings.defaultMonsterATK
    @AppStorage(GameSettings.card1AttributeKey) private var card1Attribute = OrbType.water.rawValue
    @AppStorage(GameSettings.card1ATKKey) private var card1ATK = GameSettings.defaultCardATK
    @AppStorage(GameSettings.card1HeartHealKey) private var card1HeartHeal = GameSettings.defaultCardHeartHealPercent
    @AppStorage(GameSettings.card2AttributeKey) private var card2Attribute = OrbType.fire.rawValue
    @AppStorage(GameSettings.card2ATKKey) private var card2ATK = GameSettings.defaultCardATK
    @AppStorage(GameSettings.card2HeartHealKey) private var card2HeartHeal = GameSettings.defaultCardHeartHealPercent
    @AppStorage(GameSettings.card3AttributeKey) private var card3Attribute = OrbType.wood.rawValue
    @AppStorage(GameSettings.card3ATKKey) private var card3ATK = GameSettings.defaultCardATK
    @AppStorage(GameSettings.card3HeartHealKey) private var card3HeartHeal = GameSettings.defaultCardHeartHealPercent
    @AppStorage(GameSettings.card4AttributeKey) private var card4Attribute = OrbType.light.rawValue
    @AppStorage(GameSettings.card4ATKKey) private var card4ATK = GameSettings.defaultCardATK
    @AppStorage(GameSettings.card4HeartHealKey) private var card4HeartHeal = GameSettings.defaultCardHeartHealPercent
    @AppStorage(GameSettings.card5AttributeKey) private var card5Attribute = OrbType.dark.rawValue
    @AppStorage(GameSettings.card5ATKKey) private var card5ATK = GameSettings.defaultCardATK
    @AppStorage(GameSettings.card5HeartHealKey) private var card5HeartHeal = GameSettings.defaultCardHeartHealPercent

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Form {
                switch selectedTab {
                case .gameplay:
                    gameplaySections
                case .battle:
                    battleSections
                }
            }
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private var gameplaySections: some View {
        Section("Turn Time") {
            Toggle("Turn Time", isOn: $turnTimeEnabled)
            Stepper(value: $turnDuration, in: GameSettings.turnDurationRange, step: 1) {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(Int(effectiveTurnDuration)) seconds")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!turnTimeEnabled)
        }

        Section("Turn Resolution") {
            Toggle("No Resolve During Turn", isOn: $noResolveDuringTurn)
            Text(noResolveDuringTurn
                 ? "Finger-up keeps the board and timer active. Resolution starts at zero."
                 : "Finger-up resolves immediately after the first valid move.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("Skyfall Combo") {
            Toggle("Skyfall Combo", isOn: $skyfallComboEnabled)
            Stepper(value: $skyfallComboCount, in: GameSettings.skyfallComboCountRange, step: 1) {
                HStack {
                    Text("Guaranteed")
                    Spacer()
                    Text("\(effectiveSkyfallComboCount) Combo")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!skyfallComboEnabled)
            Text(skyfallComboEnabled
                 ? "This is the exact number of additional match groups generated after the initial matches."
                 : "Controlled skyfall is off. Natural matches still resolve normally.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var battleSections: some View {
        Section("PLAYER") {
            ClampedIntegerField(
                title: "Player Max HP",
                value: $playerMaxHP,
                range: GameSettings.battleHPRange
            )
        }

        Section("MONSTER") {
            ClampedIntegerField(title: "HP", value: $monsterHP, range: GameSettings.battleHPRange)
            ClampedIntegerField(title: "CD", value: $monsterCD, range: GameSettings.monsterCDRange)
            ClampedIntegerField(title: "ATK", value: $monsterATK, range: GameSettings.battleAttackRange)
        }

        cardSection(title: "CARD 1", attribute: $card1Attribute, attack: $card1ATK, heartHeal: $card1HeartHeal)
        cardSection(title: "CARD 2", attribute: $card2Attribute, attack: $card2ATK, heartHeal: $card2HeartHeal)
        cardSection(title: "CARD 3", attribute: $card3Attribute, attack: $card3ATK, heartHeal: $card3HeartHeal)
        cardSection(title: "CARD 4", attribute: $card4Attribute, attack: $card4ATK, heartHeal: $card4HeartHeal)
        cardSection(title: "CARD 5", attribute: $card5Attribute, attack: $card5ATK, heartHeal: $card5HeartHeal)

        Section {
            Text("Battle changes are applied when the next New Game starts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func cardSection(
        title: String,
        attribute: Binding<String>,
        attack: Binding<Int>,
        heartHeal: Binding<Int>
    ) -> some View {
        Section {
            Picker("Attribute", selection: attribute) {
                ForEach(GameSettings.battleCardAttributes, id: \.self) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            }
            ClampedIntegerField(title: "ATK", value: attack, range: GameSettings.battleAttackRange)
            Stepper(value: heartHeal, in: 0...100, step: 1) {
                HStack {
                    Text("Heart Heal %")
                    Spacer()
                    Text("\(heartHeal.wrappedValue)%")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(title)
        }
    }

    private var effectiveTurnDuration: Double {
        GameSettings.effectiveTurnDuration(enabled: turnTimeEnabled, configured: turnDuration)
    }

    private var effectiveSkyfallComboCount: Int {
        GameSettings.effectiveSkyfallComboCount(enabled: skyfallComboEnabled, configured: skyfallComboCount)
    }
}

private struct ClampedIntegerField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent {
            TextField(title, value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(minWidth: 90)
                .onChange(of: value) { _, newValue in
                    let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                    if value != clamped { value = clamped }
                }
        } label: {
            Text(title)
        }
    }
}

#Preview { NavigationStack { SettingsView() } }
