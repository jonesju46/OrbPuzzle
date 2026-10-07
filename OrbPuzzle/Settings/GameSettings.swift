import Foundation

enum GameSettings {
    static let turnDurationKey = "turnDuration"
    static let noResolveDuringTurnKey = "noResolveDuringTurn"
    static let skyfallComboCountKey = "skyfallComboCount"

    static let defaultTurnDuration = 10.0
    static let defaultNoResolveDuringTurn = false
    static let defaultSkyfallComboCount = 15

    static let turnDurationRange = 5.0...99.0
    static let skyfallComboCountRange = 1...99

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
