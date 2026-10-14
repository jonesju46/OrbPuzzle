import Foundation
import SpriteKit

final class GravityController {
    static let fallActionKey = "gravity-fall"

    func apply(to grid: OrbGrid, nodes: [UUID: OrbNode],
               pointForPosition: (GridPosition) -> CGPoint,
               completion: (() -> Void)? = nil) -> TimeInterval {
        let modelStart = GamePerformanceProfiler.timestamp
        let movements = grid.collapse()
        let modelMs = (GamePerformanceProfiler.timestamp - modelStart) * 1_000
        let animationStart = GamePerformanceProfiler.timestamp
        let actionStart = animationStart
        let movingNodes = movements.compactMap { movement in
            nodes[movement.orb.id].map { ($0, pointForPosition(movement.to)) }
        }
        guard !movingNodes.isEmpty else {
            GamePerformanceProfiler.shared.recordGravity(
                modelMs: modelMs, actionScheduleMs: 0, animationElapsedMs: 0)
            if let completion { DispatchQueue.main.async(execute: completion) }
            return 0
        }

        var remaining = movingNodes.count
        var actionScheduleMs = 0.0
        for (node, destination) in movingNodes {
            let move = SKAction.move(to: destination, duration: GameSettings.Tuning.fallDuration)
            guard completion != nil else {
                node.run(move, withKey: Self.fallActionKey)
                continue
            }
            node.run(.sequence([move, .run {
                remaining -= 1
                if remaining == 0 {
                    GamePerformanceProfiler.shared.recordGravity(
                        modelMs: modelMs,
                        actionScheduleMs: actionScheduleMs,
                        animationElapsedMs: (GamePerformanceProfiler.timestamp - animationStart) * 1_000)
                    completion?()
                }
            }]), withKey: Self.fallActionKey)
        }
        actionScheduleMs = (GamePerformanceProfiler.timestamp - actionStart) * 1_000
        if completion == nil {
            GamePerformanceProfiler.shared.recordGravity(
                modelMs: modelMs, actionScheduleMs: actionScheduleMs,
                animationElapsedMs: GameSettings.Tuning.fallDuration * 1_000)
        }
        return movements.isEmpty ? 0 : GameSettings.Tuning.fallDuration
    }
}
