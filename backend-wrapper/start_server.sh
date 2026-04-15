#!/bin/bash
# Server-only launcher for TxemAI MLX embedded backend.
# Called by Swift ServerManager via Process().
# Starts oMLX inference server WITHOUT the PyObjC menu bar app.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENTS_DIR="$(dirname "$SCRIPT_DIR")"

# Dev mode: si no hay Frameworks/ en Contents/, usar el bundle de desarrollo
if [ ! -d "$CONTENTS_DIR/Frameworks" ]; then
    DEV_BUNDLE="$(dirname "$SCRIPT_DIR")/backend-wrapper/oMLX-bundle.app/Contents"
    if [ -d "$DEV_BUNDLE/Frameworks" ]; then
        CONTENTS_DIR="$DEV_BUNDLE"
        LAYERS_DIR="$CONTENTS_DIR/Frameworks"
        PYTHON_BIN="$CONTENTS_DIR/MacOS/python3"
    fi
fi

LAYERS_DIR="$CONTENTS_DIR/Frameworks"
PYTHON_BIN="$CONTENTS_DIR/MacOS/python3"

# Si no existe el python embebido (dev mode), usar python del sistema
if [ ! -f "$PYTHON_BIN" ]; then
    PYTHON_BIN="$(which python3)"
    LAYERS_DIR=""
fi

if [ -n "$LAYERS_DIR" ]; then
    export PYTHONHOME="$LAYERS_DIR/cpython-3.11"
    export PYTHONPATH="$CONTENTS_DIR/Resources:$LAYERS_DIR/framework-mlx-framework/lib/python3.11/site-packages"
fi

export PYTHONDONTWRITEBYTECODE=1
export OMLX_PORT="${OMLX_PORT:-8000}"
export OMLX_BASE_PATH="${OMLX_BASE_PATH:-$HOME/.omlx}"
MODEL_DIR="${OMLX_MODEL_DIR:-$HOME/.omlx/models}"

cd "$CONTENTS_DIR/Resources"
exec "$PYTHON_BIN" -m omlx.cli serve \
    --port "$OMLX_PORT" \
    --base-path "$OMLX_BASE_PATH" \
    --model-dir "$MODEL_DIR" \
    --log-level info \
    ${OMLX_API_KEY:+--api-key "$OMLX_API_KEY"}
