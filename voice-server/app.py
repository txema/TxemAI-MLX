"""
CortexML Voice Server
Microservidor FastAPI para TTS y STT usando mlx-audio.
Sin torch — usa el bundle Python de oMLX.

TTS: Qwen3-TTS via mlx-audio
STT: Whisper via mlx_whisper

Arranque via run_server.py
"""

import asyncio
import io
import json
import logging
import os
import tempfile
import time
import uuid
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

# ── Data directory ────────────────────────────────────────────────────────────

_data_dir = Path.home() / ".cortexML" / "voice"

def set_data_dir(path: str):
    global _data_dir
    _data_dir = Path(path)
    _data_dir.mkdir(parents=True, exist_ok=True)
    profiles_dir().mkdir(parents=True, exist_ok=True)
    audio_dir().mkdir(parents=True, exist_ok=True)

def profiles_dir() -> Path:
    return _data_dir / "profiles"

def audio_dir() -> Path:
    return _data_dir / "audio"

# ── Model repos ───────────────────────────────────────────────────────────────

QWEN_TTS_REPOS = {
    "0.6B": "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
    "1.7B": "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
    "1.7B-voice": "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit",
}

# Voces disponibles en CustomVoice 0.6B y 1.7B
QWEN_TTS_VOICES_CUSTOM = [
    "serena", "vivian", "uncle_fu", "ryan",
    "aiden", "ono_anna", "sohee", "eric", "dylan",
]

# Voces disponibles en VoiceDesign 1.7B (descritas por texto)
QWEN_TTS_VOICES = QWEN_TTS_VOICES_CUSTOM  # default

AVAILABLE_MODELS = [
    {
        "model_name": "qwen3-tts-0.6b",
        "display_name": "Qwen3-TTS 0.6B CustomVoice (Fast, 8bit)",
        "hf_repo_id": "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
        "type": "tts",
        "size_mb": 800,
    },
    {
        "model_name": "qwen3-tts-1.7b",
        "display_name": "Qwen3-TTS 1.7B CustomVoice (High Quality, 8bit)",
        "hf_repo_id": "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
        "type": "tts",
        "size_mb": 1800,
    },
    {
        "model_name": "qwen3-tts-1.7b-voice",
        "display_name": "Qwen3-TTS 1.7B VoiceDesign (Voice Cloning, 8bit)",
        "hf_repo_id": "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit",
        "type": "tts",
        "size_mb": 1800,
    },
    {
        "model_name": "whisper-tiny",
        "display_name": "Whisper Tiny (Fast STT)",
        "hf_repo_id": "mlx-community/whisper-tiny-mlx",
        "type": "stt",
        "size_mb": 75,
    },
    {
        "model_name": "whisper-base",
        "display_name": "Whisper Base (STT)",
        "hf_repo_id": "mlx-community/whisper-base-mlx",
        "type": "stt",
        "size_mb": 145,
    },
    {
        "model_name": "whisper-large-v3-turbo",
        "display_name": "Whisper Large v3 Turbo (Best STT)",
        "hf_repo_id": "mlx-community/whisper-large-v3-turbo-asr-fp16",
        "type": "stt",
        "size_mb": 1550,
    },
]

# ── Download management ───────────────────────────────────────────────────────

_downloads: dict[str, dict] = {}  # {model_name: {"status": ..., "progress": float, ...}}

def _start_download(model_name: str) -> str:
    """Inicia descarga en background y devuelve download_id."""
    download_id = str(uuid.uuid4())
    
    # Guardar estado inicial
    _downloads[model_name] = {
        "download_id": download_id,
        "status": "started",
        "progress": 0.0,
    }

    async def _download_task():
        try:
            repo_id = None
            for m in AVAILABLE_MODELS:
                if m["model_name"] == model_name:
                    repo_id = m["hf_repo_id"]
                    break
            if not repo_id:
                raise ValueError(f"Model {model_name} not found in AVAILABLE_MODELS")

            from huggingface_hub import constants as hf_constants
            cache_dir = Path(hf_constants.HF_HUB_CACHE)

            # Descargar con callback de progreso
            def _progress_hook(current: int, total: int):
                progress = current / total if total > 0 else 1.0
                _downloads[model_name]["progress"] = progress
                if current == total:
                    _downloads[model_name]["status"] = "completed"
                    _downloads[model_name]["progress"] = 1.0

            from huggingface_hub import snapshot_download
            snapshot_download(
                repo_id=repo_id,
                cache_dir=str(cache_dir),
                max_workers=1,  # para controlar progreso
            )
        except Exception as e:
            _downloads[model_name]["status"] = "failed"
            _downloads[model_name]["error"] = str(e)
        finally:
            # Limpiar si falló o completado
            if _downloads[model_name]["status"] in ("completed", "failed"):
                del _downloads[model_name]

    # Ejecutar en background
    asyncio.create_task(_download_task())
    
    return download_id

