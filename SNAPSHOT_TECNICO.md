# CortexML — Snapshot Técnico
*Fecha: 23 abril 2026 · Estado: pausado en Phase 7 (voice descartado)*

---

## 1. Visión general

CortexML es una app nativa macOS (SwiftUI) que actúa como frontend para **oMLX**, un servidor local de inferencia LLM construido sobre MLX y Apple Silicon. El objetivo es reemplazar la interfaz web de administración de oMLX con una experiencia nativa de primera clase, manteniendo el backend Python/FastAPI intacto.

**Hardware de referencia:** Apple M4 Max, 128 GB unified memory, macOS 26 (Sequoia), Xcode 26.

---

## 2. Repositorio

```
/Users/txema/Projects/IA/TxemAI-MLX/
├── CortexML/                  ← Fuentes Swift (target principal)
│   ├── App/
│   ├── Assets.xcassets/
│   ├── Models/
│   ├── Services/
│   ├── Theme/
│   ├── Views/
│   └── TxemAI_MLX.entitlements
├── CortexML.xcodeproj/
├── backend/                   ← oMLX git subtree (packaging/dist/oMLX.app = bundle Python)
├── backend-wrapper/           ← Scripts de arranque y build DMG
│   ├── start_server.sh        ← Arranca oMLX en puerto 8000
│   ├── build_dmg.sh           ← Pipeline para DMG distribuible
│   └── dist/                  ← Artefactos de build
└── README.md                  ← Documentación de la API de oMLX
```

**Git remote:** GitHub bajo organización TxemAI.

---

## 3. Stack tecnológico

