# TxemAI MLX — Chat Phase 2

## Project context
TxemAI MLX is a native macOS SwiftUI app that acts as a frontend for oMLX,
a local LLM inference server running at localhost:8000.
The app already has a working chat window (ChatView.swift). This document
defines the next phase: a full-featured chat client for model testing.

## Existing chat code
- `Views/Chat/ChatView.swift` — working chat window with streaming, thinking indicator
- `Models/ServerModels.swift` — ChatMessage struct (id, role, content)
- `Services/APIClient.swift` — streamChat(model:messages:) method
- `Services/ServerStateViewModel.swift` — activeModelName, models list

## Storage conventions
All persistent data goes to `~/.txemai-mlx/` — create subdirectories as needed.
Use JSONEncoder/JSONDecoder for all persistence. No CoreData, no SQLite.

## Swift conventions
- macOS 26, Swift 6, SwiftUI only
- @MainActor for all ViewModels
- async/await, no Combine except @Published
- String(format:) for number formatting
- No new SPM dependencies
- Keep all existing #Preview blocks working

---

## TASK 1 — Data models (do this first, everything depends on it)

Create `Models/ChatModels.swift` with these structs:

```swift
// A "Persona" = system prompt + model parameters
struct Persona: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String               // display name, e.g. "Logic Tester"
    var systemPrompt: String       // sent as role: "system" message
    var temperature: Double?       // nil = use model default
    var topP: Double?
    var topK: Int?
    var maxTokens: Int?
    var preferredModel: String?    // model id, nil = use whatever is loaded
}

// A single chat session
struct ChatSession: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String              // auto-generated from first user message (first 50 chars)
    var folderId: UUID?            // nil = root level
    var personaId: UUID?           // nil = no persona
    var modelId: String?           // which model was used
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var messages: [PersistedMessage] = []
}

// A message stored on disk (richer than the in-memory ChatMessage)
struct PersistedMessage: Identifiable, Codable {
    var id: UUID = UUID()
    var role: String               // "user" | "assistant" | "system"
    var content: String
    var timestamp: Date = Date()
    var tokensPerSecond: Double?   // filled for assistant messages
    var durationSeconds: Double?   // filled for assistant messages
}

// A folder for grouping chats
struct ChatFolder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
}
```

## TASK 2 — Persistence service

Create `Services/ChatStore.swift`:

```swift
@MainActor
class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published var folders: [ChatFolder] = []
    @Published var sessions: [ChatSession] = []
    @Published var personas: [Persona] = []

    // Base directory: ~/.txemai-mlx/
    // folders.json, sessions/{uuid}.json, personas.json

    func save(session: ChatSession)
    func delete(session: ChatSession)
    func move(session: ChatSession, to folder: ChatFolder?)
    func save(folder: ChatFolder)
    func rename(folder: ChatFolder, to name: String)
    func delete(folder: ChatFolder)   // also moves its sessions to root
    func save(persona: Persona)
    func delete(persona: Persona)

    func load()   // called on init, loads everything from disk
}
```

Storage layout:
```
~/.txemai-mlx/
├── folders.json          — [ChatFolder]
├── personas.json         — [Persona]
└── chats/
    ├── {uuid}.json       — ChatSession (one file per session)
    └── ...
```

## TASK 3 — Personas manager

Create `Views/Chat/PersonasView.swift`:
- Sheet accessible from the chat toolbar
- List of personas with name and system prompt preview
- Add / Edit / Delete buttons
- Edit form: name field, system prompt text editor (multiline),
  temperature slider (0.0-2.0), top_p (0.0-1.0), top_k (0-100),
  max tokens field, preferred model picker (from serverState.models)
- Changes saved immediately via ChatStore.shared.save(persona:)
- Match existing dark visual style

## TASK 4 — Chat history sidebar

Redesign ChatView.swift into a two-panel layout:

```
┌─────────────────────┬─────────────────────────────────┐
│   History sidebar   │      Active chat area           │
│                     │                                 │
│  [+ New Chat]       │  [model] [persona picker] [···] │
│                     │  ─────────────────────────────  │
│  FOLDERS            │                                 │
│  ▶ Logic Tests      │     messages scroll area        │
│  ▶ Code Review      │                                 │
│                     │  ─────────────────────────────  │
│  RECENT             │  [input field]  [send]          │
│  · Chat with GLM    │                                 │
│  · Test session 2   │                                 │
│                     │                                 │
└─────────────────────┴─────────────────────────────────┘
```

Left panel (220px fixed):
- "+ New Chat" button at top
- Folders section: expandable, click to filter sessions inside
- Sessions list: title + date, click to load
- Right-click context menu on sessions: rename, move to folder, delete
- Right-click on folders: rename, delete
- "Manage Folders" button at bottom

Right panel (existing chat area, enhanced):
- Toolbar: model indicator, persona picker dropdown, "···" menu
  (the "···" menu has: export chat as markdown, clear chat)
- Messages area (existing ChatBubble, keep as-is)
- Below each assistant message: show token/s and duration if available
- Input area (existing, keep as-is)

When "+ New Chat" is clicked:
- Clear messages, set current session to nil
- Auto-save previous session if it had messages

When a session is clicked in sidebar:
- Load its messages into the chat area
- Set active persona and model from session metadata

Auto-save behavior:
- When first user message sent: create a ChatSession, title = first 50 chars of message
- After each assistant response completes: update session on disk
- Sessions updated_at is refreshed on every save

## TASK 5 — File & image attachments

Add file attachment support to the input area.

- Add a paperclip button (SF Symbol: "paperclip") to the left of the input field
- Clicking opens NSOpenPanel to select files
- Supported types: .txt, .md, .swift, .py, .js, .ts, .json, .csv, .pdf (text extraction only)
- Supported images: .jpg, .jpeg, .png, .gif, .webp
- For text files: read content and prepend to the user message as a code block
  ``` 
  [filename.swift]
  ```swift
  <file content>
  ```
  ```
- For images: if the loaded model supports vision (check model name for VLM indicators:
  "vl", "vision", "vlm", "pixtral", "llava", "qwen-vl", "glm-4v"):
  encode as base64 and send via the OpenAI vision API format
  (content array with type "image_url" using data URI)
- Show attached files as small chips above the input field, with an × to remove
- Max 3 attachments at once

For the vision API call, update streamChat in APIClient.swift to accept
an optional [AttachmentItem] parameter where AttachmentItem is:
```swift
enum AttachmentItem {
    case text(filename: String, content: String)
    case image(filename: String, base64: String, mimeType: String)
}
```

## Implementation order
Task 1 → Task 2 → Task 3 → Task 4 → Task 5
Compile and verify after each task.
Do NOT change DashboardView, MetricsRowView, SparklineView, LogsView.
Keep all existing #Preview blocks working with mock data.
