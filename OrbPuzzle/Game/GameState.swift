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