| Capa | Decisión |
|---|---|
| Plataforma | macOS 26 (Sequoia), Apple Silicon exclusivo |
| Lenguaje | Swift 6 |
| UI | SwiftUI puro (sin AppKit salvo NSOpenPanel, NSStatusBar, NSAlert) |
| Concurrencia | `async/await` + `AsyncThrowingStream` — sin Combine salvo `@Published` |
| Persistencia | JSONEncoder/JSONDecoder a `~/.cortexML/` — sin CoreData ni SQLite |
| Markdown | [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — única dep externa |
| Red | URLSession + streaming SSE manual — sin librerías HTTP externas |
| Log watching | DispatchSource VNODE_EXTEND sobre `~/.omlx/logs/server.log` (fallback) |

### Entitlements activos
- `com.apple.security.app-sandbox`: true
- `com.apple.security.network.client`: true (necesario para localhost)

---

## 4. Arquitectura de la aplicación

### 4.1 Estructura de ficheros Swift

```
CortexML/
├── App/
│   ├── CortexMLApp.swift          ← @main, dos WindowGroup (main + chat)
│   └── AppDelegate.swift          ← Menu bar status item + icono cerebro animado
│
├── Models/
│   ├── LLMModel.swift             ← LLMModel (id, status, quantization, sizeGB, isPinned…)
│   ├── ServerModels.swift         ← ServerMetrics, LogEntry, ChatMessage
│   ├── ChatModels.swift           ← Persona, ChatSession, PersistedMessage, ChatFolder,
│   │                                 FolderSettings, AttachmentItem
│   ├── BenchmarkModels.swift      ← BenchmarkEvent, BenchmarkResult
│   ├── ModelConfig.swift          ← ModelGenerationConfig, ModelSettingsUpdate
│   ├── GlobalSettings.swift       ← GlobalSettings, GlobalSettingsUpdate
│   └── HFModels.swift             ← HFModel, HFDownloadTask, response wrappers
│
├── Services/
│   ├── APIClient.swift            ← Todas las llamadas HTTP a oMLX (singleton compartido)
│   ├── ServerStateViewModel.swift ← @MainActor ObservableObject; loops de polling
│   │                                 modelos (5s), métricas (2s), logs (3s)
│   ├── ServerManager.swift        ← Lifecycle del servidor embebido (Process + Pipe)
│   ├── ChatStore.swift            ← @MainActor ObservableObject; persistencia JSON
│   └── LogFileWatcher.swift       ← Tail -f fallback cuando /admin/api/logs está vacío
│
├── Theme/
│   ├── CortexTheme.swift          ← Design tokens (colores, tipografía) via Environment
│   └── AccentPreset.swift         ← 5 presets de color de acento
│
└── Views/
    ├── ContentView.swift          ← NavigationSplitView raíz (sidebar + dashboard)
    ├── Dashboard/
    │   ├── DashboardView.swift
    │   ├── MetricsRowView.swift   ← 8 tiles de métricas en grid 4×2
    │   ├── SparklineView.swift    ← Sparklines en tiempo real
    │   ├── ThroughputChartView.swift ← Gráfico de área de throughput
    │   ├── CacheTierBarView.swift ← Barra de tier de caché
    │   ├── LogsView.swift         ← Panel de logs con filtros por nivel
    │   └── BenchmarkView.swift    ← Sheet de benchmark PP/TG con SSE
    ├── ModelSidebar/
    │   ├── ModelSidebarView.swift ← Lista de modelos, load/unload, pin, badges
    │   ├── ModelSettingsSheet.swift ← Config por modelo (alias, TTL, sampling)
    │   └── HFDownloaderSheet.swift  ← Buscador HF + gestor de descargas
    ├── Chat/
    │   ├── ChatView.swift         ← Chat completo (sidebar + área activa)
    │   ├── PersonasView.swift     ← CRUD de personas (system prompt + sampling)
    │   ├── ParametersPanelView.swift ← Panel lateral de parámetros de generación
    │   └── FolderSettingsSheet.swift ← System prompt + sampling por carpeta
    └── Settings/
        ├── SettingsView.swift     ← Setup inicial de API key
        └── GlobalSettingsView.swift ← Config completa del servidor
```

### 4.2 Flujo de datos principal

```
oMLX (Puerto 8000)
    ↓ HTTP polling (2-5s)
ServerStateViewModel (@MainActor, @Published)
    ↓ .environmentObject
ContentView
    ├── ModelSidebarView   ← modelos + acciones
    ├── DashboardView      ← métricas + logs
    └── [chat window]
        └── ChatView       ← streaming SSE
```

### 4.3 Modo servidor embebido

`ServerManager.swift` gestiona el lifecycle del servidor oMLX embebido:
- Lanza `/bin/bash backend-wrapper/start_server.sh` via `Process()`
- Captura stdout/stderr via `Pipe` y detecta `"Application startup complete"` para marcar estado `.running`
- Resolución del script: primero en `Bundle.main` (producción), luego path hardcodeado en dev
- En producción el bundle Python de oMLX está en `backend/packaging/dist/oMLX.app/Contents/`

---

## 5. Backend: oMLX

oMLX es un servidor FastAPI (Python 3.11 + MLX) para inferencia local de LLMs en Apple Silicon. Se integra como **git subtree** en `backend/` y se distribuye como `.app` bundle usando **venvstacks** para empaquetar el entorno Python completo.

### 5.1 Autenticación dual

| Endpoint | Auth |
|---|---|
| `/admin/api/*` | Cookie de sesión (POST /admin/api/login) |
| `/v1/*` | Bearer token (`Authorization: Bearer <api_key>`) |

El cliente Swift hace login al arrancar y usa `HTTPCookieStorage.shared` para persistir la cookie entre peticiones.

### 5.2 Endpoints principales

```
# Auth
POST /admin/api/login              → establece cookie de sesión

# Modelos
GET  /admin/api/models             → lista completa con estado
POST /admin/api/models/{id}/load
POST /admin/api/models/{id}/unload
GET  /admin/api/models/{id}/generation_config
PUT  /admin/api/models/{id}/settings

# Stats (polling cada 2s)
GET  /admin/api/stats              → métricas de throughput, caché, tokens

# Logs (polling cada 3s)
GET  /admin/api/logs?lines=200     → string multilinea (no array JSON)

# HuggingFace Downloader
GET  /admin/api/hf/recommended
GET  /admin/api/hf/search?q=...
POST /admin/api/hf/download        → inicia descarga, devuelve task_id
GET  /admin/api/hf/tasks

# Benchmark (SSE)
POST /admin/api/bench/start        → devuelve bench_id
GET  /admin/api/bench/{id}/stream  → SSE con eventos progress/result/done/error

# Config global
GET  /admin/api/global-settings
POST /admin/api/global-settings

# Chat (OpenAI-compatible, SSE)
POST /v1/chat/completions          → Bearer token, stream: true
```

### 5.3 Quirks conocidos de la API

1. **api_key en plaintext**: GET /global-settings devuelve la clave en claro (servicio LAN-only, intencional).
2. **task_id vs id**: HFDownloadTask usa `task_id` en JSON → `taskId` en Swift (convertFromSnakeCase).
3. **Benchmark SSE**: usa campo `type` en el JSON, no el campo `event:` estándar de SSE.
4. **Stats field mapping**: `avg_generation_tps` → `tokensPerSecond`, `cache_efficiency` (0-1) → `cacheHitPercent` (%), `memory_used_gb` NO existe — se computa sumando `estimated_size` de modelos cargados.
5. **Logs como string**: `/admin/api/logs` devuelve `{"logs": "<multiline string>"}`, no array. Se parsea con regex para extraer timestamp, level y message.
6. **GlobalSettingsUpdate usa CodingKeys manuales**: el encoder NO usa `.convertToSnakeCase` por defecto, así que los DTOs de actualización declaran `CodingKeys` explícitos.

---

## 6. Modelos de dominio (Swift)

### LLMModel
```swift
struct LLMModel: Identifiable, Codable, Sendable {
    let id: String              // repo path o nombre
    var status: Status          // loaded, loading, unloaded
    var quantization: String?
    var sizeGB: Double?
    var isPinned: Bool
    var settings: ModelSettings?
    var generationConfig: ModelGenerationConfig?
}
```

### ServerMetrics
```swift
struct ServerMetrics: Codable, Sendable {
    var tokensPerSecond: Double         // avg_generation_tps
    var memoryUsedGB: Double            // computed client-side
    var memoryTotalGB: Double           // hardcoded 128 (M4 Max)
    var memoryPressurePercent: Double
    var cacheHitPercent: Double         // cache_efficiency × 100
    var totalPrefillTokens: Int         // total_prompt_tokens
    var cachedTokens: Int
    var promptProcessingTps: Double     // avg_prefill_tps
}
```

### ChatMessage (in-memory)
```swift
struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role              // .user | .assistant | .system
    var content: String
    var imageData: Data?        // imagen adjunta (user)
    var textAttachmentNames: [String]
    var tokensPerSecond: Double?
    var durationSeconds: Double?
    var contentVariants: [String]   // branching/fork
    var activeVariant: Int
}
```

### Persistencia en disco
```
~/.cortexML/
├── folders.json       ← [ChatFolder] (reescritura completa en cada cambio)
├── personas.json      ← [Persona] (reescritura completa)
└── chats/
    └── {uuid}.json    ← ChatSession individual
```

---

## 7. Theming

Sistema de design tokens via `@Environment(\.cortexTheme)`:

```swift
struct CortexTheme {
    // Fondos
    var win, side, card, inp, btnBg: Color
    // Bordes
    var bd, inpBd, aB: Color
    // Texto
    var t1, t2, t3, t4, t5, lbl: Color
    // Acento
    var accent, aL: Color
    // Log panel (siempre oscuro)
    var logBg, logBd: Color
}
```

5 presets de acento (`AccentPreset`): emerald, blue, violet, rose, amber. Seleccionable en Settings → Appearance. Persistido en `@AppStorage("cortex_accent")`.

**Icono:** Cerebro azul eléctrico (#00aaff) sobre fondo oscuro (#1c1c1e). Anima entre `brain` y `brain.fill` en el menu bar según estado del servidor.

---

## 8. Funcionalidades implementadas

### Phase 1-3: Infraestructura + Dashboard
- [x] APIClient con todos los endpoints de oMLX
- [x] ServerStateViewModel con polling de modelos (5s), métricas (2s), logs (3s)
- [x] LogFileWatcher fallback
- [x] Dashboard: 8 tiles de métricas, sparklines, gráfico de throughput, barra de caché
- [x] Panel de logs con filtros ALL/ERRORS/WARNINGS
- [x] Benchmark PP/TG con SSE y tabla de resultados

### Phase 4-5: Chat
- [x] ChatView con sidebar de sesiones + área de chat activa
- [x] Carpetas con system prompt y overrides de sampling
- [x] Personas (system prompt + sampling predefinidos)
- [x] Streaming SSE con cancelación
- [x] Adjuntos: imágenes (vision multimodal) y ficheros texto (fenced code blocks)
- [x] Markdown rendering via swift-markdown-ui
- [x] Stats por mensaje (t/s, duración)
- [x] Export de chat como Markdown
- [x] Branching/fork de mensajes (variants)
- [x] Edición inline de mensajes de usuario

### Phase 6: Modelo sidebar + HF Downloader
- [x] ModelSidebarView con load/unload/pin y badges de estado
- [x] ModelSettingsSheet: alias, TTL, temperatura, top-p, top-k
- [x] HFDownloaderSheet: búsqueda HF, trending/popular, descarga con progreso, cancelación
- [x] GlobalSettingsView: servidor, caché SSD, sampling defaults, auth

### Phase 7: Voice Engine (DESCARTADO)
Se intentó implementar un motor de voz (TTS/STT) basado en mlx-audio (Qwen3-TTS + Whisper). Se descartó por:
- Complejidad de integración con el bundle Python de oMLX
- Problemas de SwiftUI con sheets anidados (layout recursivo, ViewBridge crashes)
- Scope excesivo para el estado actual del proyecto

**Todo el código de voz fue eliminado** en el commit de limpieza post-Phase 7.

---

## 9. Servidor embebido: distribución DMG

El script `backend-wrapper/build_dmg.sh` genera un DMG distribuible:

```
CortexML.app/
├── Contents/
│   ├── MacOS/
│   │   └── CortexML          ← binario Swift
│   ├── Frameworks/
│   │   └── cpython-3.11/     ← Python embebido (venvstacks)
│   ├── Resources/
│   │   └── (site-packages de oMLX)
│   └── _CodeSignature/
```

El Python 3.11 embebido (venvstacks + framework layers) incluye:
- mlx, mlx_lm, mlx_vlm, mlx_embeddings
- fastapi, uvicorn, pydantic
- transformers, huggingface_hub, safetensors
- librosa, soundfile (audio processing)
- spacy (NLP)
- y ~80 dependencias más

**Modelos:** Se almacenan en `/Volumes/MLXLab/models-lmx/` (no se distribuyen con el DMG). El usuario los descarga via HFDownloaderSheet.

---

## 10. Convenciones Swift

| Convención | Detalle |
|---|---|
| `@MainActor` | Todos los `ObservableObject` ViewModels están anotados `@MainActor` |
| Sin Combine | Solo `@Published` para bindings reactivos. Sin publishers, sinks ni subjects |
| `AsyncThrowingStream` | SSE de chat y benchmark expuesto como `AsyncThrowingStream<T, Error>` |
| `convertFromSnakeCase` | El decoder compartido en APIClient convierte automáticamente snake_case → camelCase |
| Sin encoder global | El encoder NO usa `.convertToSnakeCase`. Los DTOs de escritura usan `CodingKeys` explícitos |
| Formato numérico | `String(format: "%.1f", value)` — nunca interpolación con especificadores |
| Sin nuevas dependencias SPM | Solo `swift-markdown-ui`. No añadir otras |
| `#Preview` | Cada fichero de vista tiene un `#Preview` funcional con datos estáticos |
| Singletons | `APIClient.shared`, `ChatStore.shared` — seguros desde cualquier contexto `@MainActor` |
| Storage | `ChatSession`: un fichero JSON por UUID. `folders.json` y `personas.json`: reescritura completa |

---

## 11. Decisiones de arquitectura clave

### 11.1 oMLX como git subtree (no submodule)
oMLX se integra como subtree en `backend/` para facilitar el packaging. Un submodule requeriría que el usuario hiciera checkout separado; el subtree permite incluir el código en el mismo repositorio.

### 11.2 Polling vs WebSocket
oMLX devuelve 404 en su endpoint WebSocket (versión DMG). Se optó por **HTTP polling** cada 2s para métricas. Es menos eficiente pero funciona con la versión distribuida de oMLX.

### 11.3 Modo embedded vs external
La app soporta dos modos:
- **Embedded**: oMLX corre dentro del bundle de la app (arranque via ServerManager)
- **External**: La app conecta a un oMLX externo (standalone oMLX.app o servidor remoto)

El modo se selecciona en Settings y se persiste en `@AppStorage("serverMode")`.

### 11.4 Autenticación dual en oMLX
- `/admin/api/*` usa cookie de sesión (establecida por login al arrancar)
- `/v1/*` usa Bearer token
Son sistemas completamente separados. El cliente guarda la API key en UserDefaults bajo `"cortex_api_key"`.

### 11.5 Sin CoreData
Toda la persistencia usa JSONEncoder/JSONDecoder directamente a disco. Para el volumen de datos de chat (centenares de sesiones) es suficiente y elimina la complejidad de CoreData.

### 11.6 Theming via Environment
Los design tokens se distribuyen via `@Environment(\.cortexTheme)` en lugar de constantes globales. Esto permite que en el futuro se soporten temas claros/oscuros sin modificar las vistas.

---

## 12. Issues conocidos y deuda técnica

### Bugs pendientes
- **ForEach IDs**: resuelto en ThroughputChartView (xLabels) y ChatView (textAttachmentNames) usando `enumerated()` + `id: \.offset`
- **GlobalSettingsView**: el ForEach de startupLog ya usa `\.offset`

### Deuda técnica
- El **README.md** en raíz del repo documenta la API de oMLX pero no la arquitectura de la app Swift (este documento cubre eso)
- `CLAUDE.md` en raíz sirve como contexto para sesiones de Claude Code
- El `path/` en raíz del repo parece un artefacto accidental — debería limpiarse

### Consideraciones futuras
- **Tauri como alternativa UI**: se evaluó brevemente. Permitiría abandonar Xcode como IDE (usar VSCode), frontend en React/TypeScript, DMG via `tauri build`. El backend Python quedaría intacto. No se implementó.
- **RAG**: `mlx_embeddings` ya está en el bundle. Se podría añadir búsqueda semántica sobre el historial de chat
- **Fine-tuning**: explorado conceptualmente ("Project Brain") pero sin implementación
- **Widget macOS (WidgetKit)**: también explorado pero no implementado

---

## 13. Modelos disponibles

Modelos probados en el sistema de referencia (M4 Max, 128GB):

| Modelo | Tamaño | Notas |
|---|---|---|
| Qwen3-Coder-Next | ~91GB | Modelo principal de código |
| Gemma-4 | variable | Multimodal |
| Qwen3.5 | variable | General purpose |
| DeepSeek V3 | variable | Reasoning |

Almacenados en `/Volumes/MLXLab/models-lmx/`. HuggingFace presence bajo organización **TxemAI**.

---

## 14. Cómo continuar el proyecto

### Setup de desarrollo
```bash
# Clonar repo
git clone <repo-url> /Users/txema/Projects/IA/TxemAI-MLX
cd TxemAI-MLX

# Abrir en Xcode
open CortexML.xcodeproj

# Resolver dependencias SPM (swift-markdown-ui)
# File → Packages → Resolve Package Versions

# Arrancar oMLX externamente (o usar modo embedded desde la app)
./backend-wrapper/start_server.sh

# Build y run desde Xcode (⌘R)
```

### Variables de entorno del servidor
```bash
OMLX_PORT=8000
OMLX_BASE_PATH=~/.omlx
OMLX_API_KEY=<tu-api-key>
OMLX_MODEL_DIR=/Volumes/MLXLab/models-lmx
```

### Próximas features posibles
1. **Export/import de sesiones** — backup de historial de chat
2. **Búsqueda global** — buscar en todas las sesiones, no solo la activa
3. **Multi-model A/B** — comparar respuestas de dos modelos en paralelo
4. **Shortcuts de teclado** — navegación rápida entre sesiones y vistas
5. **Reconsiderar Tauri** — si la frustración con SwiftUI continúa

---

*Documento generado el 23 de abril de 2026. Refleja el estado del repo en rama `main` tras eliminar el código de voice engine (Phase 7).*
