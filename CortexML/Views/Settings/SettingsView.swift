import SwiftUI

/// Pantalla de configuración inicial.
/// Se muestra cuando no hay API key guardada.
struct SettingsView: View {
    @AppStorage("omlx_api_key") private var storedApiKey: String = ""
    @State private var inputKey: String = ""
    @State private var showKey: Bool = false
    @State private var isConnecting: Bool = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    var onSave: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("oMLX connection")
                .font(.system(size: 16, weight: .medium))

            Text("Enter the API key configured in oMLX Global Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Group {
                    if showKey {
                        TextField("API Key", text: $inputKey)
                    } else {
                        SecureField("API Key", text: $inputKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                }
                .buttonStyle(.plain)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.systemRed))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(isConnecting ? "Connecting..." : "Save & Connect") {
                    saveAndConnect()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inputKey.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            inputKey = storedApiKey
        }
    }

    private func saveAndConnect() {
        let key = inputKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isConnecting = true
        errorMessage = nil

        Task {
            do {
                APIClient.shared.apiKey = key
                try await APIClient.shared.login(apiKey: key)
                storedApiKey = key
                await MainActor.run {
                    isConnecting = false
                    onSave?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = "Could not connect. Check the API key and that oMLX is running."
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
