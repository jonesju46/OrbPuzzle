final class CascadeController {
    private(set) var completedRounds = 0
    var maximumRounds: Int

    init(maximumRounds: Int) {
        self.maximumRounds = min(max(maximumRounds, GameSettings.cascadeRoundsRange.lowerBound), GameSettings.cascadeRoundsRange.upperBound)
    }

    func reset(maximumRounds: Int) {
        self.maximumRounds = min(max(maximumRounds, GameSettings.cascadeRoundsRange.lowerBound), GameSettings.cascadeRoundsRange.upperBound)
        completedRounds = 0
    }

    func beginNextRound() -> Bool {
        guard completedRounds < maximumRounds else { return false }
        completedRounds += 1
        return true
    }
}
