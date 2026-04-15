# TxemAI MLX

Native macOS frontend for [oMLX](https://github.com/jundot/omlx), a local LLM inference server running at `localhost:8000`. Built with SwiftUI on macOS 26 / Apple Silicon (M4 Max, 128 GB).

---

## Architecture

```
TxemAI-MLX/
├── App/
│   ├── TxemAI_MLXApp.swift       — @main, two WindowGroup scenes (main + chat)
│   └── AppDelegate.swift         — menu-bar status item + popover
│
├── Models/
│   ├── LLMModel.swift            — LLMModel struct (id, status, quantization, sizeGB, isPinned…)
│   ├── ServerModels.swift        — ServerMetrics, LogEntry, ChatMessage
│   ├── ChatModels.swift          — Persona, ChatSession, PersistedMessage, ChatFolder,
│   │                               FolderSettings, AttachmentItem
│   ├── BenchmarkModels.swift     — BenchmarkEvent, BenchmarkResult
│   ├── ModelConfig.swift         — ModelGenerationConfig, ModelSettingsUpdate
│   ├── GlobalSettings.swift      — GlobalSettings, GlobalSettingsUpdate
│   └── HFModels.swift            — HFModel, HFDownloadTask, response wrappers
│
├── Services/
│   ├── APIClient.swift           — all HTTP calls to oMLX; single shared singleton
│   ├── ServerStateViewModel.swift — @MainActor ObservableObject; polling loops for models,
│   │                               metrics, logs; injected via .environmentObject
│   ├── ChatStore.swift           — @MainActor ObservableObject; JSON persistence for
│   │                               sessions / folders / personas on ~/.txemai-mlx/
│   └── LogFileWatcher.swift      — DispatchSource tail -f fallback when /admin/api/logs is empty
│
└── Views/
    ├── ContentView.swift                       — NavigationSplitView root (sidebar + dashboard)
    ├── Dashboard/
    │   ├── DashboardView.swift                 — metrics + sparklines + logs container
    │   ├── MetricsRowView.swift                — t/s, memory, cache hit cards
    │   ├── SparklineView.swift                 — real-time sparkline charts
    │   ├── LogsView.swift                      — live log panel with level filters
    │   └── BenchmarkView.swift                 — PP/TG benchmark sheet (SSE progress)
    ├── ModelSidebar/
    │   ├── ModelSidebarView.swift              — model list rows, load/unload, pin
    │   ├── ModelSettingsSheet.swift            — per-model alias, TTL, sampling params
    │   └── HFDownloaderSheet.swift             — HuggingFace search + download manager
    ├── Chat/
    │   ├── ChatView.swift                      — two-panel chat (sidebar + active chat)
    │   ├── PersonasView.swift                  — persona CRUD sheet
    │   └── FolderSettingsSheet.swift           — folder system-prompt + sampling overrides
    └── Settings/
        ├── SettingsView.swift                  — initial API key setup sheet
        └── GlobalSettingsView.swift            — full server config sheet
```

### Persistent data layout

```
~/.txemai-mlx/
├── folders.json          — [ChatFolder]   (whole array, rewritten on every change)
├── personas.json         — [Persona]      (whole array, rewritten on every change)
├── chats/
│   ├── {uuid}.json       — ChatSession    (one file per session)
│   └── …
└── avatars/
    └── {folder-uuid}.jpg — folder avatar images (always stored as .jpg)
```

---

## Tech Stack

| Layer | Choice |
|---|---|
| Platform | macOS 26 (Sequoia), Apple Silicon |
| Language | Swift 6 |
| UI | SwiftUI only (no AppKit views except `NSOpenPanel`, `NSStatusBar`, `NSHostingController`) |
| Concurrency | `async/await`, `AsyncThrowingStream` — no Combine except `@Published` |
| Persistence | `JSONEncoder` / `JSONDecoder` to `~/.txemai-mlx/` — no CoreData, no SQLite |
| Markdown rendering | [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (`import MarkdownUI`) |
| Network | `URLSession` bytes streaming for SSE; no third-party HTTP libs |
| Log watching | `DispatchSource` VNODE_EXTEND on `~/.omlx/logs/server.log` (fallback when API is empty) |

---

## oMLX API Endpoints

All `/admin/api/*` calls authenticate via **session cookie** set by `POST /admin/api/login`.  
All `/v1/*` calls authenticate via **`Authorization: Bearer <api_key>`** header.

### Authentication

```
POST /admin/api/login
Body:  {"api_key": "mysecretkey", "remember": true}
→ 200 OK  (sets session cookie)
```

### Models

```
GET /admin/api/models
→ {
    "models": [
      {
        "id": "Qwen3-Coder-Next",
        "model_path": "/Volumes/MLXLab/models-lmx/Qwen3-Coder-Next",
        "loaded": true,
        "is_loading": false,
        "estimated_size": 91500000000,
        "pinned": false,
        "settings": {
          "model_alias": null,
          "display_name": "Qwen3 Coder Next",
          "is_pinned": false,
          "temperature": null,
          "top_p": null,
          "top_k": null,
          "ttl_seconds": null
        }
      }
    ]
  }

POST /admin/api/models/{id}/load    → 200 OK
POST /admin/api/models/{id}/unload  → 200 OK

GET /admin/api/models/{id}/generation_config
→ {
    "temperature": 0.7,
    "top_p": 0.9,
    "top_k": 50,
    "repetition_penalty": 1.1,
    "max_context_window": 32768
  }

PUT /admin/api/models/{id}/settings
Body (all fields optional, only sent fields are updated):
  {
    "model_alias": "My Alias",
    "is_pinned": true,
    "ttl_seconds": 300,
    "temperature": 0.8,
    "top_p": 0.95,
    "top_k": 40,
    "repetition_penalty": 1.05
  }
→ 200 OK
```

### Server Stats

```
GET /admin/api/stats
→ {
    "avg_generation_tps": 24.3,
    "avg_prefill_tps": 1850.0,
    "cache_efficiency": 0.78,
    "total_tokens_served": 184200,
    "total_cached_tokens": 43000,
    "total_prompt_tokens": 55000,
    "total_requests": 142
  }
```

Note: `memory_used_gb` is **not** in this response — the app computes it client-side from the
sum of `estimated_size` of all loaded models.

### Logs

```
GET /admin/api/logs?lines=200
→ {"logs": "2026-04-13 10:12:01,123 - omlx.server - INFO - [req_abc] - request completed\n..."}
```

The response is a single multiline string (not a JSON array). The app splits on `\n` and
parses each line with the format: `<timestamp> - <logger> - <LEVEL> - [<req_id>] - <message>`.
ANSI color codes are stripped with a regex before parsing.

### HuggingFace Downloader

```
GET /admin/api/hf/recommended
→ {"trending": [HFModel…], "popular": [HFModel…]}

GET /admin/api/hf/search?q=qwen&limit=50
→ {"models": [HFModel…], "total": 12}

HFModel shape:
  {
    "repo_id": "mlx-community/Qwen3-Coder-Next-8bit",
    "name": "Qwen3 Coder Next 8bit",
    "downloads": 45000,
    "likes": 320,
    "trending_score": 8.4,
    "size": 91500000000,
    "size_formatted": "85.2 GB",
    "params": 110000000000,
    "params_formatted": "110B"
  }

POST /admin/api/hf/download
Body: {"repo_id": "mlx-community/Qwen3-Coder-Next-8bit", "hf_token": ""}
→ {"success": true, "task": HFDownloadTask}

GET /admin/api/hf/tasks
→ {"tasks": [HFDownloadTask…]}

HFDownloadTask shape:
  {
    "task_id": "abc-123",        ← primary key; Swift maps to taskId
    "repo_id": "mlx-community/…",
    "status": "downloading",     ← "pending"|"downloading"|"completed"|"failed"|"cancelled"
    "progress": 42.7,
    "total_size": 91500000000,
    "downloaded_size": 38900000000,
    "error": "",
    "created_at": 1744560000.0,
    "started_at": 1744560001.0,
    "completed_at": 0.0,
    "retry_count": 0
  }

POST /admin/api/hf/cancel/{task_id}  → 200 OK
DELETE /admin/api/hf/task/{task_id}  → 200 OK
```

### Benchmark

```
POST /admin/api/bench/start
Body: {
  "model_id": "Qwen3-Coder-Next",
  "prompt_tokens": 1024,
  "completion_tokens": 128,
  "runs": 1
}
→ {"bench_id": "xyz-789"}   ← decoded via convertFromSnakeCase

GET /admin/api/bench/{bench_id}/stream   ← SSE
Each event line: "data: <JSON>"

BenchmarkEvent shapes:
  Progress:  {"type":"progress","phase":"single","message":"Running…","current":1,"total":3}
  Result:    {"type":"result","data":{"test_type":"single","pp":1024,"tg":128,
               "gen_tps":24.1,"processing_tps":1820.0,"ttft_ms":55.2,"batch_size":null}}
  Done:      {"type":"done","summary":{"model_id":"…","total_time":12.4,"total_tests":3}}
  Error:     {"type":"error","message":"…"}

POST /admin/api/bench/{bench_id}/cancel  → 200 OK
```

### Global Settings

```
GET /admin/api/global-settings
→ {
    "server":    {"host":"localhost","port":8000,"log_level":"INFO"},
    "memory":    {"max_process_memory":null,"prefill_memory_guard":true},
    "scheduler": {"max_concurrent_requests":4},
    "cache":     {"enabled":true,"ssd_cache_dir":"/tmp/omlx_cache",
                  "ssd_cache_max_size":"50GB","hot_cache_max_size":null},
    "sampling":  {"max_context_window":null,"max_tokens":null,"temperature":null,
                  "top_p":null,"top_k":null,"repetition_penalty":null},
    "auth":      {"api_key_set":true,"api_key":"mysecretkey","skip_api_key_verification":false},
    "system":    {"total_memory":"128 GB","auto_model_memory":"112 GB","ssd_total":"2 TB"}
  }

POST /admin/api/global-settings
Body (only sent fields are updated, all optional):
  {
    "port": 8000,
    "host": "localhost",
    "log_level": "INFO",
    "max_process_memory": "120GB",
    "max_concurrent_requests": 4,
    "cache_enabled": true,
    "ssd_cache_dir": "/tmp/omlx_cache",
    "ssd_cache_max_size": "50GB",
    "hot_cache_max_size": "8GB",
    "sampling_max_context_window": 32768,
    "sampling_max_tokens": 4096,
    "sampling_temperature": 0.7,
    "sampling_top_p": 0.9,
    "sampling_top_k": 50,
    "sampling_repetition_penalty": 1.1,
    "api_key": "newkey",
    "skip_api_key_verification": false
  }
→ 200 OK

POST /admin/api/ssd-cache/clear  → 200 OK
```

### Chat Completions (OpenAI-compatible)

```
POST /v1/chat/completions
Headers: Authorization: Bearer <api_key>
Body:
  {
    "model": "Qwen3-Coder-Next",
    "stream": true,
    "messages": [
      {"role": "system",    "content": "You are a helpful assistant."},
      {"role": "user",      "content": "Hello!"},
      {"role": "assistant", "content": "Hi there!"},
      {"role": "user",      "content": "What is 2+2?"}
    ]
  }

SSE stream — each event:
  data: {"choices":[{"delta":{"content":"The answer"}}]}
  …
  data: [DONE]
```

For vision models (name contains `vl`, `vision`, `vlm`, `pixtral`, `llava`, `qwen-vl`,
`glm-4v`, or `minicpm-v`), the last user message uses multimodal content:

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "Describe this image."},
    {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,<base64>"}}
  ]
}
```

---

## Data Models (Swift)

### `Persona` — system prompt + sampling overrides

```swift
struct Persona: Identifiable, Codable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var temperature: Double?    // nil = use model default
    var topP: Double?
    var topK: Int?
    var maxTokens: Int?
    var preferredModel: String? // model id; nil = use whatever is loaded
}
```

### `ChatSession` — one conversation thread

```swift
struct ChatSession: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String           // first 50 chars of the first user message
    var folderId: UUID?         // nil = root level
    var personaId: UUID?
    var modelId: String?        // model used in this session
    var createdAt: Date
    var updatedAt: Date
    var messages: [PersistedMessage]
}
// Equatable/Hashable by id only — avoids comparing the messages array
```

### `PersistedMessage` — message stored on disk

```swift
struct PersistedMessage: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var role: String            // "user" | "assistant" | "system"
    var content: String
    var timestamp: Date
    var tokensPerSecond: Double?   // assistant messages only
    var durationSeconds: Double?   // assistant messages only
    var imageBase64: String?       // base64 image data attached by user
    var textAttachmentNames: [String]  // filenames of text attachments shown in bubble
}
```

### `FolderSettings` — sampling overrides stored per folder

```swift
struct FolderSettings: Codable {
    var systemPrompt: String
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var maxTokens: Int?
}
```

### `ChatFolder` — groups chat sessions

```swift
struct ChatFolder: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var settings: FolderSettings  // system prompt + sampling overrides for all chats in folder
    var avatarPath: String?       // absolute path to a .jpg in ~/.txemai-mlx/avatars/
}
```

### `AttachmentItem` — file attached before sending a message

```swift
enum AttachmentItem: Identifiable, Sendable {
    case text(filename: String, content: String)
    case image(filename: String, base64: String, mimeType: String)
}
```

Text attachments are prepended to the user message as fenced code blocks:

```
[filename.swift]
```swift
<file content>
```
```

Image attachments are sent via the OpenAI vision multimodal format.  
Supported text extensions: `.txt .md .swift .py .js .ts .json .csv .pdf`  
Supported image extensions: `.jpg .jpeg .png .gif .webp`  
Maximum 3 attachments per message.

---

## Swift Conventions

| Convention | Detail |
|---|---|
| `@MainActor` | All `ObservableObject` ViewModels (`ServerStateViewModel`, `ChatStore`) are annotated `@MainActor`. All `@Published` mutations happen on the main thread. |
| `async/await` | All network calls are `async throws`. No callbacks except where required by system APIs (`NSOpenPanel.begin`, `NSWorkspace.openApplication`). |
| No Combine | `@Published` is used for reactive bindings. No `Combine` publishers, sinks, or subjects. |
| `AsyncThrowingStream` | SSE streaming (`streamChat`, `streamBenchmarkResults`) is exposed as `AsyncThrowingStream<T, Error>`. Cancellation is handled via `continuation.onTermination = { _ in task.cancel() }`. |
| `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` | The shared decoder in `APIClient` auto-converts all `snake_case` API fields to `camelCase` Swift properties. **The encoder does NOT use `.convertToSnakeCase`** — DTOs that need explicit snake_case output use custom `CodingKeys` enums instead. |
| Number formatting | `String(format: "%.1f", value)` — never string interpolation with format specifiers. |
| No new SPM packages | The only external dependency is `swift-markdown-ui`. Do not add others. |
| `#Preview` blocks | Every view file has a working `#Preview` block using mock/static data. Never break these. |
| Singletons | `APIClient.shared`, `ChatStore.shared` — safe to call from any `@MainActor` context. |
| Storage | All disk I/O uses `JSONEncoder` / `JSONDecoder`. `ChatSession` is one file per UUID; `folders.json` and `personas.json` are full-array rewrites on every change. |

