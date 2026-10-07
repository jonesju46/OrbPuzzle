import SpriteKit
import SwiftUI

struct GameView: View {
    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.cascadeRoundsKey) private var cascadeRounds = GameSettings.defaultCascadeRounds
    @AppStorage(GameSettings.dropModeKey) private var dropModeRaw = GameSettings.defaultDropMode
    @AppStorage(GameSettings.targetComboKey) private var targetCombo = GameSettings.defaultTargetCombo
    @State private var scene = GameScene(size: CGSize(width: 390, height: 844))
    @State private var isShowingSettings = false

    var body: some View {
        GeometryReader { geometry in
            SpriteView(
                scene: scene,
                preferredFramesPerSecond: 60,
                options: [.ignoresSiblingOrder]
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onAppear {
                resizeScene(to: geometry.size)
                applySettings()
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeScene(to: newSize)
            }
        }
        .navigationTitle("OrbPuzzle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
        .background(alignment: .topLeading) {
            GameplayNavigationGuard()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingSettings = false }
                        }
                    }
            }
        }
        .onChange(of: turnDuration) { _, _ in applySettings() }
        .onChange(of: cascadeRounds) { _, _ in applySettings() }
        .onChange(of: dropModeRaw) { _, _ in applySettings() }
        .onChange(of: targetCombo) { _, _ in applySettings() }
    }

    private func resizeScene(to size: CGSize) {
        guard size.width > 0, size.height > 0, scene.size != size else { return }
        scene.size = size
    }

    private func applySettings() {
        scene.configure(
            turnDuration: turnDuration,
            cascadeRounds: cascadeRounds,
            dropMode: DropMode(rawValue: dropModeRaw) ?? .normal,
            targetCombo: targetCombo
        )
    }
}
