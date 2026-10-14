import AVFoundation
import Foundation

enum RecordedPianoAssets {
    /// Retained verified recordings. V5.3 no longer loads them for Combo playback.
    static let notes = [
        "C3", "D3", "E3", "F3", "G3", "A3", "B3",
        "C4", "D4", "E4", "F4", "G4", "A4", "B4",
        "C5", "D5", "E5", "F5", "G5", "A5", "B5"
    ]
}

enum ComboSoundPolicy {
    static let resourceName = "combo_soap_bubble"
    static let fileExtension = "wav"

    static func resourceName(for comboNumber: Int) -> String? {
        guard comboNumber > 0 else { return nil }
        return resourceName
    }
}

enum ComboVoicePoolPolicy {
    static let voiceLimit = 4

    static func firstIdleVoiceIndex(
        voiceCount: Int,
        isPlaying: (Int) -> Bool
    ) -> Int? {
        (0..<max(0, min(voiceCount, voiceLimit))).first { !isPlaying($0) }
    }
}

/// DEBUG-only, one-second aggregate reporting. Recording a sample performs no
/// console I/O; this avoids turning per-frame or per-swap diagnostics into the
/// frame hitch being measured.
final class GamePerformanceProfiler {
    static let shared = GamePerformanceProfiler()
    static var timestamp: TimeInterval {
#if DEBUG
        ProcessInfo.processInfo.systemUptime
#else
        0
#endif
    }

#if DEBUG
    private struct Totals {
        var sums: [Double] = []
        var counts: [Int] = []
        mutating func add(_ newValues: [Double], includeZeros: Bool = true) {
            if sums.count < newValues.count {
                sums.append(contentsOf: repeatElement(0, count: newValues.count - sums.count))
                counts.append(contentsOf: repeatElement(0, count: newValues.count - counts.count))
            }
            for index in newValues.indices where includeZeros || newValues[index] != 0 {
                sums[index] += newValues[index]
                counts[index] += 1
            }
        }
        mutating func takeAverages() -> [Double] {
            defer {
                sums.removeAll(keepingCapacity: true)
                counts.removeAll(keepingCapacity: true)
            }
            return sums.indices.map { sums[$0] / Double(max(counts[$0], 1)) }
        }
    }

    private var drag = Totals(), dragCount = 0
    private var remove = Totals(), removeCount = 0
    private var audioTriggerMsTotal = 0.0
    private var audioRequestCount = 0, audioPlayedCount = 0, audioDroppedRequestCount = 0
    private var audioPeakActiveVoices = 0, audioVoiceStealCount = 0
    private var gravity = Totals(), gravityCount = 0
    private var friendly = Totals(), friendlyCount = 0
    private var refill = Totals(), refillCount = 0
    private var frameIntervalTotal = 0.0, frameCount = 0, frameHitchCount = 0
    private var mainThreadWorkTotal = 0.0
    private var lastFlush = ProcessInfo.processInfo.systemUptime
#endif

    private init() {}

    func recordDrag(touchMs: Double, pathMs: Double, swapMs: Double,
                    spriteMs: Double, audioMs: Double) {
#if DEBUG
        drag.add([touchMs, pathMs, swapMs, spriteMs, audioMs]); dragCount += 1
        mainThreadWorkTotal += touchMs
#endif
    }

    func recordRemove(matchMs: Double = 0, actionScheduleMs: Double = 0,
                      animationElapsedMs: Double = 0, nodeCleanupMs: Double = 0) {
#if DEBUG
        remove.add([matchMs, actionScheduleMs, animationElapsedMs, nodeCleanupMs], includeZeros: false)
        removeCount += 1
        mainThreadWorkTotal += matchMs + actionScheduleMs + nodeCleanupMs
#endif
    }

    func recordComboAudio(triggerMs: Double, played: Bool, activeVoices: Int,
                          voiceStealCount: Int = 0) {
#if DEBUG
        audioTriggerMsTotal += triggerMs
        audioRequestCount += 1
        if played { audioPlayedCount += 1 } else { audioDroppedRequestCount += 1 }
        audioPeakActiveVoices = max(audioPeakActiveVoices, activeVoices)
        audioVoiceStealCount += voiceStealCount
#endif
    }

    func recordGravity(modelMs: Double, actionScheduleMs: Double,
                       animationElapsedMs: Double) {
#if DEBUG
        gravity.add([modelMs, actionScheduleMs, animationElapsedMs]); gravityCount += 1
        mainThreadWorkTotal += modelMs + actionScheduleMs
#endif
    }

