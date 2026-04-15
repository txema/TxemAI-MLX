# Phase 5 — Backend Integration Roadmap

## Objective

Convert TxemAI MLX into a **self-contained app** with oMLX Python embedded inside the
`.app` bundle. The user installs one DMG, double-clicks the app, and gets a fully working
LLM inference stack — no Homebrew, no `pip install`, no terminal setup required.

**Key insight from source analysis:** oMLX already has a complete, production-grade
`venvstacks` packaging pipeline in `backend/packaging/`. We do **not** need to rebuild
this from scratch. The plan is: run their build pipeline as-is, strip the PyObjC
menu-bar layer (`app-omlx-app`) we don't need, add our own `start_server.sh` launcher,
and wire it into Xcode. The hard work is already done.

---

## Git Subtree Strategy

oMLX lives at `backend/` as a **git subtree** (already added). This keeps the upstream
code reviewable in-tree while allowing a clean pull workflow.

```bash
# Sync future upstream updates
git subtree pull --prefix=backend https://github.com/jundot/omlx main --squash
```

**Rule: never modify files inside `backend/`.** All customizations live in wrapper
scripts or Swift code outside that directory. This keeps `git subtree pull` conflict-free.

**Files to watch after every sync:**

| File | What to check |
|---|---|
| `backend/packaging/venvstacks.toml` | Dep bumps → need to rebuild bundle |
| `backend/omlx/api/` (or `routes/`) | Endpoint changes → update `APIClient.swift` + `README.md` |
| `backend/omlx/cli.py` | CLI arg changes → update `start_server.sh` |
| `backend/omlx/server.py` | App init / uvicorn startup changes → update startup detection logic |

---

## Bundle Structure (Final)

oMLX's `build.py` produces three venvstacks layers exported to `packaging/_export/`:

```
packaging/_export/
├── cpython-3.11/                      ← Python 3.11.10 runtime (ARM64)
├── framework-mlx-framework/           ← all ML deps (mlx, mlx-lm, mlx-vlm,
│   └── lib/python3.11/site-packages/    mlx-embeddings, mlx-audio, fastapi,
│                                        uvicorn, transformers, tokenizers…)
└── app-omlx-app/                      ← PyObjC menu-bar app layer
    └── lib/python3.11/site-packages/    (pyobjc-core, pyobjc-framework-Cocoa)
```

**We use only the first two layers.** `app-omlx-app` is the Python menu bar that oMLX
ships; TxemAI's Swift `AppDelegate` replaces it entirely.

Target app bundle structure:

```
TxemAI-MLX.app/Contents/
├── MacOS/TxemAI-MLX                   ← Swift binary (CFBundleExecutable)
├── Resources/
│   ├── omlx/                          ← omlx Python package (from backend/omlx/)
│   └── start_server.sh                ← our server launcher script
└── Frameworks/
    ├── cpython-3.11/                  ← from venvstacks _export (runtime layer)
    └── framework-mlx-framework/       ← from venvstacks _export (framework layer)
    # app-omlx-app NOT included — replaced by Swift AppDelegate
```

**Note:** oMLX's `build.py` also copies `python3` into `Contents/MacOS/` and creates a
compiled C launcher (`_create_c_launcher`) that loads `libpython` in-process via
`Py_BytesMain`. **We do not need either.** Swift `Process()` launches `python3` directly
from `Frameworks/cpython-3.11/bin/python3` — no C trampoline required.

---

## Roadmap — 11 Tasks

**Critical path: Task 2 → Task 4 → Task 5 → Task 8 → Task 10**

---

### TASK 1 — git subtree `(DONE)`

`backend/` is already tracked as a git subtree pointing to the oMLX repo.

---

### TASK 2 — `build_server_bundle.sh` — adapt oMLX's build pipeline `(2–3 h)`

Create `scripts/build_server_bundle.sh`. This script wraps `backend/packaging/build.py`
to produce only the server layers (no `app-omlx-app`, no DMG, no C launcher).

