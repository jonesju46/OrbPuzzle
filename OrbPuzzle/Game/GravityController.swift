import SpriteKit

final class GravityController {
    func apply(to grid: OrbGrid, nodes: [UUID: OrbNode], pointForPosition: (GridPosition) -> CGPoint) -> TimeInterval {
        let movements = grid.collapse()
        for movement in movements {
            nodes[movement.orb.id]?.run(.move(to: pointForPosition(movement.to), duration: GameSettings.Tuning.fallDuration))
        }
        return movements.isEmpty ? 0 : GameSettings.Tuning.fallDuration
    }
}
