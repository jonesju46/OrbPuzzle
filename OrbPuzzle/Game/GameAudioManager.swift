import AVFoundation
import Foundation

struct ComboSoundPair: Equatable, Sendable {
    let primary: String
    let harmony: String
}

enum ComboSoundSequence {
    static let notes = [
        "C3", "D3", "E3", "F3", "G3", "A3", "B3",
        "C4", "D4", "E4", "F4", "G4", "A4", "B4",
        "C5", "D5", "E5", "F5", "G5", "A5", "B5"
    ]
    // Diatonic thirds. The final two harmonies fold C6/D6 down one octave
    // because the original licensed resource set intentionally ends at B5.
    static let harmonies = [
        "E3", "F3", "G3", "A3", "B3", "C4", "D4",
        "E4", "F4", "G4", "A4", "B4", "C5", "D5",
        "E5", "F5", "G5", "A5", "B5", "C5", "D5"
    ]
    static let stepCount = notes.count
    static let fileExtension = "wav"

    static func soundIndex(for comboNumber: Int) -> Int? {
        guard comboNumber > 0 else { return nil }
        return ((comboNumber - 1) % stepCount) + 1
    }

    static func note(for comboNumber: Int) -> String? {
        guard let index = soundIndex(for: comboNumber) else { return nil }
        return notes[index - 1]
    }

    static func notePair(for comboNumber: Int) -> ComboSoundPair? {
        guard let index = soundIndex(for: comboNumber) else { return nil }
        return ComboSoundPair(primary: notes[index - 1], harmony: harmonies[index - 1])
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
    static let comboVoiceCount = 6
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
        for note in ComboSoundSequence.notes {
            preloadResource(name: "combo_\(note)", voiceCount: Self.comboVoiceCount, volume: 0.38)
        }
        preloadResource(name: "orb_glass_swap", voiceCount: Self.glassVoiceCount, volume: 0.22)
    }

    @discardableResult
    func playComboSound(comboNumber: Int) -> Bool {
        guard let index = ComboSoundSequence.soundIndex(for: comboNumber),
              let pair = ComboSoundSequence.notePair(for: comboNumber),
              let names = ComboSoundSequence.resourceNames(for: comboNumber) else { return false }
        preload()
        configureAudioSessionIfNeeded()
        guard let primary = playerPools[names[0]]?.first(where: { !$0.isPlaying }),
              let harmony = playerPools[names[1]]?.first(where: { !$0.isPlaying }) else {
#if DEBUG
            print("[AUDIO][ERROR] pair=\(names) missingOrPoolBusy=true")
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
        print("[AUDIO] combo=\(comboNumber) soundIndex=\(index) primary=\(pair.primary) harmony=\(pair.harmony) synchronized=true play=\(played)")
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
