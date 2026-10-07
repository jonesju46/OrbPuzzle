import SpriteKit

final class ComboController {
    private(set) var comboCount = 0

    func reset() { comboCount = 0 }

    @discardableResult
    func add(_ matches: [MatchResult]) -> Int {
        comboCount += matches.count
        return comboCount
    }

    func animate(label: SKLabelNode) {
        label.removeAllActions()
        label.text = "\(comboCount) Combo"
        label.setScale(0.75)
        label.alpha = 1
        label.run(.sequence([
            .scale(to: 1.18, duration: GameSettings.Tuning.comboDisplayDuration * 0.45),
            .scale(to: 1.0, duration: GameSettings.Tuning.comboDisplayDuration * 0.55)
        ]))
    }
}
