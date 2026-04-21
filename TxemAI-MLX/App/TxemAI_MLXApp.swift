import SwiftUI

@main
struct CortexMLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverState = ServerStateViewModel.shared

    var body: some Scene {
        WindowGroup("CortexML") {
            ThemeProvider {
                ContentView()
                    .environmentObject(serverState)
                    .onAppear {
                        appDelegate.setServerState(serverState)
                    }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 660, height: 720)

        WindowGroup("Chat", id: "chat") {
            ThemeProvider {
                ChatView()
                    .environmentObject(serverState)
            }
        }
        .defaultSize(width: 520, height: 720)
    }
}
