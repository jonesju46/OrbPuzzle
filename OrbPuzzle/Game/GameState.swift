import Foundation

enum GameState: String, Equatable {
    case idle
    case selected
    case turnActive
    case dragging
    case resolving
    case removing
    case falling
    case refilling
    case skyfall
    case completed
}

/// Monotonically identifies the currently active game. Delayed work captures an
/// ID and must be ignored after a new session begins.
struct GameSessionFence: Equatable, Sendable {
    private(set) var id: UInt = 0

    @discardableResult
    mutating func beginNewSession() -> UInt {
        id &+= 1
        return id
    }

    func accepts(_ candidate: UInt) -> Bool {
        candidate == id
    }
}

struct GameSessionSnapshot: Equatable {
    let sessionID: UInt
    let orbIDs: Set<UUID>
    let state: GameState
    let comboCount: Int
    let generatedSkyfall: Int
    let requestedSkyfall: Int
    let remainingTime: TimeInterval
    let progress: Double
    let resolveID: UInt
    let resolveLifecycleState: SkyfallFinalizationState
    let completedTurnCount: Int
    let averageTurnTime: TimeInterval
    let averageTotalCombo: Double
}

struct SessionStatistics: Equatable, Sendable {
    private(set) var completedTurnCount = 0
    private(set) var turnTimeSum: TimeInterval = 0
    private(set) var totalComboSum = 0
    private(set) var comboTotalSumByType = SessionStatistics.zeroedCounts()
    private var lastCommittedResolveID: UInt?

    var averageTurnTime: TimeInterval {
        guard completedTurnCount > 0 else { return 0 }
        return turnTimeSum / Double(completedTurnCount)
    }

    var averageTotalCombo: Double {
        guard completedTurnCount > 0 else { return 0 }
        return Double(totalComboSum) / Double(completedTurnCount)
    }

    func averageCombo(for type: OrbType) -> Double {
        guard completedTurnCount > 0 else { return 0 }
        return Double(comboTotalSumByType[type, default: 0]) / Double(completedTurnCount)
    }

    mutating func reset() {
        completedTurnCount = 0
        turnTimeSum = 0
        totalComboSum = 0
        comboTotalSumByType = SessionStatistics.zeroedCounts()
        lastCommittedResolveID = nil
    }

    @discardableResult
    mutating func commitCompletedTurn(
        resolveID: UInt,
        moveTime: TimeInterval,
        totalCombo: Int,
        comboTotalByType: [OrbType: Int]
    ) -> Bool {
        guard lastCommittedResolveID != resolveID else { return false }
        lastCommittedResolveID = resolveID
        completedTurnCount += 1
        turnTimeSum += max(0, moveTime)
        totalComboSum += max(0, totalCombo)
        for type in OrbType.allCases {
            comboTotalSumByType[type, default: 0] += max(0, comboTotalByType[type, default: 0])
        }
        return true
    }

    private static func zeroedCounts() -> [OrbType: Int] {
        Dictionary(uniqueKeysWithValues: OrbType.allCases.map { ($0, 0) })
    }
}

enum GameplayStatusHUDText {
    static func time(current: TimeInterval, average: TimeInterval) -> String {
        String(format: "Time %.1f [%.1f]", current, average)
    }

    static func combo(currentBreakdown: String, average: Double) -> String {
        String(format: "%@ [%.1f]", currentBreakdown, average)
    }

    static func orbType(currentBreakdown: String, average: Double) -> String {
        String(format: "%@ [%.1f]", currentBreakdown, average)
    }
}

enum SkyfallFinalizationState: Equatable, Sendable {
    case idle
    case running
    case finalizing
    case finished
}

/// Exactly-once gate shared by the runtime and boundary tests. It prevents an
/// old skyfall completion from starting another cycle or a second final refill.
struct ResolveLifecycle: Equatable, Sendable {
    private(set) var state: SkyfallFinalizationState = .idle
    private(set) var finalRefillCount = 0
    private(set) var finishCount = 0

    var acceptsSkyfallCompletion: Bool { state == .running }

    mutating func start() {
        state = .running
        finalRefillCount = 0
        finishCount = 0
    }

    mutating func beginFinalization() -> Bool {
        guard state == .running else { return false }
        state = .finalizing
        finalRefillCount += 1
        return true
    }

    mutating func finish() -> Bool {
        guard state == .running || state == .finalizing else { return false }
        state = .finished
        finishCount += 1
        return true
    }
}
