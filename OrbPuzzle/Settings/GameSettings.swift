import Foundation

enum DropMode: String, CaseIterable, Identifiable {
    case normal
    case highCombo

    var id: String { rawValue }
    var title: String { self == .normal ? "Normal" : "High Combo" }
}

enum GameSettings {
    static let turnDurationKey = "turnDuration"
    static let cascadeRoundsKey = "cascadeRounds"
    static let dropModeKey = "dropMode"

    static let defaultTurnDuration = 10.0
    static let defaultCascadeRounds = 10
    static let defaultDropMode = DropMode.normal.rawValue

    static let turnDurationRange = 5.0...20.0
    static let cascadeRoundsRange = 1...99

    enum Tuning {
        static let highComboWeightMultiplier = 4
        static let swapDuration = 0.08
        static let removeDuration = 0.18
        static let fallDuration = 0.20
        static let refillDuration = 0.24
        static let comboDisplayDuration = 0.30
    }
}
