import Foundation
import AppKit
import Combine

// MARK: - ServerError

enum ServerError: LocalizedError {
    case scriptNotFound
    case alreadyRunning
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:      return "start_server.sh not found in app bundle"
        case .alreadyRunning:      return "Server is already running"
        case .launchFailed(let m): return "Server launch failed: \(m)"
        }
    }
}

// MARK: - ServerManager

@MainActor
final class ServerManager: ObservableObject {

    enum ServerState: Equatable {
        case stopped
        case starting(progress: String)
        case running(port: Int)
        case error(String)
    }

    // MARK: Published state

    @Published var state: ServerState = .stopped
    @Published var startupLog: [String] = []

    // MARK: Singleton

    static let shared = ServerManager()

    // MARK: Private

    private var process: Process?
    private var outputPipe: Pipe?
    private var targetPort: Int = 8000

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    // MARK: - Start

    func start(port: Int = 8000, apiKey: String) async throws {
        switch state {
        case .starting, .running:
            throw ServerError.alreadyRunning
        default:
            break
        }

        guard let scriptURL = resolveServerScript() else {
            state = .error(ServerError.scriptNotFound.errorDescription!)
            throw ServerError.scriptNotFound
        }

        targetPort  = port
        state       = .starting(progress: "Launching oMLX…")
        startupLog  = []

        let basePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omlx").path

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        let modelDir = UserDefaults.standard.string(forKey: "modelDirectory")
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".omlx/models")

        proc.environment = ProcessInfo.processInfo.environment.merging([
            "OMLX_PORT":      "\(port)",
            "OMLX_BASE_PATH": basePath,
            "OMLX_API_KEY":   apiKey,
            "OMLX_MODEL_DIR": modelDir,
        ]) { _, new in new }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        outputPipe = pipe
        process    = proc

        // Read stdout/stderr from background queue, hop to main actor for state updates
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }

            Task { @MainActor [weak self] in
                print("[ServerManager] \(text)")
                guard let self else { return }
                self.startupLog.append(contentsOf: lines)
                // Cap log to avoid unbounded growth
                if self.startupLog.count > 500 {
                    self.startupLog = Array(self.startupLog.suffix(500))
                }
                // Detect startup completion — uvicorn prints this when actually ready
                for line in lines {
                    if line.contains("Application startup complete") {
                        if case .starting = self.state {
                            self.state = .running(port: self.targetPort)
                            APIClient.shared.updateBaseURL(host: "localhost", port: self.targetPort)
                            NotificationCenter.default.post(name: .embeddedServerDidStart, object: nil)
                        }
                    }
                }
            }
        }

        // Handle unexpected exit
        proc.terminationHandler = { [weak proc] _ in
            let status = proc?.terminationStatus ?? -1
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only update if we didn't initiate the stop
                switch self.state {
                case .running:
                    self.state = .error("Server exited unexpectedly (code \(status))")
                case .starting:
                    self.state = .error("Server failed to start (exit \(status))")
                default:
                    break
                }
                self.process    = nil
                self.outputPipe = nil
            }
        }

        do {
            try proc.run()
        } catch {
            state  = .error(error.localizedDescription)
            process    = nil
            outputPipe = nil
            throw ServerError.launchFailed(error.localizedDescription)
        }
    }

    // MARK: - Stop

    func stop() {
        defer {
            state      = .stopped
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
            process    = nil
        }

        guard let proc = process, proc.isRunning else { return }

        let pid = proc.processIdentifier
        proc.terminate()   // SIGTERM — gives oMLX a chance to flush logs / close sockets

        // Safety net: SIGKILL after 5 s if the process hasn't exited
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            // kill(pid, 0) returns 0 if the process still exists
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    // MARK: - Script resolution

    /// Finds start_server.sh in the app bundle (production)
    /// or in the project source tree (development/Xcode run).
    private func resolveServerScript() -> URL? {
        // 1. Production: script is inside the app bundle Resources/
        if let url = Bundle.main.url(forResource: "start_server", withExtension: "sh") {
            return url
        }

        // 2. Development: fall back to known project path
        let devURL = URL(fileURLWithPath:
            "/Users/txema/Projects/IA/TxemAI-MLX/backend-wrapper/start_server.sh")
        return FileManager.default.fileExists(atPath: devURL.path) ? devURL : nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let embeddedServerDidStart = Notification.Name("embeddedServerDidStart")
}
