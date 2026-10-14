import SpriteKit
import UIKit

final class OrbNode: SKShapeNode {
    static let glassRimName = "orb-glass-rim"
    static let hebrewLabelName = "orb-hebrew-label"

    private(set) var orbID: UUID
    private(set) var orbType: OrbType
    private let innerTint = SKShapeNode()
    private let innerRim = SKShapeNode()
    private let shine = SKShapeNode()
    private let hebrewLabel = SKLabelNode()
    private var configuredDiameter: CGFloat = 0

    init(orb: Orb, diameter: CGFloat) {
        orbID = orb.id
        orbType = orb.type
        super.init()
        isUserInteractionEnabled = false
        innerTint.isUserInteractionEnabled = false
        innerRim.name = Self.glassRimName
        innerRim.isUserInteractionEnabled = false
        shine.isUserInteractionEnabled = false
        hebrewLabel.name = Self.hebrewLabelName
        hebrewLabel.horizontalAlignmentMode = .center
        hebrewLabel.verticalAlignmentMode = .center
        hebrewLabel.isUserInteractionEnabled = false
        addChild(innerTint)
        addChild(innerRim)
        addChild(shine)
        addChild(hebrewLabel)
        configureGeometry(diameter: diameter)
        configureAppearance()
        resetTransientState()
    }

    func prepareForReuse(orb: Orb, diameter: CGFloat) {
        let typeChanged = orb.type != orbType
        orbID = orb.id
        orbType = orb.type
        if abs(configuredDiameter - diameter) > 0.01 {
            configureGeometry(diameter: diameter)
        }
        if typeChanged { configureAppearance() }
        resetTransientState()
    }

    private func configureAppearance() {
        let color = Self.color(for: orbType)
        fillColor = color.withAlphaComponent(0.80)
        strokeColor = .white.withAlphaComponent(0.78)
        innerTint.fillColor = color.withAlphaComponent(0.24)
        innerTint.strokeColor = .clear
        innerTint.zPosition = 1
        innerRim.fillColor = .clear
        innerRim.strokeColor = .white.withAlphaComponent(0.25)
        innerRim.zPosition = 2
        shine.fillColor = .white.withAlphaComponent(0.62)
        shine.strokeColor = .clear
        shine.zRotation = -.pi / 7
        shine.zPosition = 3
        hebrewLabel.text = orbType.hebrewLabel
        hebrewLabel.fontColor = orbType == .light
            ? SKColor(white: 0.16, alpha: 0.96)
            : .white.withAlphaComponent(0.98)
        hebrewLabel.zPosition = 4
    }

    private func configureGeometry(diameter: CGFloat) {
        configuredDiameter = diameter
        path = CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2,
            width: diameter, height: diameter), transform: nil)
        lineWidth = max(2, diameter * 0.045)
        glowWidth = diameter * 0.035
        innerTint.path = CGPath(ellipseIn: CGRect(x: -diameter * 0.39, y: -diameter * 0.39,
            width: diameter * 0.78, height: diameter * 0.78), transform: nil)
        innerTint.position = CGPoint(x: diameter * 0.045, y: -diameter * 0.06)
        innerRim.path = CGPath(ellipseIn: CGRect(x: -diameter * 0.43, y: -diameter * 0.43,
            width: diameter * 0.86, height: diameter * 0.86), transform: nil)
        innerRim.lineWidth = max(1, diameter * 0.018)
        shine.path = CGPath(ellipseIn: CGRect(
            x: -diameter * 0.16, y: -diameter * 0.075,
            width: diameter * 0.32, height: diameter * 0.15
        ), transform: nil)
        shine.position = CGPoint(x: -diameter * 0.17, y: diameter * 0.20)
        let font = UIFont(name: "ArialHebrew-Bold", size: diameter * 0.38)
            ?? UIFont.boldSystemFont(ofSize: diameter * 0.38)
        hebrewLabel.fontName = font.fontName
        hebrewLabel.fontSize = diameter * 0.38
        hebrewLabel.position = CGPoint(x: 0, y: -diameter * 0.015)
    }

    private func resetTransientState() {
        removeAllActions()
        name = "orb-\(orbID.uuidString)"
        alpha = 1
        setScale(1)
        zPosition = 0
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
