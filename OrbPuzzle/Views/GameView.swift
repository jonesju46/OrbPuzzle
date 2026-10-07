import SpriteKit
import SwiftUI

struct GameView: View {
    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.cascadeRoundsKey) private var cascadeRounds = GameSettings.defaultCascadeRounds
    @AppStorage(GameSettings.dropModeKey) private var dropModeRaw = GameSettings.defaultDropMode
    @State private var scene = GameScene(size: CGSize(width: 390, height: 844))

    var body: some View {
        SpriteView(
            scene: scene,
            preferredFramesPerSecond: 60,
            options: [.ignoresSiblingOrder]
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("OrbPuzzle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .onAppear(perform: applySettings)
        .onChange(of: turnDuration) { _, _ in applySettings() }
        .onChange(of: cascadeRounds) { _, _ in applySettings() }
        .onChange(of: dropModeRaw) { _, _ in applySettings() }
    }

    private func applySettings() {
        scene.configure(
            turnDuration: turnDuration,
            cascadeRounds: cascadeRounds,
            dropMode: DropMode(rawValue: dropModeRaw) ?? .normal
        )
    }
}
