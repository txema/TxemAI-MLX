//
//  PersonasView.swift
//  TxemAI-MLX
//
//  Created by Txema on 11/04/2026.
//

import SwiftUI

// MARK: - Main Sheet

struct PersonasView: View {
    @EnvironmentObject var serverState: ServerStateViewModel
    @ObservedObject private var store = ChatStore.shared
    @State private var selectedID: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            personaList
            Divider()
            editArea
        }
        .frame(width: 680, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left Panel

    private var personaList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PERSONAS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: addPersona) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("New Persona")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if store.personas.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No personas yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.personas) { persona in
                            PersonaRowView(
                                persona: persona,
                                isSelected: selectedID == persona.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = persona.id }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deletePersona(persona)
                                }
                            }
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }

            Divider()

            // Footer
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .frame(width: 210)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var editArea: some View {
        if let id = selectedID,
           let persona = store.personas.first(where: { $0.id == id }) {
            PersonaEditForm(
                persona: persona,
                availableModels: serverState.models,
                onSave: { updated in store.save(persona: updated) },
                onDelete: { deletePersona(persona) }
            )
            .id(persona.id)   // forces reinit when selection changes
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select a persona to edit\nor press + to create one")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func addPersona() {
        let newPersona = Persona(
            name: "New Persona",
            systemPrompt: "You are a helpful assistant."
        )
        store.save(persona: newPersona)
        selectedID = newPersona.id
    }

    private func deletePersona(_ persona: Persona) {
        if selectedID == persona.id { selectedID = nil }
        store.delete(persona: persona)
    }
}

// MARK: - Persona Row

private struct PersonaRowView: View {
    let persona: Persona
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(persona.name.isEmpty ? "Unnamed" : persona.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(persona.systemPrompt.isEmpty ? "No system prompt" : persona.systemPrompt)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}

// MARK: - Edit Form

private struct PersonaEditForm: View {
    let persona: Persona
    let availableModels: [LLMModel]
    let onSave: (Persona) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var systemPrompt: String
    @State private var preferredModel: String

    @State private var useTemperature: Bool
    @State private var temperature: Double

    @State private var useTopP: Bool
    @State private var topP: Double

    @State private var useTopK: Bool
    @State private var topK: Double   // stored as Double for Slider

    @State private var useMaxTokens: Bool
    @State private var maxTokensText: String

    init(
        persona: Persona,
        availableModels: [LLMModel],
        onSave: @escaping (Persona) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.persona = persona
        self.availableModels = availableModels
        self.onSave = onSave
        self.onDelete = onDelete

        _name           = State(initialValue: persona.name)
        _systemPrompt   = State(initialValue: persona.systemPrompt)
        _preferredModel = State(initialValue: persona.preferredModel ?? "")

        _useTemperature = State(initialValue: persona.temperature != nil)
        _temperature    = State(initialValue: persona.temperature ?? 0.7)

        _useTopP        = State(initialValue: persona.topP != nil)
        _topP           = State(initialValue: persona.topP ?? 0.9)

        _useTopK        = State(initialValue: persona.topK != nil)
        _topK           = State(initialValue: Double(persona.topK ?? 40))

        _useMaxTokens   = State(initialValue: persona.maxTokens != nil)
        _maxTokensText  = State(initialValue: persona.maxTokens.map { String($0) } ?? "")
    }

    /// Assembles the current form state into a Persona value ready for saving.
    private var current: Persona {
        Persona(
            id: persona.id,
            name: name,
            systemPrompt: systemPrompt,
            temperature:    useTemperature ? temperature : nil,
            topP:           useTopP ? topP : nil,
            topK:           useTopK ? Int(topK) : nil,
            maxTokens:      useMaxTokens ? Int(maxTokensText) : nil,
            preferredModel: preferredModel.isEmpty ? nil : preferredModel
        )
    }

    private func save() { onSave(current) }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(name.isEmpty ? "New Persona" : name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete Persona")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Name ─────────────────────────────────────────────
                    FormSection(label: "NAME") {
                        TextField("Persona name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: name) { save() }
                    }

                    // ── System Prompt ─────────────────────────────────────
                    FormSection(label: "SYSTEM PROMPT") {
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 13))
                            .frame(minHeight: 100, maxHeight: 160)
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                            )
                            .onChange(of: systemPrompt) { save() }
                    }

                    // ── Preferred Model ───────────────────────────────────
                    FormSection(label: "PREFERRED MODEL") {
                        Picker("", selection: $preferredModel) {
                            Text("Any loaded model").tag("")
                            ForEach(availableModels, id: \.id) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: preferredModel) { save() }
                    }

                    Divider()

                    // ── Parameters header ─────────────────────────────────
                    Text("PARAMETERS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    // Temperature  0.0 – 2.0
                    ParameterSliderRow(
                        label: "Temperature",
                        isEnabled: $useTemperature,
                        value: $temperature,
                        range: 0.0...2.0,
                        displayValue: String(format: "%.2f", temperature)
                    )
                    .onChange(of: useTemperature) { save() }
                    .onChange(of: temperature) { save() }

                    // Top P  0.0 – 1.0
                    ParameterSliderRow(
                        label: "Top P",
                        isEnabled: $useTopP,
                        value: $topP,
                        range: 0.0...1.0,
                        displayValue: String(format: "%.2f", topP)
                    )
                    .onChange(of: useTopP) { save() }
                    .onChange(of: topP) { save() }

                    // Top K  0 – 100
                    ParameterSliderRow(
                        label: "Top K",
                        isEnabled: $useTopK,
                        value: $topK,
                        range: 0.0...100.0,
                        displayValue: String(Int(topK)),
                        step: 1.0
                    )
                    .onChange(of: useTopK) { save() }
                    .onChange(of: topK) { save() }

                    // Max Tokens (integer text field, no slider)
                    HStack {
                        Toggle("", isOn: $useMaxTokens)
                            .labelsHidden()
                            .onChange(of: useMaxTokens) { save() }
                        Text("Max Tokens")
                            .font(.system(size: 13))
                        Spacer()
                        if useMaxTokens {
                            TextField("e.g. 2048", text: $maxTokensText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: maxTokensText) { save() }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

private struct FormSection<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct ParameterSliderRow: View {
    let label: String
    @Binding var isEnabled: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String
    var step: Double? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                Text(label)
                    .font(.system(size: 13))
                Spacer()
                if isEnabled {
                    Text(displayValue)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            if isEnabled {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PersonasView()
        .environmentObject(ServerStateViewModel())
}
