import SwiftUI

struct SettingsView: View {
    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.noResolveDuringTurnKey) private var noResolveDuringTurn = GameSettings.defaultNoResolveDuringTurn
    @AppStorage(GameSettings.skyfallComboCountKey) private var skyfallComboCount = GameSettings.defaultSkyfallComboCount

    var body: some View {
        Form {
            Section("Turn Time") {
                Stepper(value: $turnDuration, in: GameSettings.turnDurationRange, step: 1) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(Int(turnDuration)) seconds")
                            .foregroundStyle(.secondary)
                    }
                }
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
                Stepper(value: $skyfallComboCount, in: GameSettings.skyfallComboCountRange, step: 1) {
                    HStack {
                        Text("Guaranteed")
                        Spacer()
                        Text("\(skyfallComboCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("This is the exact number of additional match groups generated after the initial matches.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gameplay Settings")
    }
}

#Preview { NavigationStack { SettingsView() } }
