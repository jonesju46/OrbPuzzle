import AVFoundation
import Foundation

struct ComboSoundPair: Equatable, Sendable {
    let primary: String
    let harmony: String
}

enum ComboSoundSequence {
    /// The recorded resources remain bundled for provenance and future use,
    /// but V5.2 intentionally plays one fixed acoustic harmony for every
    /// resolved group.
    static let assetNotes = [
        "C3", "D3", "E3", "F3", "G3", "A3", "B3",
        "C4", "D4", "E4", "F4", "G4", "A4", "B4",
        "C5", "D5", "E5", "F5", "G5", "A5", "B5"
    ]
    static let fixedPair = ComboSoundPair(primary: "B5", harmony: "D5")
    static let playbackNotes = [fixedPair.primary, fixedPair.harmony]
    static let stepCount = 1
    static let fileExtension = "wav"

    static func soundIndex(for comboNumber: Int) -> Int? {
        guard comboNumber > 0 else { return nil }
        return 1
    }

    static func note(for comboNumber: Int) -> String? {
        guard soundIndex(for: comboNumber) != nil else { return nil }
        return fixedPair.primary
    }

    static func notePair(for comboNumber: Int) -> ComboSoundPair? {
        guard soundIndex(for: comboNumber) != nil else { return nil }
        return fixedPair
    }

    static func resourceNames(for comboNumber: Int) -> [String]? {
        guard let pair = notePair(for: comboNumber) else { return nil }
        return ["combo_\(pair.primary)", "combo_\(pair.harmony)"]
    }

    static func resourceName(for comboNumber: Int) -> String? {
        guard let note = note(for: comboNumber) else { return nil }
        return "combo_\(note)"
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
    private var audio = Totals(), audioCount = 0
    private var audioVoiceStealCount = 0, audioDroppedRequestCount = 0
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

    func recordAudio(scheduleMs: Double, activeVoices: Int, voiceStealCount: Int,
                     droppedRequestCount: Int = 0) {
#if DEBUG
        audio.add([scheduleMs, Double(activeVoices)])
        audioCount += 1
        audioVoiceStealCount += voiceStealCount
        audioDroppedRequestCount += droppedRequestCount
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
        if audioCount > 0 {
            let v = audio.takeAverages()
            print("[AUDIO_PERF] scheduleMs=\(formatted(v[0])) activeVoices=\(formatted(v[1])) voiceStealCount=\(audioVoiceStealCount) droppedRequests=\(audioDroppedRequestCount) samples=\(audioCount)")
            audioCount = 0
            audioVoiceStealCount = 0; audioDroppedRequestCount = 0
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

/// Preloads one PCM resource per note into retained player pools. Resolution
/// never reads disk or creates players at the moment a combo starts removing.
final class GameAudioManager: NSObject, AVAudioPlayerDelegate {
    typealias ResourceLookup = (_ name: String, _ extension: String) -> URL?
    static let shared = GameAudioManager()
    static let comboVoiceCount = 8
    static let glassVoiceCount = 4
    static let synchronizationLeadTime: TimeInterval = 0.012
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
        for note in ComboSoundSequence.playbackNotes {
            preloadResource(name: "combo_\(note)", voiceCount: Self.comboVoiceCount, volume: 0.38)
        }
        preloadResource(name: "orb_glass_swap", voiceCount: Self.glassVoiceCount, volume: 0.22)
    }

    @discardableResult
    func playComboSound(comboNumber: Int) -> Bool {
#if DEBUG
        let scheduleStarted = GamePerformanceProfiler.timestamp
#endif
        guard ComboSoundSequence.soundIndex(for: comboNumber) != nil,
              let names = ComboSoundSequence.resourceNames(for: comboNumber) else { return false }
        preload()
        configureAudioSessionIfNeeded()
        guard let primary = playerPools[names[0]]?.first(where: { !$0.isPlaying }),
              let harmony = playerPools[names[1]]?.first(where: { !$0.isPlaying }) else {
#if DEBUG
            let active = names.reduce(0) { $0 + (playerPools[$1]?.filter(\.isPlaying).count ?? 0) }
            GamePerformanceProfiler.shared.recordAudio(
                scheduleMs: (GamePerformanceProfiler.timestamp - scheduleStarted) * 1_000,
                activeVoices: active, voiceStealCount: 0, droppedRequestCount: 1)
#endif
            return false
        }
        primary.currentTime = 0
        harmony.currentTime = 0
        // AVAudioPlayer device time shares the output clock. Scheduling both
        // voices at one future timestamp avoids an audible arpeggio.
        let startTime = max(primary.deviceCurrentTime, harmony.deviceCurrentTime)
            + Self.synchronizationLeadTime
        let primaryPlayed = primary.play(atTime: startTime)
        let harmonyPlayed = harmony.play(atTime: startTime)
        let played = primaryPlayed && harmonyPlayed
        if !played {
            primary.stop()
            harmony.stop()
        }
#if DEBUG
        let active = names.reduce(0) { $0 + (playerPools[$1]?.filter(\.isPlaying).count ?? 0) }
        GamePerformanceProfiler.shared.recordAudio(
            scheduleMs: (GamePerformanceProfiler.timestamp - scheduleStarted) * 1_000,
            activeVoices: active, voiceStealCount: 0)
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
        guard let url = resourceLookup(name, ComboSoundSequence.fileExtension) else {
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
