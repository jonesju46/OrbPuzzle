import SpriteKit

enum ComboSource {
    case manual
    case skyfall
}

final class ComboController {
    private(set) var manualComboCount = 0
    private(set) var skyfallComboCount = 0

    var comboCount: Int { manualComboCount + skyfallComboCount }
    var breakdownText: String {
        "COMBO \(comboCount)  (\(manualComboCount) com + skyfull \(skyfallComboCount) com)"
    }

    func reset() {
        manualComboCount = 0
        skyfallComboCount = 0
    }

    @discardableResult
    func add(_ matches: [MatchResult], source: ComboSource = .manual) -> Int {
        add(groups: matches.count, source: source)
    }

    @discardableResult
    func add(groups: Int, source: ComboSource = .manual) -> Int {
        let increment = max(0, groups)
        switch source {
        case .manual:
            manualComboCount += increment
        case .skyfall:
            skyfallComboCount += increment
        }
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