    func recordFriendly(analyzerMs: Double, candidateMs: Double, searchMs: Double,
                        validationMs: Double, totalMs: Double) {
#if DEBUG
        friendly.add([analyzerMs, candidateMs, searchMs, validationMs, totalMs]); friendlyCount += 1
#endif
    }

    func recordRefill(modelMs: Double, nodeCreateMs: Double, actionScheduleMs: Double,
                      animationElapsedMs: Double) {
#if DEBUG
        refill.add([modelMs, nodeCreateMs, actionScheduleMs, animationElapsedMs]); refillCount += 1
        mainThreadWorkTotal += modelMs + nodeCreateMs + actionScheduleMs
#endif
    }

    func recordFrame(intervalMs: Double, mainThreadWorkMs: Double) {
#if DEBUG
        frameIntervalTotal += intervalMs
        mainThreadWorkTotal += mainThreadWorkMs
        frameCount += 1
        if intervalMs > 25 { frameHitchCount += 1 }
        flushIfNeeded()
#endif
    }

#if DEBUG
    private func formatted(_ value: Double) -> String { String(format: "%.2f", value) }

    private func flushIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFlush >= 1 else { return }
        lastFlush = now
        if dragCount > 0 {
            let v = drag.takeAverages()
            print("[DRAG_PERF] touchMs=\(formatted(v[0])) pathMs=\(formatted(v[1])) swapMs=\(formatted(v[2])) spriteMs=\(formatted(v[3])) audioMs=\(formatted(v[4])) samples=\(dragCount)")
            dragCount = 0
        }
        if removeCount > 0 {
            let v = remove.takeAverages()
            print("[REMOVE_PERF] matchMs=\(formatted(v[0])) actionScheduleMs=\(formatted(v[1])) animationElapsedMs=\(formatted(v[2])) nodeCleanupMs=\(formatted(v[3])) samples=\(removeCount)")
            removeCount = 0
        }
        if audioRequestCount > 0 {
            let averageTriggerMs = audioTriggerMsTotal / Double(audioRequestCount)
            print("[AUDIO_PERF] comboRequests=\(audioRequestCount) comboPlayed=\(audioPlayedCount) comboDropped=\(audioDroppedRequestCount) activeVoices=\(audioPeakActiveVoices) voiceStealCount=\(audioVoiceStealCount) triggerMs=\(formatted(averageTriggerMs))")
            audioTriggerMsTotal = 0
            audioRequestCount = 0; audioPlayedCount = 0; audioDroppedRequestCount = 0
            audioPeakActiveVoices = 0; audioVoiceStealCount = 0
        }
        if gravityCount > 0 {
            let v = gravity.takeAverages()
            print("[GRAVITY_PERF] modelMs=\(formatted(v[0])) actionScheduleMs=\(formatted(v[1])) animationElapsedMs=\(formatted(v[2])) samples=\(gravityCount)")
            gravityCount = 0
        }
        if friendlyCount > 0 {
            let v = friendly.takeAverages()
            print("[FRIENDLY_PERF] analyzerMs=\(formatted(v[0])) candidateMs=\(formatted(v[1])) searchMs=\(formatted(v[2])) validationMs=\(formatted(v[3])) totalMs=\(formatted(v[4])) samples=\(friendlyCount)")
            friendlyCount = 0
        }
        if refillCount > 0 {
            let v = refill.takeAverages()
            print("[REFILL_PERF] modelMs=\(formatted(v[0])) nodeCreateMs=\(formatted(v[1])) actionScheduleMs=\(formatted(v[2])) animationElapsedMs=\(formatted(v[3])) samples=\(refillCount)")
            refillCount = 0
        }
        if frameCount > 0 {
            print("[FRAME_PERF] frameIntervalMs=\(formatted(frameIntervalTotal / Double(frameCount))) frameHitchCount=\(frameHitchCount) mainThreadWorkMs=\(formatted(mainThreadWorkTotal / Double(frameCount))) samples=\(frameCount)")
            frameIntervalTotal = 0; mainThreadWorkTotal = 0
            frameCount = 0; frameHitchCount = 0
        }
    }
#endif
}

struct GlassSwapSoundGate: Equatable, Sendable {
    static let cooldown: TimeInterval = 0.045
    private(set) var lastPlaybackTime: TimeInterval?

    func allowsPlayback(at time: TimeInterval) -> Bool {
        guard let lastPlaybackTime else { return true }
        return time - lastPlaybackTime >= Self.cooldown
    }

    mutating func recordPlayback(at time: TimeInterval) {
        lastPlaybackTime = time
    }

    mutating func reset() { lastPlaybackTime = nil }
}