---

## Known API Quirks

### 1. `api_key` in plaintext in both directions

`POST /admin/api/login` sends `{"api_key": "mykey"}` unencrypted.  
`GET /admin/api/global-settings` returns `{"auth": {"api_key": "mykey"}}` — the key is exposed in the response. This is intentional in the oMLX admin API (LAN-only service).

The app stores the key in `UserDefaults` under `"omlx_api_key"` and re-reads it on launch.

### 2. `task_id` vs `id` in `HFDownloadTask`

The JSON field is `task_id`. After `convertFromSnakeCase` this becomes `taskId` in Swift.  
The `Identifiable` conformance returns `taskId` via `var id: String { taskId }`.  
Cancel and delete endpoints use the raw `task_id` string in the URL path.

### 3. Benchmark SSE uses `type`, not `event:` or `status`

The SSE payload does not use the standard `event:` SSE field — it is always `data: <json>`.  
The JSON object has a `"type"` string field: `"progress"` | `"result"` | `"done"` | `"error"`.  
The stream loop breaks when `event.type == "done" || event.type == "error"`.

### 4. Stats field names differ from `ServerMetrics` property names

| JSON field | Swift property |
|---|---|
| `avg_generation_tps` | `tokensPerSecond` |
| `avg_prefill_tps` | `promptProcessingTps` |
| `cache_efficiency` | `cacheHitPercent` (0–1 float, displayed as %) |
| `total_prompt_tokens` | `totalPrefillTokens` |
| — (not in API) | `memoryUsedGB` (computed from loaded model sizes) |

