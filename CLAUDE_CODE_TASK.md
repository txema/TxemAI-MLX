# Tarea para Claude Code — TxemAI MLX

## Contexto
Estoy construyendo TxemAI MLX, una app SwiftUI nativa para macOS que actúa como frontend 
para un servidor de inferencia LLM local (fork de oMLX). El backend es FastAPI corriendo 
en localhost:8000, completamente compatible con la API de OpenAI.

El proyecto está en: /Users/txema/Projects/IA/TxemAI-MLX

## Lo que existe y compila
- `TxemAI-MLX/Services/APIClient.swift` — cliente HTTP/WebSocket, todos los métodos son TODO
- `TxemAI-MLX/Services/ServerStateViewModel.swift` — ObservableObject central, usa mock data
- `TxemAI-MLX/Models/LLMModel.swift` — struct del modelo LLM
- `TxemAI-MLX/Models/ServerModels.swift` — ServerMetrics, LogEntry, ChatMessage

## Tu tarea: implementar la capa de datos real

### 1. APIClient.swift — implementar todos los métodos

**fetchModels()** — GET /v1/models
El servidor devuelve formato OpenAI estándar:
```json
{
  "object": "list",
  "data": [
    {"id": "Qwen3-Coder-Next", "object": "model", "created": 1234567890, "owned_by": "local"}
  ]
}
```
Mapear cada item a LLMModel. Para sizeGB y quantization, hacer GET /admin/api/models 
que devuelve info extendida de oMLX (explorar el endpoint, puede variar).

**connectMetricsStream()** — WebSocket ws://localhost:8000/admin/ws/metrics  
El servidor emite JSON cada segundo con esta estructura (aproximada, verificar en backend/omlx/):
```json
{
  "tokens_per_second": 24.3,
  "memory_used_gb": 89.2,
  "memory_total_gb": 128.0,
  "active_requests": 2,
  "queued_requests": 0,
  "cache_hit_percent": 78.0
}
```
Si el endpoint no existe en oMLX, implementar polling cada 2 segundos a GET /admin/api/stats 
como fallback.

**streamChat()** — POST /v1/chat/completions con stream: true  
Parsear Server-Sent Events (SSE). Cada línea tiene formato:
`data: {"choices":[{"delta":{"content":"token"}}]}`
Emitir cada token via AsyncThrowingStream.

**toggleModel()** — POST /admin/api/models/{id}/load o /unload  
Explorar el backend en backend/omlx/ para encontrar el endpoint correcto.

**togglePin()** — buscar endpoint en backend/omlx/

**startServer() / stopServer()** — lanzar/parar el proceso Python con Process():
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["python", "-m", "omlx", "serve", "--model-dir", "/Volumes/MLXLab/models-lmx"]
process.currentDirectoryURL = URL(fileURLWithPath: "/Users/txema/Projects/IA/TxemAI-MLX/backend")
```

### 2. ServerStateViewModel.swift — conectar a datos reales

- En `init()`, llamar a `api.connectMetricsStream()` y arrancar polling de modelos cada 10s
- Implementar `refreshModels()` que llama `api.fetchModels()` y actualiza `self.models`
- Mantener el mock data SOLO para previews (dentro de #if DEBUG)
- Gestionar errores de conexión con `@Published var connectionError: String?`
- Añadir `@Published var isConnected: Bool` que refleja si el WebSocket está activo

### 3. Exploración del backend
Antes de implementar, leer estos ficheros del backend para entender los endpoints reales:
- backend/omlx/server.py (o app.py) — rutas FastAPI
- backend/omlx/admin/ — rutas del panel de administración

## Restricciones importantes
- Todo async/await, sin callbacks salvo donde sea imprescindible (WebSocket receive)
- El ViewModel es @MainActor — toda actualización de @Published en main thread
- No usar Combine, solo async/await y AsyncStream
- Swift 6 — usar String(format:) no specifier: en interpolación
- Manejo de errores tipado — definir enum APIError en APIClient.swift

## Entregables
1. APIClient.swift completamente implementado
2. ServerStateViewModel.swift conectado a datos reales
3. El proyecto debe seguir compilando sin errores
4. Si encuentras que algún endpoint del backend no existe, implementarlo en Python 
   en backend/omlx/ y documentarlo en un comentario en el Swift

## Nota final
El hardware es Apple M4 Max con 128GB. Los modelos están en /Volumes/MLXLab/models-lmx/
