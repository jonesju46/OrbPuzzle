enum GameState: String {
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
