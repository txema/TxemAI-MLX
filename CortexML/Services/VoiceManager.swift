import Foundation
import AppKit
import Combine

// MARK: - VoiceServerError

enum VoiceServerError: LocalizedError {
    case scriptNotFound
    case alreadyRunning
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:      return "start_voice_server.sh not found in app bundle"
        case .alreadyRunning:      return "Voice server is already running"
        case .launchFailed(let m): return "Voice server launch failed: \(m)"
        }
    }
}

// MARK: - VoiceManager

@MainActor
final class VoiceManager: ObservableObject {

    enum VoiceServerState: Equatable {
        case stopped
        case starting(progress: String)
        case running(port: Int)
        case error(String)
    }

    @Published var state: VoiceServerState = .stopped
    @Published var startupLog: [String] = []

    static let shared = VoiceManager()

    private var process: Process?
    private var outputPipe: Pipe?
    private let port = 17493

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

    func start() async throws {
        switch state {
        case .starting, .running:
            throw VoiceServerError.alreadyRunning
        default:
            break
        }

        guard let scriptURL = resolveServerScript() else {
            state = .error(VoiceServerError.scriptNotFound.errorDescription!)
            throw VoiceServerError.scriptNotFound
        }

        state      = .starting(progress: "Launching voicebox…")
        startupLog = []

        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cortexML/voice").path

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        proc.environment = ProcessInfo.processInfo.environment.merging([
            "VOICE_PORT":     "\(port)",
            "VOICE_DATA_DIR": dataDir,
        ]) { _, new in new }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe
        outputPipe = pipe
        process    = proc

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startupLog.append(contentsOf: lines)
                if self.startupLog.count > 500 {
                    self.startupLog = Array(self.startupLog.suffix(500))
                }
                for line in lines {
                    if self.detectStartupComplete(line) {
                        if case .starting = self.state {
                            self.state = .running(port: self.port)
                            NotificationCenter.default.post(name: .voiceServerDidStart, object: nil)
                        }
                    }
                }
            }
        }

        proc.terminationHandler = { [weak proc] _ in
            let status = proc?.terminationStatus ?? -1
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.state {
                case .running:
                    self.state = .error("Voice server exited unexpectedly (code \(status))")
                case .starting:
                    self.state = .error("Voice server failed to start (exit \(status))")
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
            state      = .error(error.localizedDescription)
            process    = nil
            outputPipe = nil
            throw VoiceServerError.launchFailed(error.localizedDescription)
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
        proc.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    // MARK: - Private helpers

    private func detectStartupComplete(_ line: String) -> Bool {
        line.contains("Uvicorn running on") || line.contains("Application startup complete")
    }

    private func resolveServerScript() -> URL? {
        if let url = Bundle.main.url(forResource: "start_voice_server", withExtension: "sh") {
            return url
        }
        let devURL = URL(fileURLWithPath:
            "/Users/txema/Projects/IA/TxemAI-MLX/backend-wrapper/start_voice_server.sh")
        return FileManager.default.fileExists(atPath: devURL.path) ? devURL : nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let voiceServerDidStart = Notification.Name("voiceServerDidStart")
}
