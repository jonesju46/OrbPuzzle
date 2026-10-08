import AVFoundation
import Foundation

enum ComboSoundSequence {
    static let stepCount = 7
    static let fileExtension = "wav"

    static func soundIndex(for comboNumber: Int) -> Int? {
        guard comboNumber > 0 else { return nil }
        return ((comboNumber - 1) % stepCount) + 1
    }

    static func resourceName(for comboNumber: Int) -> String? {
        guard let index = soundIndex(for: comboNumber) else { return nil }
        return "combo_\(index)"
    }
}

/// Owns short gameplay SFX playback. Each trigger creates a retained player so
/// consecutive combo sounds can overlap without blocking SpriteKit resolution.
final class GameAudioManager: NSObject, AVAudioPlayerDelegate {
    typealias ResourceLookup = (_ name: String, _ extension: String) -> URL?

    static let shared = GameAudioManager()

    private let resourceLookup: ResourceLookup
    private var activePlayers: [ObjectIdentifier: AVAudioPlayer] = [:]
    private var didConfigureAudioSession = false
#if DEBUG
    private var reportedMissingResources: Set<String> = []
#endif

    init(resourceLookup: @escaping ResourceLookup = { name, fileExtension in
        Bundle.main.url(forResource: name, withExtension: fileExtension)
    }) {
        self.resourceLookup = resourceLookup
        super.init()
    }

    @discardableResult
    func playComboSound(comboNumber: Int) -> Bool {
        guard let resourceName = ComboSoundSequence.resourceName(for: comboNumber) else {
            return false
        }
        guard let url = resourceLookup(resourceName, ComboSoundSequence.fileExtension) else {
            reportMissing(resourceName)
            return false
        }

        configureAudioSessionIfNeeded()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            let identifier = ObjectIdentifier(player)
            activePlayers[identifier] = player
            guard player.play() else {
                activePlayers.removeValue(forKey: identifier)
#if DEBUG
                print("[AUDIO] unable to play combo sound: \(resourceName)")
#endif
                return false
            }
            return true
        } catch {
#if DEBUG
            print("[AUDIO] failed combo sound: \(resourceName) error=\(error)")
#endif
            return false
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        activePlayers.removeValue(forKey: ObjectIdentifier(player))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        activePlayers.removeValue(forKey: ObjectIdentifier(player))
#if DEBUG
        if let error {
            print("[AUDIO] decode error: \(error)")
        }
#endif
    }

    private func configureAudioSessionIfNeeded() {
        guard !didConfigureAudioSession else { return }
        didConfigureAudioSession = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
#if DEBUG
            print("[AUDIO] session configuration failed: \(error)")
#endif
        }
    }

    private func reportMissing(_ resourceName: String) {
#if DEBUG
        guard reportedMissingResources.insert(resourceName).inserted else { return }
        print("[AUDIO] missing combo sound: \(resourceName)")
#endif
    }
}
