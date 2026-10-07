import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.16, green: 0.09, blue: 0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()
                    Text("OrbPuzzle")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                    Text("Core Orb Engine")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        GameView()
                    } label: {
                        Label("Start Game", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Spacer()
                }
                .padding(.horizontal, 44)
                .foregroundStyle(.white)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.purple)
    }
}

#Preview { ContentView() }
