import CoreGraphics
import Foundation

final class TurnController {
    private(set) var selectedOrbID: UUID?
    private(set) var currentPosition: GridPosition?
    private(set) var previousTouchPosition: CGPoint?
    private(set) var turnStartTime: TimeInterval?
    private(set) var remainingTime: TimeInterval
    private(set) var elapsedTurnTime: TimeInterval = 0
    private(set) var lastCompletedTurnTime: TimeInterval?

    var duration: TimeInterval {
        didSet {
            duration = min(max(duration, GameSettings.turnDurationRange.lowerBound), GameSettings.turnDurationRange.upperBound)
            if turnStartTime == nil { remainingTime = duration }
        }
    }

    var isTiming: Bool { turnStartTime != nil }
    var hasActiveGesture: Bool { selectedOrbID != nil }
    var progress: Double { duration > 0 ? min(max(remainingTime / duration, 0), 1) : 0 }
    var displayedElapsedTurnTime: TimeInterval {
        isTiming ? elapsedTurnTime : (lastCompletedTurnTime ?? 0)
    }

    init(duration: TimeInterval) {
        self.duration = min(max(duration, GameSettings.turnDurationRange.lowerBound), GameSettings.turnDurationRange.upperBound)
        remainingTime = self.duration
    }

    func select(orbID: UUID, at gridPosition: GridPosition, touchPosition: CGPoint) {
        selectedOrbID = orbID
        currentPosition = gridPosition
        previousTouchPosition = touchPosition
        if turnStartTime == nil, remainingTime > 0 {
            remainingTime = duration
        }
    }

    func beginTiming(at currentTime: TimeInterval) {
        guard turnStartTime == nil else { return }
        turnStartTime = currentTime
        remainingTime = duration
        elapsedTurnTime = 0
        lastCompletedTurnTime = nil
    }

    @discardableResult
    func update(at currentTime: TimeInterval) -> Bool {
        guard let turnStartTime else { return false }
        remainingTime = max(0, duration - (currentTime - turnStartTime))
        elapsedTurnTime = min(max(duration - remainingTime, 0), duration)
        return remainingTime <= 0
    }

    func advance(to position: GridPosition) {
        currentPosition = position
    }

    func rememberTouch(_ point: CGPoint) {
        previousTouchPosition = point
    }

    /// Ends only the current finger gesture. An active timed session continues.
    func endGesture() {
        selectedOrbID = nil
        currentPosition = nil
        previousTouchPosition = nil
    }

    /// Stops a player-ended turn while preserving both its remaining and elapsed time.
    func completeSession() {
        guard turnStartTime != nil else {
            endGesture()
            return
        }
        lastCompletedTurnTime = elapsedTurnTime
        endGesture()
        turnStartTime = nil
    }

    /// Locks an expired session at zero while match resolution is running.
    func expireSession() {
        endGesture()
        turnStartTime = nil
        remainingTime = 0
        elapsedTurnTime = duration
        lastCompletedTurnTime = duration
    }

    /// Prepares the next turn without erasing the completed turn's HUD result.
    func prepareNextSession() {
        endGesture()
        turnStartTime = nil
        remainingTime = duration
        elapsedTurnTime = 0
    }

    /// Clears all transient timing state for a genuinely new game.
    func resetSession() {
        endGesture()
        turnStartTime = nil
        remainingTime = duration
        elapsedTurnTime = 0
        lastCompletedTurnTime = nil
    }

    static func gridPosition(
        for point: CGPoint,
        boardFrame: CGRect,
        rows: Int,
        columns: Int
    ) -> GridPosition? {
        guard rows > 0, columns > 0, boardFrame.width > 0, boardFrame.height > 0,
              boardFrame.contains(point) else { return nil }
        let cellWidth = boardFrame.width / CGFloat(columns)
        let cellHeight = boardFrame.height / CGFloat(rows)
        return GridPosition(
            row: min(max(Int((point.y - boardFrame.minY) / cellHeight), 0), rows - 1),
            column: min(max(Int((point.x - boardFrame.minX) / cellWidth), 0), columns - 1)
        )
    }

    /// Returns every board cell crossed by a segment, in order. Exact corner crossings
    /// become a direct diagonal step, which preserves the game's eight-direction rule.
    static func traversedPositions(
        from start: CGPoint,
        to end: CGPoint,
        boardFrame: CGRect,
        rows: Int,
        columns: Int
    ) -> [GridPosition] {
        guard rows > 0, columns > 0, boardFrame.width > 0, boardFrame.height > 0 else { return [] }
        let cellWidth = boardFrame.width / CGFloat(columns)
        let cellHeight = boardFrame.height / CGFloat(rows)

        guard var current = gridPosition(for: start, boardFrame: boardFrame, rows: rows, columns: columns) else { return [] }
        let clampedEnd = CGPoint(
            x: min(max(end.x, boardFrame.minX.nextUp), boardFrame.maxX.nextDown),
            y: min(max(end.y, boardFrame.minY.nextUp), boardFrame.maxY.nextDown)
        )
        guard let target = gridPosition(for: clampedEnd, boardFrame: boardFrame, rows: rows, columns: columns) else { return [current] }
        var result = [current]
        if current == target { return result }
        // If one touch sample moves directly into any neighboring cell, preserve that
        // exact eight-direction gesture (including a diagonal corner-to-corner swap).
        if current.isAdjacent(to: target) { return [current, target] }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let stepColumn = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
        let stepRow = dy > 0 ? 1 : (dy < 0 ? -1 : 0)
        let infinity = CGFloat.greatestFiniteMagnitude

        let nextVertical = stepColumn > 0
            ? boardFrame.minX + CGFloat(current.column + 1) * cellWidth
            : boardFrame.minX + CGFloat(current.column) * cellWidth
        let nextHorizontal = stepRow > 0
            ? boardFrame.minY + CGFloat(current.row + 1) * cellHeight
            : boardFrame.minY + CGFloat(current.row) * cellHeight
        var tMaxX = stepColumn == 0 ? infinity : (nextVertical - start.x) / dx
        var tMaxY = stepRow == 0 ? infinity : (nextHorizontal - start.y) / dy
        let tDeltaX = stepColumn == 0 ? infinity : abs(cellWidth / dx)
        let tDeltaY = stepRow == 0 ? infinity : abs(cellHeight / dy)
        let epsilon: CGFloat = 0.000_001
        let safetyLimit = rows * columns * 2

        while current != target && result.count <= safetyLimit {
            if abs(tMaxX - tMaxY) <= epsilon {
                current = GridPosition(row: current.row + stepRow, column: current.column + stepColumn)
                tMaxX += tDeltaX
                tMaxY += tDeltaY
            } else if tMaxX < tMaxY {
                current = GridPosition(row: current.row, column: current.column + stepColumn)
                tMaxX += tDeltaX
            } else {
                current = GridPosition(row: current.row + stepRow, column: current.column)
                tMaxY += tDeltaY
            }
            guard (0..<rows).contains(current.row), (0..<columns).contains(current.column) else { break }
            if result.last != current { result.append(current) }
        }
        return result
    }
}
