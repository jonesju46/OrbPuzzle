import Foundation
import SpriteKit

final class RefillController {
    func refill(
        grid: OrbGrid,
        mode: DropMode,
        boardNode: SKNode,
        cellSize: CGSize,
        pointForPosition: (GridPosition) -> CGPoint
    ) -> (spawns: [OrbSpawn], nodes: [OrbNode], duration: TimeInterval) {
        let spawns = grid.refill { [weak grid] position in
            guard let grid else { return OrbType.allCases.randomElement() ?? .fire }
            return Self.randomType(mode: mode, grid: grid, at: position)
        }
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

    private static func randomType(mode: DropMode, grid: OrbGrid, at position: GridPosition) -> OrbType {
        guard mode == .highCombo else { return OrbType.allCases.randomElement() ?? .fire }
        var weights = Dictionary(uniqueKeysWithValues: OrbType.allCases.map { ($0, 1) })
        let candidates = [
            GridPosition(row: position.row - 1, column: position.column),
            GridPosition(row: position.row - 2, column: position.column),
            GridPosition(row: position.row, column: position.column - 1),
            GridPosition(row: position.row, column: position.column - 2)
        ].compactMap { grid.orb(at: $0)?.type }
        for type in candidates {
            weights[type, default: 1] += GameSettings.Tuning.highComboWeightMultiplier
        }
        let total = weights.values.reduce(0, +)
        var roll = Int.random(in: 0..<max(total, 1))
        for type in OrbType.allCases {
            roll -= weights[type, default: 1]
            if roll < 0 { return type }
        }
        return .fire
    }
}