```bash
#!/bin/bash
# scripts/build_server_bundle.sh
# Builds the Python server bundle for TxemAI-MLX using oMLX's venvstacks pipeline.
# Output: TxemAI-MLX/Resources/  (Frameworks/ + Resources/omlx/ + Resources/start_server.sh)
# Run once before each Xcode archive build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGING="$REPO_ROOT/backend/packaging"
EXPORT="$PACKAGING/_export"
XCODE_RESOURCES="$REPO_ROOT/TxemAI-MLX/Resources"
XCODE_FRAMEWORKS="$REPO_ROOT/TxemAI-MLX/Frameworks"

# Step 1: Build venvstacks layers (cpython-3.11 + framework-mlx-framework only)
# build.py builds all three layers; we simply don't copy app-omlx-app.
cd "$PACKAGING"
python build.py --skip-venv   # or omit --skip-venv for a clean build

# Step 2: Copy runtime + framework layers into Xcode target directories
rm -rf "$XCODE_FRAMEWORKS/cpython-3.11" "$XCODE_FRAMEWORKS/framework-mlx-framework"
mkdir -p "$XCODE_FRAMEWORKS"
cp -R "$EXPORT/cpython-3.11" "$XCODE_FRAMEWORKS/"
cp -R "$EXPORT/framework-mlx-framework" "$XCODE_FRAMEWORKS/"
# Intentionally NOT copying app-omlx-app (PyObjC layer — replaced by Swift)

# Step 3: Copy omlx Python package into Resources
rm -rf "$XCODE_RESOURCES/omlx"
cp -R "$REPO_ROOT/backend/omlx" "$XCODE_RESOURCES/omlx"

# Step 4: Copy our start_server.sh
cp "$REPO_ROOT/backend/start_server.sh" "$XCODE_RESOURCES/start_server.sh"
chmod +x "$XCODE_RESOURCES/start_server.sh"

echo "Bundle ready. Sizes:"
du -sh "$XCODE_FRAMEWORKS/cpython-3.11"
du -sh "$XCODE_FRAMEWORKS/framework-mlx-framework"
du -sh "$XCODE_RESOURCES/omlx"
```

**Prerequisites on the build machine:**
```bash
pip install pipx
pipx install venvstacks
# Python 3.11 must be available for building sdist wheels
brew install python@3.11
```

**`.gitignore` additions** (generated artifacts, never commit):
```
TxemAI-MLX/Frameworks/cpython-3.11/
TxemAI-MLX/Frameworks/framework-mlx-framework/
TxemAI-MLX/Resources/omlx/
backend/packaging/_build/
backend/packaging/_export/
backend/packaging/_wheels/
backend/packaging/dist/
backend/packaging/requirements/
```

---

### TASK 3 — `start_server.sh` `(~1 h)`

Create `backend/start_server.sh`. This is our only customization inside `backend/`.
It sets the correct `PYTHONHOME` / `PYTHONPATH` for the venvstacks layer layout and
invokes the oMLX CLI entry point.

```bash
#!/bin/bash
# backend/start_server.sh
# TxemAI-MLX server launcher — called by ServerManager.swift via Process().
# Environment variables injected by ServerManager:
#   TXEMAI_MODEL_DIR  — path to model directory (default: ~/.omlx)
#   TXEMAI_PORT       — port number (default: 8000)
#   TXEMAI_API_KEY    — API key (from Keychain in embedded mode)

set -euo pipefail

# Resolve bundle layout.
# In the app bundle: script is at Contents/Resources/start_server.sh
# Frameworks/ is at Contents/Frameworks/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENTS_DIR="$(dirname "$SCRIPT_DIR")"
LAYERS_DIR="$CONTENTS_DIR/Frameworks"

# Validate required directories
if [ ! -d "$LAYERS_DIR/cpython-3.11" ]; then
    echo "ERROR: Python runtime not found at $LAYERS_DIR/cpython-3.11" >&2
    exit 1
fi

PYTHON="$LAYERS_DIR/cpython-3.11/bin/python3"
OMLX_PKG="$SCRIPT_DIR/omlx"

export PYTHONHOME="$LAYERS_DIR/cpython-3.11"
export PYTHONPATH="$CONTENTS_DIR/Resources:$LAYERS_DIR/framework-mlx-framework/lib/python3.11/site-packages"
export PYTHONDONTWRITEBYTECODE=1

MODEL_DIR="${TXEMAI_MODEL_DIR:-$HOME/.omlx}"
PORT="${TXEMAI_PORT:-8000}"
API_KEY="${TXEMAI_API_KEY:-}"

# Build CLI args
ARGS=(--base-path "$MODEL_DIR" --port "$PORT")
if [ -n "$API_KEY" ]; then
    ARGS+=(--api-key "$API_KEY")
fi

# exec replaces the shell so Process.terminate() sends SIGTERM to python3 directly
exec "$PYTHON" -m omlx.cli serve "${ARGS[@]}"
```

