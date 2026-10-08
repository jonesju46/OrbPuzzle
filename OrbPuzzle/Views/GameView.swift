import SpriteKit
import SwiftUI

struct GameView: View {
    @AppStorage(GameSettings.turnDurationKey) private var turnDuration = GameSettings.defaultTurnDuration
    @AppStorage(GameSettings.noResolveDuringTurnKey) private var noResolveDuringTurn = GameSettings.defaultNoResolveDuringTurn
    @AppStorage(GameSettings.skyfallComboCountKey) private var skyfallComboCount = GameSettings.defaultSkyfallComboCount
    @State private var scene = GameScene(size: CGSize(width: 390, height: 844))
    @State private var isShowingSettings = false
    @State private var isGameplayVisible = false

    var body: some View {
        GeometryReader { geometry in
            SpriteView(
                scene: scene,
                preferredFramesPerSecond: 60,
                options: [.ignoresSiblingOrder]
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .onAppear {
                resizeScene(to: geometry.size)
                applySettings()
                guard !isGameplayVisible else { return }
                isGameplayVisible = true
                scene.startNewGame()
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeScene(to: newSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("OrbPuzzle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    scene.startNewGame()
                } label: {
                    Text("New Game")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Game")

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
        .onChange(of: noResolveDuringTurn) { _, _ in applySettings() }
        .onChange(of: skyfallComboCount) { _, _ in applySettings() }
        .onDisappear {
            // A sheet does not remove GameView. A real navigation departure does,
            // so the next Start Game appearance must create another session.
            if !isShowingSettings { isGameplayVisible = false }
        }
    }

    private func resizeScene(to size: CGSize) {
        guard size.width > 0, size.height > 0, scene.size != size else { return }
        scene.size = size
    }

    private func applySettings() {
        scene.configure(
            turnDuration: turnDuration,
            noResolveDuringTurn: noResolveDuringTurn,
            skyfallComboCount: skyfallComboCount
        )
    }
}