# ── Lazy model cache ──────────────────────────────────────────────────────────

_tts_model = None
_tts_model_size = None

def _is_model_downloaded(model_name: str) -> bool:
    """Verifica si un modelo está descargado en la caché HuggingFace."""
    from huggingface_hub import constants as hf_constants
    cache_dir = Path(hf_constants.HF_HUB_CACHE)

    hf_repo_id = None
    for m in AVAILABLE_MODELS:
        if m["model_name"] == model_name:
            hf_repo_id = m["hf_repo_id"]
            break

    if not hf_repo_id:
        return False

    repo_dir = cache_dir / ("models--" + hf_repo_id.replace("/", "--"))
    return repo_dir.exists() and any(repo_dir.rglob("*.safetensors"))

def _model_name_for_size(model_size: str) -> str:
    """Devuelve el model_name de AVAILABLE_MODELS para un model_size dado."""
    size_to_name = {
        "0.6B": "qwen3-tts-0.6b",
        "1.7B": "qwen3-tts-1.7b",
        "1.7B-voice": "qwen3-tts-1.7b-voice",
    }
    return size_to_name.get(model_size, "qwen3-tts-1.7b")

def get_tts_model(model_size: str = "1.7B"):
    global _tts_model, _tts_model_size
    if _tts_model is None or _tts_model_size != model_size:
        model_name = _model_name_for_size(model_size)
        if not _is_model_downloaded(model_name):
            raise HTTPException(
                status_code=428,
                detail=f"Model {model_name} not downloaded. Please download it first from Voice Studio → Models."
            )
            
        logger.info(f"Loading Qwen3-TTS {model_size}...")
        from mlx_audio.tts.utils import load_model
        _tts_model = load_model(repo_id)
        _tts_model_size = model_size
        logger.info(f"Qwen3-TTS {model_size} loaded. sample_rate={_tts_model.sample_rate}")
    return _tts_model

# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(title="CortexML Voice Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/models/{name}/download")
async def download_model(name: str):
    """Inicia descarga de un modelo en background."""
    # Validar que el modelo existe
    model_info = next((m for m in AVAILABLE_MODELS if m["model_name"] == name), None)
    if not model_info:
        raise HTTPException(status_code=404, detail=f"Model '{name}' not found")

    # Si ya está descargado, no hacer nada
    if _is_model_downloaded(name):
        return {"status": "already_downloaded", "download_id": None}

    # Si ya hay descarga en curso, devolver su ID
    if name in _downloads and _downloads[name]["status"] == "started":
        return {"status": "already_downloading", "download_id": _downloads[name]["download_id"]}

    # Iniciar descarga
    download_id = _start_download(name)
    return {"status": "started", "download_id": download_id}

@app.get("/models/{name}/download/progress")
async def download_progress(name: str):
    """Devuelve progreso de descarga en tiempo real (SSE)."""
    if name not in _downloads:
        # Si no hay descarga activa, devolver estado final
        if _is_model_downloaded(name):
            async def already_done():
                yield "data: {\"status\": \"completed\", \"progress\": 1.0}\n\n"
            return StreamingResponse(already_done(), media_type="text/event-stream")
        else:
            raise HTTPException(status_code=404, detail="No active download for this model")

    async def progress_stream():
        while True:
            status = _downloads.get(name)
            if not status:
                # Descarga terminada o fallida (limpiado en _start_download)
                break
            if status["status"] == "completed":
                yield f"data: {{\"download_id\": \"{status['download_id']}\", \"status\": \"completed\", \"progress\": 1.0}}\n\n"
                break
            elif status["status"] == "failed":
                yield f"data: {{\"download_id\": \"{status['download_id']}\", \"status\": \"failed\", \"error\": \"{status.get('error', 'Unknown error')}\"}}\n\n"
                break
            else:
                yield f"data: {{\"download_id\": \"{status['download_id']}\", \"status\": \"downloading\", \"progress\": {status['progress']:.4f}}}\n\n"
            await asyncio.sleep(0.5)  # Actualizar cada 500ms

    return StreamingResponse(progress_stream(), media_type="text/event-stream")

