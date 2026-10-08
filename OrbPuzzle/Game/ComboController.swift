import SpriteKit

enum ComboSource {
    case manual
    case skyfall
}

final class ComboController {
    private(set) var manualComboByType = ComboController.zeroedCounts()
    private(set) var skyfallComboByType = ComboController.zeroedCounts()

    var manualComboCount: Int { manualComboByType.values.reduce(0, +) }
    var skyfallComboCount: Int { skyfallComboByType.values.reduce(0, +) }
    var comboCount: Int { manualComboCount + skyfallComboCount }
    var comboTotalByType: [OrbType: Int] {
        Dictionary(uniqueKeysWithValues: OrbType.allCases.map { type in
            (type, manualComboByType[type, default: 0] + skyfallComboByType[type, default: 0])
        })
    }
    var breakdownText: String {
        "COMBO \(comboCount) (\(manualComboCount) + \(skyfallComboCount))"
    }

    func reset() {
        manualComboByType = ComboController.zeroedCounts()
        skyfallComboByType = ComboController.zeroedCounts()
    }

    @discardableResult
    func add(_ matches: [MatchResult], source: ComboSource = .manual) -> Int {
        for match in matches {
            _ = add(type: match.type, groups: 1, source: source)
        }
        return comboCount
    }

    @discardableResult
    func add(type: OrbType, groups: Int, source: ComboSource = .manual) -> Int {
        let increment = max(0, groups)
        switch source {
        case .manual:
            manualComboByType[type, default: 0] += increment
        case .skyfall:
            skyfallComboByType[type, default: 0] += increment
        }
        return comboCount
    }

    func breakdownText(for type: OrbType) -> String {
        let manual = manualComboByType[type, default: 0]
        let skyfall = skyfallComboByType[type, default: 0]
        return "\(type.hudDisplayName)：\(manual) + \(skyfall)"
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

    private static func zeroedCounts() -> [OrbType: Int] {
        Dictionary(uniqueKeysWithValues: OrbType.allCases.map { ($0, 0) })
    }
}
