import SpriteKit

final class RefillController {
    func refillEmptySlots(
        grid: OrbGrid,
        slots: [GridPosition],
        types: [OrbType],
        boardNode: SKNode,
        cellSize: CGSize,
        pointForPosition: (GridPosition) -> CGPoint
    ) -> (spawns: [OrbSpawn], nodes: [OrbNode], duration: TimeInterval) {
        let spawns = grid.refill(types: types, at: slots)
        let nodes = spawns.map { spawn -> OrbNode in
            let node = OrbNode(orb: spawn.orb, diameter: min(cellSize.width, cellSize.height) * 0.82)
            let destination = pointForPosition(spawn.destination)
            node.position = CGPoint(x: destination.x, y: pointForPosition(GridPosition(row: spawn.sourceRow, column: spawn.destination.column)).y)
            boardNode.addChild(node)
            node.run(.move(to: destination, duration: GameSettings.Tuning.refillDuration))
            return node
        }
        return (spawns, nodes, spawns.isEmpty ? 0 : GameSettings.Tuning.refillDuration)
    }
}
