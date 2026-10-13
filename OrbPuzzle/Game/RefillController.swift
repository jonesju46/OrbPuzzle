import SpriteKit

struct RefillAnimationDescriptor: Equatable {
    let orbID: UUID
    let start: CGPoint
    let end: CGPoint
    let duration: TimeInterval
}

struct RefillAnimationResult {
    let spawns: [OrbSpawn]
    let nodes: [OrbNode]
    let duration: TimeInterval
    let descriptors: [RefillAnimationDescriptor]
}

final class RefillController {
    static let fallActionKey = "refill-fall"

    func refillEmptySlots(
        grid: OrbGrid,
        slots: [GridPosition],
        types: [OrbType],
        boardNode: SKNode,
        cellSize: CGSize,
        pointForPosition: (GridPosition) -> CGPoint,
        friendlyPreparation: FriendlyRefillPreparation? = nil,
        completion: @escaping (RefillAnimationResult) -> Void = { _ in }
    ) -> RefillAnimationResult {
        let spawns: [OrbSpawn]
        if let friendlyPreparation {
            precondition(slots == friendlyPreparation.slots && types == friendlyPreparation.types)
            spawns = friendlyPreparation.refill(in: grid)
        } else {
            // ON mode keeps its existing exact-target refill path.
            spawns = grid.refill(types: types, at: slots)
        }
        let nodes = spawns.map { spawn -> OrbNode in
            let node = OrbNode(orb: spawn.orb, diameter: min(cellSize.width, cellSize.height) * 0.82)
            let destination = pointForPosition(spawn.destination)
            node.position = CGPoint(x: destination.x, y: pointForPosition(GridPosition(row: spawn.sourceRow, column: spawn.destination.column)).y)
            boardNode.addChild(node)
            return node
        }
        let descriptors = zip(spawns, nodes).map { spawn, node in
            RefillAnimationDescriptor(orbID: spawn.orb.id, start: node.position,
                end: pointForPosition(spawn.destination), duration: GameSettings.Tuning.refillDuration)
        }
        let result = RefillAnimationResult(spawns: spawns, nodes: nodes,
            duration: spawns.isEmpty ? 0 : GameSettings.Tuning.refillDuration,
            descriptors: descriptors)
        guard !nodes.isEmpty else {
            completion(result)
            return result
        }
        var remaining = nodes.count
        for (node, descriptor) in zip(nodes, descriptors) {
            let action = SKAction.sequence([
                .move(to: descriptor.end, duration: descriptor.duration),
                .run {
                    remaining -= 1
                    if remaining == 0 { completion(result) }
                }
            ])
            node.run(action, withKey: Self.fallActionKey)
        }
        return result
    }
}
