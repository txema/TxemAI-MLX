"""
CortexML Voice Server
Microservidor FastAPI para TTS y STT usando mlx-audio.
Sin torch, sin dependencias extra — usa el bundle Python de oMLX.

Engines soportados:
- TTS: Qwen3-TTS (0.6B, 1.7B) via mlx-audio — alta calidad, Apple Silicon nativo
- STT: Whisper (tiny, base, small, medium, large) via mlx-audio

Arranque:
  python -m voice_server.main --port 17493 --data-dir ~/.cortexML/voice
"""

import argparse
import uvicorn
from .app import app, set_data_dir

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CortexML Voice Server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=17493)
    parser.add_argument("--data-dir", default=None)
    args = parser.parse_args()

    if args.data_dir:
        set_data_dir(args.data_dir)

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level="info",
    )
