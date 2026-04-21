import SwiftUI

@main
struct CortexMLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverState = ServerStateViewModel.shared

    var body: some Scene {
        WindowGroup("CortexML") {
            ContentView()
                .environmentObject(serverState)
                .onAppear {
                    appDelegate.setServerState(serverState)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 620)

        WindowGroup("Chat", id: "chat") {
            ChatView()
                .environmentObject(serverState)
        }
        .defaultSize(width: 700, height: 500)
    }
}
