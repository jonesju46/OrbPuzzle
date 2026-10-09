import AVFoundation
import Foundation

enum ComboSoundSequence {
    static let notes = ["C4", "D4", "E4", "F4", "G4", "A4", "B4"]
    static let stepCount = 7
    static let fileExtension = "wav"

    static func soundIndex(for comboNumber: Int) -> Int? {
        guard comboNumber > 0 else { return nil }
        return ((comboNumber - 1) % stepCount) + 1
    }

    static func note(for comboNumber: Int) -> String? {
        guard let index = soundIndex(for: comboNumber) else { return nil }
        return notes[index - 1]
    }

    static func resourceName(for comboNumber: Int) -> String? {
        guard let note = note(for: comboNumber) else { return nil }
        return "combo_\(note)"
    }
}

/// Preloads one PCM resource per note into retained player pools. Resolution
/// never reads disk or creates players at the moment a combo starts removing.
final class GameAudioManager: NSObject, AVAudioPlayerDelegate {
    typealias ResourceLookup = (_ name: String, _ extension: String) -> URL?
    static let shared = GameAudioManager()
    private let resourceLookup: ResourceLookup
    private var playerPools: [String: [AVAudioPlayer]] = [:]
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
            let name = "combo_\(note)"
            guard let url = resourceLookup(name, ComboSoundSequence.fileExtension) else {
#if DEBUG
                print("[AUDIO][ERROR] missing=\(name).wav")
#endif
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                var pool: [AVAudioPlayer] = []
                for _ in 0..<6 {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.volume = 0.65
                    player.prepareToPlay()
                    pool.append(player)
                }
                playerPools[name] = pool
            } catch {
#if DEBUG
                print("[AUDIO][ERROR] file=\(name).wav preload=\(error)")
#endif
            }
        }
    }

    @discardableResult
    func playComboSound(comboNumber: Int) -> Bool {
        guard let index = ComboSoundSequence.soundIndex(for: comboNumber),
              let note = ComboSoundSequence.note(for: comboNumber),
              let name = ComboSoundSequence.resourceName(for: comboNumber) else { return false }
        preload()
        configureAudioSessionIfNeeded()
        guard let player = playerPools[name]?.first(where: { !$0.isPlaying }) else {
#if DEBUG
            print("[AUDIO][ERROR] file=\(name).wav missingOrPoolBusy=true")
            print("[AUDIO] combo=\(comboNumber) index=\(index) note=\(note) file=\(name).wav play=false")
#endif
            return false
        }
        player.currentTime = 0
        let played = player.play()
#if DEBUG
        print("[AUDIO] combo=\(comboNumber) index=\(index) note=\(note) file=\(name).wav play=\(played)")
#endif
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

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        didConfigureAudioSession = false
        // Reactivate only on the next requested game sound, never in background.
    }

    @objc private func audioServicesReset(_ notification: Notification) {
        didConfigureAudioSession = false
        didPreload = false
        playerPools.removeAll()
    }
}