@app.on_event("startup")
async def startup():
    set_data_dir(str(_data_dir))
    logger.info(f"Voice server ready. Data dir: {_data_dir}")

# ── Pydantic models ───────────────────────────────────────────────────────────

class VoiceProfile(BaseModel):
    id: str
    name: str
    language: str = "en"
    engine: str = "qwen"
    model_size: str = "1.7B"
    voice: str = "serena"         # voz builtin de Qwen3-TTS CustomVoice
    effects_chain: list = []
    ref_audio_path: Optional[str] = None
    ref_text: Optional[str] = None

class ProfileCreate(BaseModel):
    name: str
    language: str = "en"
    engine: str = "qwen"
    model_size: str = "1.7B"
    voice: str = "serena"

class GenerateRequest(BaseModel):
    text: str
    profile_id: str
    language: str = "en"
    model_size: str = "1.7B"
    speed: float = 1.0
    effects_chain: list = []

class EffectsUpdate(BaseModel):
    effects_chain: list

# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "engine": "mlx-audio"}

# ── Profiles ──────────────────────────────────────────────────────────────────

def _profile_path(profile_id: str) -> Path:
    return profiles_dir() / f"{profile_id}.json"

def _load_profile(profile_id: str) -> VoiceProfile:
    path = _profile_path(profile_id)
    if not path.exists():
        raise HTTPException(404, f"Profile {profile_id} not found")
    return VoiceProfile(**json.loads(path.read_text()))

def _save_profile(profile: VoiceProfile):
    profiles_dir().mkdir(parents=True, exist_ok=True)
    _profile_path(profile.id).write_text(profile.model_dump_json(indent=2))

@app.get("/profiles")
async def list_profiles() -> list[VoiceProfile]:
    result = []
    for p in profiles_dir().glob("*.json"):
        try:
            result.append(VoiceProfile(**json.loads(p.read_text())))
        except Exception:
            pass
    return result

@app.post("/profiles", status_code=201)
async def create_profile(data: ProfileCreate) -> VoiceProfile:
    profile = VoiceProfile(
        id=str(uuid.uuid4()),
        name=data.name,
        language=data.language,
        engine=data.engine,
        model_size=data.model_size,
        voice=data.voice,
    )
    _save_profile(profile)
    return profile

@app.get("/profiles/{profile_id}")
async def get_profile(profile_id: str) -> VoiceProfile:
    return _load_profile(profile_id)

@app.delete("/profiles/{profile_id}")
async def delete_profile(profile_id: str):
    path = _profile_path(profile_id)
    if not path.exists():
        raise HTTPException(404, "Profile not found")
    path.unlink()
    return {"message": "Deleted"}

@app.put("/profiles/{profile_id}/effects")
async def update_effects(profile_id: str, data: EffectsUpdate) -> VoiceProfile:
    profile = _load_profile(profile_id)
    profile.effects_chain = data.effects_chain
    _save_profile(profile)
    return profile

@app.post("/profiles/{profile_id}/sample")
async def upload_sample(
    profile_id: str,
    file: UploadFile = File(...),
    reference_text: str = Form(""),
):
    """Upload reference audio for voice cloning."""
    profile = _load_profile(profile_id)
    sample_dir = profiles_dir() / profile_id
    sample_dir.mkdir(exist_ok=True)

    suffix = Path(file.filename or "sample.wav").suffix or ".wav"
    sample_path = sample_dir / f"ref{suffix}"
    sample_path.write_bytes(await file.read())

    profile.ref_audio_path = str(sample_path)
    profile.ref_text = reference_text
    _save_profile(profile)
    return profile

# ── TTS Generation ────────────────────────────────────────────────────────────