Key decisions:
- Uses `python3 -m omlx.cli serve` — the exact entry point from `backend/omlx/cli.py`.
- `--base-path` controls where settings.json and logs land (default `~/.omlx/`).
- `exec` is critical — without it, SIGTERM from `Process.terminate()` hits bash, not Python.
- No `--model-dir` flag: oMLX 's `--base-path` implies models are at `{base_path}/models/`.
  Check `backend/omlx/cli.py` `serve_command()` to confirm before implementing.

---

### TASK 4 — Verify exact CLI entry point `(~30 min)`

Read `backend/omlx/cli.py` carefully and confirm:

1. The correct subcommand: `python3 -m omlx.cli serve` (confirmed — `serve_command()` exists)
2. The `--base-path` flag sets the model directory root (`settings.base_path`)
3. Startup completion signal: cli.py prints
   `"Starting server at http://{host}:{port}"` just before calling `uvicorn.run()`
   → `ServerManager` detects this line in stdout to transition `starting → running`
4. Whether `--api-key` is a valid CLI flag or must go through `settings.json`

If `--api-key` is not a direct CLI arg, write it to
`{base_path}/settings.json` before launching instead.

---

### TASK 5 — `ServerManager.swift` `(~2 h)`

New `@MainActor` class that manages the Python process lifecycle.

```swift
@MainActor
final class ServerManager: ObservableObject {
    enum State: Equatable {
        case stopped
        case extracting(progress: Double)
        case starting
        case running
        case error(String)
    }

    @Published var state: State = .stopped
    static let shared = ServerManager()

    private var process: Process?
    private var outputPipe: Pipe?
    private var monitorTask: Task<Void, Never>?

    func start(basePath: URL, port: Int, apiKey: String) async
    func stop() async          // SIGTERM → wait 5s → SIGKILL
    func restart(basePath: URL, port: Int, apiKey: String) async
}
```

**Process launch:**
```swift
private func launchProcess(basePath: URL, port: Int, apiKey: String) throws {
    let process = Process()
    // Use start_server.sh from the extracted runtime directory
    let runtimeDir = BundleExtractor.runtimeDirectory()
    process.executableURL = runtimeDir.appendingPathComponent("Resources/start_server.sh")
    process.environment = ProcessInfo.processInfo.environment.merging([
        "TXEMAI_MODEL_DIR": basePath.path,
        "TXEMAI_PORT":      "\(port)",
        "TXEMAI_API_KEY":   apiKey,
    ]) { _, new in new }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError  = pipe
    outputPipe = pipe
    self.process = process
    try process.run()
}
```

**Startup detection** — read stdout line by line and look for the signal from `cli.py`:
```swift
// Transition starting → running when oMLX prints the startup line
if line.contains("Starting server at http://") {
    state = .running
}
```

**Graceful shutdown:**
```swift
func stop() async {
    guard let process, process.isRunning else { state = .stopped; return }
    process.terminate()   // SIGTERM — triggers oMLX cleanup
    // Wait up to 5s for graceful shutdown, then force-kill
    let deadline = Date().addingTimeInterval(5)
    while process.isRunning && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(100))
    }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    state = .stopped
}
```

---

### TASK 6 — `APIClient` dynamic base URL `(~30 min)`

Add a method so `ServerStateViewModel` can update the host/port when the user changes
settings or when embedded mode boots on a different port:

