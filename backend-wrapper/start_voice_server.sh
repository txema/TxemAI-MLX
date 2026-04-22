#!/bin/bash
# Arranca el voicebox FastAPI backend (TTS/STT)
# Puerto: 17493 (distinto de oMLX en 8000)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENTS_DIR="$(dirname "$SCRIPT_DIR")"
LAYERS_DIR="$CONTENTS_DIR/Frameworks"
PYTHON_BIN="$CONTENTS_DIR/MacOS/python3"

# Dev mode: usar Python del sistema si no hay bundle
if [ ! -f "$PYTHON_BIN" ]; then
    PYTHON_BIN="$(which python3)"
    LAYERS_DIR=""
fi

if [ -n "$LAYERS_DIR" ]; then
    export PYTHONHOME="$LAYERS_DIR/cpython-3.11"
    export PYTHONPATH="$CONTENTS_DIR/Resources:$LAYERS_DIR/framework-mlx-framework/lib/python3.11/site-packages"
fi

export PYTHONDONTWRITEBYTECODE=1
PORT="${VOICE_PORT:-17493}"
DATA_DIR="${VOICE_DATA_DIR:-$HOME/.cortexML/voice}"

# El módulo se llama "voicebox-backend" pero Python no acepta guiones
# Copiamos como "voicebox_backend" o arrancamos desde el directorio
cd "$CONTENTS_DIR/Resources"
exec "$PYTHON_BIN" -m voicebox_backend.main \
    --host 127.0.0.1 \
    --port "$PORT" \
    --data-dir "$DATA_DIR"