@app.post("/generate/stream")
async def generate_stream(data: GenerateRequest):
    """Generate speech and return WAV audio."""
    profile = _load_profile(data.profile_id)

    try:
        model = get_tts_model(profile.model_size)
        sample_rate = model.sample_rate

        import numpy as np
        import soundfile as sf

        # Parámetros de generación
        gen_kwargs = dict(
            text=data.text,
            lang_code=data.language,
            speed=data.speed,
            stream=False,
            verbose=False,
        )

        # Voz: usar ref_audio (clonación) o voz builtin
        if profile.ref_audio_path and Path(profile.ref_audio_path).exists():
            gen_kwargs["ref_audio"] = profile.ref_audio_path
            if profile.ref_text:
                gen_kwargs["ref_text"] = profile.ref_text
        else:
            gen_kwargs["voice"] = profile.voice

        logger.info(f"Generating TTS: '{data.text[:60]}' voice={gen_kwargs.get('voice', 'cloned')}")

        audio_chunks = []
        for result in model.generate(**gen_kwargs):
            audio_chunks.append(np.array(result.audio))
            sample_rate = result.sample_rate

        if not audio_chunks:
            raise ValueError("No audio generated")

        audio = np.concatenate(audio_chunks) if len(audio_chunks) > 1 else audio_chunks[0]

        # WAV bytes
        buf = io.BytesIO()
        sf.write(buf, audio, sample_rate, format="WAV")
        wav_bytes = buf.getvalue()

        logger.info(f"TTS done: {len(audio)/sample_rate:.1f}s audio, {len(wav_bytes)} bytes")

        return Response(
            content=wav_bytes,
            media_type="audio/wav",
            headers={"Content-Disposition": 'attachment; filename="speech.wav"'},
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"TTS generation failed: {e}")
        import traceback; traceback.print_exc()
        raise HTTPException(500, str(e))

# ── STT Transcription ─────────────────────────────────────────────────────────

@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: Optional[str] = Form(None),
    model: Optional[str] = Form("base"),
):
    """Transcribe audio to text using Whisper via mlx_whisper."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        import mlx_whisper

        model_map = {
            "tiny": "mlx-community/whisper-tiny-mlx",
            "base": "mlx-community/whisper-base-mlx",
            "small": "mlx-community/whisper-small-mlx",
            "large": "mlx-community/whisper-large-v3-turbo-asr-fp16",
        }
        model_path = model_map.get(model or "base", model_map["base"])

        result = mlx_whisper.transcribe(
            tmp_path,
            path_or_hf_repo=model_path,
            language=language,
        )
        text = result.get("text", "").strip()
        return {"text": text, "duration": 0.0}

    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(500, str(e))
    finally:
        Path(tmp_path).unlink(missing_ok=True)

# ── Model status ──────────────────────────────────────────────────────────────

@app.get("/models/status")
async def model_status():
    from huggingface_hub import constants as hf_constants
    cache_dir = Path(hf_constants.HF_HUB_CACHE)

    result = []
    for m in AVAILABLE_MODELS:
        repo_dir = cache_dir / ("models--" + m["hf_repo_id"].replace("/", "--"))
        downloaded = repo_dir.exists() and any(repo_dir.rglob("*.safetensors"))
        loaded = (
            (_tts_model is not None and m["type"] == "tts" and _tts_model_size in m["model_name"]) or
            (m["type"] == "stt" and False)  # STT se carga on-demand
        )
        result.append({**m, "downloaded": downloaded, "loaded": loaded, "downloading": False})
    return {"models": result}

# ── Voices list ───────────────────────────────────────────────────────────────

@app.get("/voices")
async def list_voices():
    """List available builtin voices for Qwen3-TTS."""
    return {
        "voices": [
            {"id": v, "name": v, "engine": "qwen3-tts"}
            for v in QWEN_TTS_VOICES
        ]
    }

# ── Effects ───────────────────────────────────────────────────────────────────

@app.get("/effects/available")
async def available_effects():
    return {
        "effects": [
            {"type": "reverb", "name": "Reverb", "params": {"room_size": {"min": 0.0, "max": 1.0, "default": 0.3}}},
            {"type": "chorus", "name": "Chorus", "params": {}},
            {"type": "compressor", "name": "Compressor", "params": {}},
        ]
    }