### 5. Admin auth vs. OpenAI auth

`/admin/api/*` endpoints require a **session cookie** established by `POST /admin/api/login`.  
`/v1/*` endpoints require **`Authorization: Bearer <api_key>`** header.  
The app calls `login()` on startup and relies on cookie persistence across requests via a shared `URLSession` with `HTTPCookieStorage.shared`.

### 6. Log response is a single string, not an array

`GET /admin/api/logs` returns `{"logs": "<big multiline string>"}`, not a JSON array.  
The app splits on `\n`, strips ANSI codes, and parses each line with the format:  
`YYYY-MM-DD HH:mm:ss,mmm - <logger> - <LEVEL> - [<req_id>] - <message>`

### 7. Model memory is client-side computed

There is no `memory_used_gb` in `/admin/api/stats`. The app sums `estimated_size` (bytes) of
all `loaded == true` models and divides by `1_073_741_824` to get GB. Total is hardcoded at
128 GB (M4 Max spec).

### 8. `GlobalSettingsUpdate` uses manual `CodingKeys`

Because the encoder does **not** use `.convertToSnakeCase`, `GlobalSettingsUpdate` and
`ModelSettingsUpdate` declare explicit `CodingKeys` with snake_case raw values so the
outgoing JSON matches what the oMLX backend expects.

