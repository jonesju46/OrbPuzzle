import SpriteKit
import UIKit

final class OrbNode: SKShapeNode {
    static let glassRimName = "orb-glass-rim"
    static let hebrewLabelName = "orb-hebrew-label"

    let orbID: UUID
    let orbType: OrbType

    init(orb: Orb, diameter: CGFloat) {
        orbID = orb.id
        orbType = orb.type
        super.init()
        path = CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter), transform: nil)
        let color = Self.color(for: orb.type)
        fillColor = color.withAlphaComponent(0.80)
        strokeColor = .white.withAlphaComponent(0.78)
        lineWidth = max(2, diameter * 0.045)
        glowWidth = diameter * 0.035
        name = "orb-\(orb.id.uuidString)"
        isUserInteractionEnabled = false

        let innerTint = SKShapeNode(circleOfRadius: diameter * 0.39)
        innerTint.fillColor = color.withAlphaComponent(0.24)
        innerTint.strokeColor = .clear
        innerTint.position = CGPoint(x: diameter * 0.045, y: -diameter * 0.06)
        innerTint.zPosition = 1
        innerTint.isUserInteractionEnabled = false
        addChild(innerTint)

        let innerRim = SKShapeNode(circleOfRadius: diameter * 0.43)
        innerRim.name = Self.glassRimName
        innerRim.fillColor = .clear
        innerRim.strokeColor = .white.withAlphaComponent(0.25)
        innerRim.lineWidth = max(1, diameter * 0.018)
        innerRim.zPosition = 2
        innerRim.isUserInteractionEnabled = false
        addChild(innerRim)

        let shine = SKShapeNode(ellipseIn: CGRect(
            x: -diameter * 0.16, y: -diameter * 0.075,
            width: diameter * 0.32, height: diameter * 0.15
        ))
        shine.fillColor = .white.withAlphaComponent(0.62)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -diameter * 0.17, y: diameter * 0.20)
        shine.zRotation = -.pi / 7
        shine.zPosition = 3
        shine.isUserInteractionEnabled = false
        addChild(shine)

        let label = SKLabelNode(text: orb.type.hebrewLabel)
        let font = UIFont(name: "ArialHebrew-Bold", size: diameter * 0.38)
            ?? UIFont.boldSystemFont(ofSize: diameter * 0.38)
        label.name = Self.hebrewLabelName
        label.fontName = font.fontName
        label.fontSize = diameter * 0.38
        label.fontColor = orb.type == .light
            ? SKColor(white: 0.16, alpha: 0.96)
            : .white.withAlphaComponent(0.98)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -diameter * 0.015)
        label.zPosition = 4
        label.isUserInteractionEnabled = false
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func color(for type: OrbType) -> SKColor {
        switch type {
        case .fire: return SKColor(red: 0.94, green: 0.23, blue: 0.18, alpha: 1)
        case .water: return SKColor(red: 0.15, green: 0.54, blue: 0.96, alpha: 1)
        case .wood: return SKColor(red: 0.19, green: 0.76, blue: 0.35, alpha: 1)
        case .light: return SKColor(red: 0.98, green: 0.79, blue: 0.16, alpha: 1)
        case .dark: return SKColor(red: 0.46, green: 0.24, blue: 0.72, alpha: 1)
        case .heart: return SKColor(red: 0.96, green: 0.35, blue: 0.67, alpha: 1)
        }
    }
}
