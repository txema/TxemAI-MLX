import Foundation

/// Observa el fichero de log del backend (tail -f) y entrega nuevas
/// líneas parseadas como LogEntry en el hilo principal.
///
/// Usa DispatchSource con DISPATCH_VNODE_EXTEND para detectar escrituras
/// sin polling. Si el fichero no existe al arrancar, reintenta cada 2 s.
final class LogFileWatcher {

    private let path: String
    private let handler: (LogEntry) -> Void

    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0

    init(path: String, onEntry: @escaping (LogEntry) -> Void) {
        self.path = (path as NSString).expandingTildeInPath
        self.handler = onEntry
    }

    // MARK: - Control

    func start() {
        guard FileManager.default.fileExists(atPath: path) else {
            // Backend aún no ha creado el fichero — reintentar en 2 s
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.start()
            }
            return
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return }

        fileHandle = handle
        // Empezar desde el final del fichero (no releer entradas antiguas)
        offset = handle.seekToEndOfFile()

        let fd = handle.fileDescriptor
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.extend, .write],
            queue: DispatchQueue.global(qos: .background)
        )

        src.setEventHandler { [weak self] in
            self?.readNewLines()
        }

        src.setCancelHandler { [weak self] in
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }

        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    // MARK: - Lectura

    private func readNewLines() {
        guard let handle = fileHandle else { return }

        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = handle.offsetInFile

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        let entries = text
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { parseLogLine($0) }

        DispatchQueue.main.async { [entries, handler] in
            entries.forEach { handler($0) }
        }
    }

    // MARK: - Parseo

    /// Parsea una línea de log Python en LogEntry.
    /// Formato esperado: "2026-04-10 14:32:01,123 - omlx.server - INFO - [req] - mensaje"
    private func parseLogLine(_ line: String) -> LogEntry {
        // Eliminar códigos ANSI de color
        let clean = line.replacingOccurrences(
            of: #"\x1B\[[0-9;]*m"#, with: "", options: .regularExpression
        )

        let parts = clean.components(separatedBy: " - ")
        var level: LogEntry.Level = .info
        var message = clean

        if parts.count >= 3 {
            switch parts[2].trimmingCharacters(in: .whitespaces).uppercased() {
            case "WARNING", "WARN": level = .warn
            case "ERROR", "CRITICAL": level = .error
            default:                 level = .info
            }
            // Mensaje: todo lo que va tras el nivel (y tras [req_id] si lo hay)
            message = parts.count >= 4
                ? parts[3...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                : parts[2...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            if message.hasPrefix("["), let end = message.firstIndex(of: "]") {
                let after = message.index(after: end)
                message = message[after...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
            }
        }

        return LogEntry(id: UUID(), timestamp: Date(), level: level, message: message)
    }
}