```swift
// In APIClient.swift
func updateBaseURL(host: String, port: Int) {
    // Replace baseURL — safe because all calls use self.baseURL at call time
    // Note: requires making baseURL a var (currently let)
}
```

In `ServerStateViewModel.embedded` mode, call `updateBaseURL(host: "127.0.0.1", port: port)`
after `ServerManager.state` transitions to `.running` before the first `login()`.

---

### TASK 7 — `SetupView.swift` + `BundleExtractor.swift` `(~1 h)`

**`BundleExtractor`** copies the Frameworks and Resources from the `.app` bundle to
`~/Library/Application Support/TxemAI-MLX/runtime/` on first launch or app update.

```swift
struct BundleExtractor {
    // Destination: ~/Library/Application Support/TxemAI-MLX/runtime/
    static func runtimeDirectory() -> URL
    static var needsExtraction: Bool   // compare bundle version stamp vs installed
    // Atomic copy: write to a temp dir, then rename to final path
    // Never write directly to the destination to avoid half-extracted state
    static func extract(progress: @escaping (Double) -> Void) async throws
}
```

**Atomic extraction pattern** — never write directly to the final destination:
```swift
let tmp = runtimeDirectory().deletingLastPathComponent()
    .appendingPathComponent("runtime.tmp")
// ... copy files to tmp ...
try FileManager.default.moveItem(at: tmp, to: runtimeDirectory())
```

**`SetupView`** is shown as a `.fullScreenCover` over `ContentView` when
`BundleExtractor.needsExtraction == true`. No cancel button — the runtime is required.

---

### TASK 8 — `ServerStateViewModel` dual mode `(~1 h)`

```swift
// In ServerStateViewModel
enum BackendMode { case external, embedded }

// Detection: embedded if the Frameworks bundle exists inside the app
static var backendMode: BackendMode {
    Bundle.main.url(forResource: "start_server", withExtension: "sh") != nil
        ? .embedded : .external
}
```

**`external` mode** (current behavior): connect to whatever is at localhost:8000.  
**`embedded` mode**: `startServer()` → `ServerManager.shared.start(...)`;
the API key is read from Keychain instead of `UserDefaults`.

In `GlobalSettingsView`, expose a **"Server Mode"** toggle (embedded / external) for
power users who want to run their own oMLX instance and just use the TxemAI frontend.

---

### TASK 9 — Xcode configuration `(~1 h)`

**Entitlements** (`TxemAI-MLX.entitlements`):
```xml
<!-- mlx loads Metal shaders via dlopen at runtime -->
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
<!-- venvstacks layers contain unsigned .so dylibs -->
<key>com.apple.security.cs.disable-library-validation</key><true/>
<!-- embedded server listens on 127.0.0.1 -->
<key>com.apple.security.network.server</key><true/>
```

**Build phases** — add before "Compile Sources":
```
Run Script: bash "$SRCROOT/scripts/build_server_bundle.sh"
Input files:  $(SRCROOT)/backend/packaging/venvstacks.toml
Output files: $(SRCROOT)/TxemAI-MLX/Frameworks/cpython-3.11/.venvstacks
              $(SRCROOT)/TxemAI-MLX/Frameworks/framework-mlx-framework/.venvstacks
```
Using input/output file declarations allows Xcode to skip the script when nothing changed.

**Copy Bundle Resources** — add as folder references (blue icon, not group):
- `TxemAI-MLX/Frameworks/cpython-3.11/`
- `TxemAI-MLX/Frameworks/framework-mlx-framework/`
- `TxemAI-MLX/Resources/omlx/`
- `TxemAI-MLX/Resources/start_server.sh`

**Build setting:** `ARCHS = arm64` (mlx has no x86_64 wheels — enforces single-arch binary).

---

### TASK 10 — Integration testing checklist `(~2 h)`

