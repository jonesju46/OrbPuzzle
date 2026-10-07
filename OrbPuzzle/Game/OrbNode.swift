import SpriteKit

final class OrbNode: SKShapeNode {
    let orbID: UUID
    let orbType: OrbType

    init(orb: Orb, diameter: CGFloat) {
        orbID = orb.id
        orbType = orb.type
        super.init()
        path = CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter), transform: nil)
        fillColor = Self.color(for: orb.type)
        strokeColor = .white.withAlphaComponent(0.72)
        lineWidth = max(2, diameter * 0.045)
        glowWidth = diameter * 0.035
        name = "orb-\(orb.id.uuidString)"

        let shine = SKShapeNode(circleOfRadius: diameter * 0.11)
        shine.fillColor = .white.withAlphaComponent(0.55)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -diameter * 0.18, y: diameter * 0.18)
        shine.isUserInteractionEnabled = false
        addChild(shine)
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
