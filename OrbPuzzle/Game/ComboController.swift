import SpriteKit

final class ComboController {
    private(set) var comboCount = 0

    func reset() { comboCount = 0 }

    @discardableResult
    func add(_ matches: [MatchResult]) -> Int {
        add(groups: matches.count)
    }

    @discardableResult
    func add(groups: Int) -> Int {
        comboCount += max(0, groups)
        return comboCount
    }

    func animate(label: SKLabelNode) {
        label.removeAllActions()
        label.text = "Combo \(comboCount)"
        label.setScale(0.75)
        label.alpha = 1
        label.run(.sequence([
            .scale(to: 1.18, duration: GameSettings.Tuning.comboDisplayDuration * 0.45),
            .scale(to: 1.0, duration: GameSettings.Tuning.comboDisplayDuration * 0.55)
        ]))
    }
}