enum GlassSwapSoundPolicy {
    static func shouldRequestPlayback(didSwap: Bool, isDragActive: Bool) -> Bool {
        didSwap && isDragActive
    }
}

/// Preloads the fixed Combo Foley and glass-swap PCM resources into retained
/// player pools. Resolution
/// never reads disk or creates players at the moment a combo starts removing.
final class GameAudioManager: NSObject, AVAudioPlayerDelegate {
    typealias ResourceLookup = (_ name: String, _ extension: String) -> URL?
    static let shared = GameAudioManager()
    static let comboVoiceCount = ComboVoicePoolPolicy.voiceLimit
    static let glassVoiceCount = 4
    private let resourceLookup: ResourceLookup
    private var playerPools: [String: [AVAudioPlayer]] = [:]
    private var glassSwapGate = GlassSwapSoundGate()
    private var didPreload = false
    private var didConfigureAudioSession = false

    init(resourceLookup: @escaping ResourceLookup = { name, fileExtension in
        Bundle.main.url(forResource: name, withExtension: fileExtension)
    }) {
        self.resourceLookup = resourceLookup
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioSessionInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func preload() {
        guard !didPreload else { return }
        didPreload = true
        configureAudioSessionIfNeeded()
        preloadResource(name: ComboSoundPolicy.resourceName,
                        voiceCount: Self.comboVoiceCount, volume: 0.40)
        preloadResource(name: "orb_glass_swap", voiceCount: Self.glassVoiceCount, volume: 0.22)
    }

    @discardableResult
    func playComboSound(comboNumber: Int) -> Bool {
#if DEBUG
        let scheduleStarted = GamePerformanceProfiler.timestamp
#endif
        guard let name = ComboSoundPolicy.resourceName(for: comboNumber) else { return false }
        preload()
        configureAudioSessionIfNeeded()
        guard let players = playerPools[name],
              let index = ComboVoicePoolPolicy.firstIdleVoiceIndex(
                voiceCount: players.count,
                isPlaying: { players[$0].isPlaying }
              ) else {
#if DEBUG
            let active = playerPools[name]?.filter(\.isPlaying).count ?? 0
            GamePerformanceProfiler.shared.recordComboAudio(
                triggerMs: (GamePerformanceProfiler.timestamp - scheduleStarted) * 1_000,
                played: false, activeVoices: active)
#endif
            return false
        }
        let player = players[index]
        player.currentTime = 0
        let played = player.play()
#if DEBUG
        let active = playerPools[name]?.filter(\.isPlaying).count ?? 0
        GamePerformanceProfiler.shared.recordComboAudio(
            triggerMs: (GamePerformanceProfiler.timestamp - scheduleStarted) * 1_000,
            played: played, activeVoices: active)
#endif
        return played
    }

    /// Called only after the grid model confirms a real swap. Audio throttling
    /// is isolated here and can never suppress or delay drag traversal.
    @discardableResult
    func playGlassSwapSound(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard glassSwapGate.allowsPlayback(at: time) else { return false }
        preload()
        configureAudioSessionIfNeeded()
        guard let player = playerPools["orb_glass_swap"]?.first(where: { !$0.isPlaying }) else {
            return false
        }
        player.currentTime = 0
        let played = player.play()
        if played { glassSwapGate.recordPlayback(at: time) }
        return played
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        player.currentTime = 0
        player.prepareToPlay()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
#if DEBUG
        print("[AUDIO][ERROR] decode=\(error?.localizedDescription ?? "unknown")")
#endif
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Short game SFX remain audible with the silent switch while mixing
            // with other apps. No background-audio capability is enabled.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            didConfigureAudioSession = true
        } catch {
#if DEBUG
            print("[AUDIO][ERROR] session=\(error)")
#endif
        }
    }

    private func preloadResource(name: String, voiceCount: Int, volume: Float) {
        guard let url = resourceLookup(name, ComboSoundPolicy.fileExtension) else {
#if DEBUG
            print("[AUDIO][ERROR] missing=\(name).wav")
#endif
            return
        }
        do {
            let data = try Data(contentsOf: url)
            playerPools[name] = try (0..<voiceCount).map { _ in
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.volume = volume
                player.prepareToPlay()
                return player
            }
        } catch {
#if DEBUG
            print("[AUDIO][ERROR] file=\(name).wav preload=\(error)")
#endif
        }
    }

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        didConfigureAudioSession = false
        // Reactivate only on the next requested game sound, never in background.
    }

    @objc private func audioServicesReset(_ notification: Notification) {
        didConfigureAudioSession = false
        didPreload = false
        playerPools.removeAll()
        glassSwapGate.reset()
    }
}