---

## Roadmap

### Phase 1 — Core infrastructure (done)
- `APIClient.swift` with all oMLX admin endpoints
- `ServerStateViewModel` polling models (5 s), metrics (2 s), logs (3 s)
- `LogFileWatcher` fallback to `~/.omlx/logs/server.log`

### Phase 2 — Model management (done)
- `ModelSidebarView` — load/unload, pin, status badges
- `ModelSettingsSheet` — alias, TTL, temperature, top-p, top-k (reads `generation_config`)
- `HFDownloaderSheet` — search + recommended tabs, download progress, cancel/remove

### Phase 3 — Dashboard & tooling (done)
- `DashboardView` with live `MetricsRowView`, `SparklineView`, `LogsView`
- `BenchmarkView` — PP/TG throughput tests, SSE progress, result table
- `GlobalSettingsView` — server, memory, cache, sampling, auth config

### Phase 4 — Chat client (done)
- `ChatModels.swift` — `Persona`, `ChatSession`, `PersistedMessage`, `ChatFolder`, `FolderSettings`
- `ChatStore.swift` — JSON persistence under `~/.txemai-mlx/`
- `PersonasView.swift` — CRUD sheet with system prompt + sampling overrides
- `ChatView.swift` — two-panel layout (history sidebar + active chat), folder grouping,
  markdown rendering via `MarkdownUI`, token/s + duration per assistant message,
  inline rename, right-click context menus, auto-save on first message

### Phase 5 — Attachments (done)
- `AttachmentItem` enum (text / image)
- `NSOpenPanel` file picker with type filtering, max 3 attachments
- Text files prepended as fenced code blocks
- Images sent as base64 data URIs in OpenAI vision multimodal format
- Vision model auto-detection from model name keywords
- Attachment chips UI above input field

### Planned
- Export chat as Markdown
- `FolderSettings.systemPrompt` injected as `system` role message per session
- Streaming token count + per-message stats displayed in chat
- Multi-model parallel chat (A/B comparison)
