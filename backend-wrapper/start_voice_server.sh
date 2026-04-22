#!/bin/bash
# start_voice_server.sh — CortexML Voice Server (TTS + STT via mlx-audio)
# Puerto: 17493

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RUNNER="$REPO_ROOT/voice-server/run_server.py"

# Python del bundle de oMLX (dev mode)
BUNDLE_DIR="$REPO_ROOT/backend/packaging/dist/oMLX.app/Contents"
BUNDLE_PYTHON="$BUNDLE_DIR/MacOS/python3"
BUNDLE_FRAMEWORKS="$BUNDLE_DIR/Frameworks"

if [ -f "$BUNDLE_PYTHON" ]; then
    PYTHON_BIN="$BUNDLE_PYTHON"
    export PYTHONHOME="$BUNDLE_FRAMEWORKS/cpython-3.11"
else
    PYTHON_BIN="$(which python3)"
fi

export PYTHONDONTWRITEBYTECODE=1
PORT="${VOICE_PORT:-17493}"
DATA_DIR="${VOICE_DATA_DIR:-$HOME/.cortexML/voice}"
mkdir -p "$DATA_DIR"

echo "Starting CortexML Voice Server on port $PORT..."
echo "Python: $PYTHON_BIN"
echo "Data dir: $DATA_DIR"

# Llamar directamente al script Python (no via -m)
# run_server.py inserta el REPO_ROOT en sys.path manualmente
exec "$PYTHON_BIN" "$RUNNER" \
    --host 127.0.0.1 \
    --port "$PORT" \
    --data-dir "$DATA_DIR"
