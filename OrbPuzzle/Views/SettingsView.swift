import SwiftUI

struct SettingsView: View {
    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.turnTimeEnabledKey) private var turnTimeEnabled = GameSettings.defaultTurnTimeEnabled
    @AppStorage(GameSettings.noResolveDuringTurnKey) private var noResolveDuringTurn = GameSettings.defaultNoResolveDuringTurn
    @AppStorage(GameSettings.skyfallComboCountKey) private var skyfallComboCount = GameSettings.defaultSkyfallComboCount
    @AppStorage(GameSettings.skyfallComboEnabledKey) private var skyfallComboEnabled = GameSettings.defaultSkyfallComboEnabled

    var body: some View {
        Form {
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
        .navigationTitle("Gameplay Settings")
    }

    private var effectiveTurnDuration: Double {
        GameSettings.effectiveTurnDuration(enabled: turnTimeEnabled, configured: turnDuration)
    }

    private var effectiveSkyfallComboCount: Int {
        GameSettings.effectiveSkyfallComboCount(enabled: skyfallComboEnabled, configured: skyfallComboCount)
    }
}

#Preview { NavigationStack { SettingsView() } }