- [ ] Clean install on a machine that has never had oMLX or Python
- [ ] App launches, `SetupView` appears with progress, extraction completes
- [ ] Server starts, `ServerManager.state == .running`, dashboard shows connected
- [ ] `ModelSidebarView` lists models from `~/.omlx/models/`
- [ ] Load / unload a model
- [ ] Chat with a loaded model, streaming works end-to-end
- [ ] Text file attachment (`.swift`)
- [ ] Image attachment to a VLM model (`.jpg`)
- [ ] HF downloader: search + download a small model (~1 GB)
- [ ] Benchmark: PP1024/TG128 SSE stream works
- [ ] GlobalSettingsView: change port → server restarts on new port → reconnect
- [ ] App quit: server shuts down gracefully (SIGTERM, not SIGKILL)
- [ ] App relaunch: no re-extraction (`BundleExtractor.needsExtraction == false`)
- [ ] Version bump (`CFBundleShortVersionString`): relaunch triggers re-extraction
- [ ] Instruments: no memory leaks after 30 min with a loaded model

---

### TASK 11 — Distribution: codesign + notarize + DMG `(4 h+)`

```bash
# 1. Archive in Xcode (Product → Archive)
# 2. Export with Developer ID
xcodebuild -exportArchive \
    -archivePath TxemAI-MLX.xcarchive \
    -exportPath dist/ \
    -exportOptionsPlist ExportOptions.plist
# ExportOptions.plist: method=developer-id, hardened-runtime=true

# 3. Verify codesigning (all .so and .dylib must be signed)
codesign --verify --deep --strict --verbose=2 dist/TxemAI-MLX.app

# 4. Notarize
ditto -c -k --keepParent dist/TxemAI-MLX.app dist/TxemAI-MLX.app.zip
xcrun notarytool submit dist/TxemAI-MLX.app.zip \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" --wait

# 5. Staple + create DMG
xcrun stapler staple dist/TxemAI-MLX.app
create-dmg dist/TxemAI-MLX.dmg dist/TxemAI-MLX.app
```

**Codesigning the Python `.so` files** — venvstacks `.so` dylibs are unsigned.
All of them must be signed with the Developer ID certificate before notarization:
```bash
find dist/TxemAI-MLX.app -name "*.so" -o -name "*.dylib" | while read f; do
    codesign --force --sign "Developer ID Application: ..." \
             --options runtime "$f"
done
```
oMLX's own `build.py` handles this for their DMG — study that code for the exact
`codesign` flags before implementing here.

---

## Important Notes

- **Python 3.11 ARM64 only.** Confirmed in `venvstacks.toml`:
  `python_implementation = "cpython@3.11.10"`, `platforms = ["macosx_arm64"]`.
  Set `ARCHS = arm64` in Xcode. There are no x86_64 mlx wheels.

- **Models in `~/.omlx/` — maintain compatibility.** Users who ran standalone oMLX
  keep their downloaded models. Default `--base-path $HOME/.omlx` achieves this.

- **No C launcher needed.** oMLX's `_create_c_launcher()` exists because their app is
  `LSUIElement=True` (menu bar only) and requires a Mach-O CFBundleExecutable for
  WindowServer access. TxemAI's CFBundleExecutable is the Swift binary — `Process()`
  handles the python3 subprocess without any trampoline.

- **mlx-embeddings already in the bundle.** `venvstacks.toml` includes
  `mlx-embeddings @ git+...` in `framework-mlx-framework`. Phase 6 RAG (semantic search
  over chat history / local docs) requires zero additional packaging work.

- **mlx-audio is also in the bundle.** Included via `_install_mlx_audio()` in `build.py`
  (separate git install due to version conflict with mlx-lm). Future audio input/output
  features are available without bundle changes.

- **Estimated bundle size: ~800 MB – 1.2 GB** after `_strip_unused_packages()` removes
  torch (~780 MB), sympy, cv2, pyarrow, pandas, datasets. The stripping is already
  implemented in oMLX's `build.py` — it runs automatically as part of the venvstacks build.

- **mlx wheel platform targeting.** `build.py`'s `swap_platform_wheels()` can replace
  mlx/mlx-metal with macOS 26 wheels (M5 Neural Accelerator matmul kernels) even when
  building on macOS 15. Set `--macos-target 26.0` when running `build_server_bundle.sh`
  on macOS 26 target machines.
