#!/usr/bin/env python3
"""CortexML Voice Server launcher."""
import sys
import os

# ── Path setup ────────────────────────────────────────────────────────────────
_this_file = os.path.abspath(__file__)
_voice_server_dir = os.path.dirname(_this_file)
_repo_root = os.path.dirname(_voice_server_dir)

# Añadir repo root
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

# Añadir el bundle framework layer si existe (dev mode con oMLX bundle)
_bundle_framework = os.path.join(
    _repo_root,
    "backend/packaging/dist/oMLX.app/Contents/Frameworks"
    "/framework-mlx-framework/lib/python3.11/site-packages"
)
if os.path.isdir(_bundle_framework) and _bundle_framework not in sys.path:
    sys.path.insert(1, _bundle_framework)

_bundle_resources = os.path.join(
    _repo_root,
    "backend/packaging/dist/oMLX.app/Contents/Resources"
)
if os.path.isdir(_bundle_resources) and _bundle_resources not in sys.path:
    sys.path.insert(2, _bundle_resources)

# ── Registrar voice_server como módulo (el dir tiene guión, no guión bajo) ───
import importlib.util
_vs_dir = os.path.join(_repo_root, "voice-server")
if "voice_server" not in sys.modules and os.path.isdir(_vs_dir):
    spec = importlib.util.spec_from_file_location(
        "voice_server",
        os.path.join(_vs_dir, "__init__.py"),
        submodule_search_locations=[_vs_dir]
    )
    if spec:
        module = importlib.util.module_from_spec(spec)
        sys.modules["voice_server"] = module
        spec.loader.exec_module(module)

# ── Importar y arrancar ───────────────────────────────────────────────────────
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, default=17493)
parser.add_argument("--data-dir", default=os.path.expanduser("~/.cortexML/voice"))
args = parser.parse_args()

# Importar después del path setup
from voice_server.app import app, set_data_dir
import uvicorn

set_data_dir(args.data_dir)
print(f"CortexML Voice Server starting on {args.host}:{args.port}")
print(f"Data dir: {args.data_dir}")

uvicorn.run(app, host=args.host, port=args.port, log_level="info")
