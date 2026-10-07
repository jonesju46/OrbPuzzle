import SwiftUI

struct SettingsView: View {
    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.cascadeRoundsKey) private var cascadeRounds = GameSettings.defaultCascadeRounds
    @AppStorage(GameSettings.dropModeKey) private var dropModeRaw = GameSettings.defaultDropMode
    @AppStorage(GameSettings.targetComboKey) private var targetCombo = GameSettings.defaultTargetCombo

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

            Section("Target Combo") {
                Stepper(value: $targetCombo, in: GameSettings.targetComboRange, step: 1) {
                    HStack {
                        Text("Goal")
                        Spacer()
                        Text("\(targetCombo)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Drop Mode") {
                Picker("Mode", selection: $dropModeRaw) {
                    ForEach(DropMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(dropModeRaw == DropMode.highCombo.rawValue
                     ? "Weighted RNG raises the chance of skyfall matches."
                     : "Each new orb uses independent, equal-probability RNG.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Cascade Rounds") {
                Stepper(value: $cascadeRounds, in: GameSettings.cascadeRoundsRange, step: 1) {
                    HStack {
                        Text("Maximum")
                        Spacer()
                        Text("\(cascadeRounds)")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Initial matches do not count. Resolution stops early when a round has no match.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gameplay Settings")
    }
}

#Preview { NavigationStack { SettingsView() } }
