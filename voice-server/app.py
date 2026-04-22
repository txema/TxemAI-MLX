"""
CortexML Voice Server — FastAPI app
"""

import io
import json
import logging
import os
import tempfile
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
    (profiles_dir()).mkdir(parents=True, exist_ok=True)
    (audio_dir()).mkdir(parents=True, exist_ok=True)

def profiles_dir() -> Path:
    return _data_dir / "profiles"

def audio_dir() -> Path:
    return _data_dir / "audio"

# ── Lazy model cache ──────────────────────────────────────────────────────────

_tts_model = None
_tts_model_size = None
_stt_model = None
_stt_model_size = None

def get_tts_model(model_size: str = "1.7B"):
    global _tts_model, _tts_model_size
    if _tts_model is None or _tts_model_size != model_size:
        logger.info(f"Loading Qwen3-TTS {model_size}...")
        from mlx_audio.tts.models.qwen import load as load_qwen
        _tts_model = load_qwen(model_size)
        _tts_model_size = model_size
        logger.info(f"Qwen3-TTS {model_size} loaded.")
    return _tts_model

def get_stt_model(model_size: str = "base"):
    global _stt_model, _stt_model_size
    if _stt_model is None or _stt_model_size != model_size:
        logger.info(f"Loading Whisper {model_size}...")
        from mlx_audio.stt.models.whisper import load as load_whisper
        _stt_model = load_whisper(model_size)
        _stt_model_size = model_size
        logger.info(f"Whisper {model_size} loaded.")
    return _stt_model

# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(title="CortexML Voice Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    set_data_dir(str(_data_dir))
    logger.info(f"Voice server data dir: {_data_dir}")

# ── Models ────────────────────────────────────────────────────────────────────

class VoiceProfile(BaseModel):
    id: str
    name: str
    language: str = "en"
    engine: str = "qwen"
    model_size: str = "1.7B"
    effects_chain: list = []
    ref_audio_path: Optional[str] = None
    ref_text: Optional[str] = None

class GenerateRequest(BaseModel):
    text: str
    profile_id: str
    language: str = "en"
    model_size: str = "1.7B"
    speed: float = 1.0
    effects_chain: list = []

class ProfileCreate(BaseModel):
    name: str
    language: str = "en"
    engine: str = "qwen"
    model_size: str = "1.7B"

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
    """Upload a reference audio sample for voice cloning."""
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
    """Generate speech and return WAV audio directly."""
    profile = _load_profile(data.profile_id)

    try:
        model = get_tts_model(profile.model_size)

        # Build voice prompt from reference audio if available
        voice_prompt = None
        if profile.ref_audio_path and Path(profile.ref_audio_path).exists():
            voice_prompt = profile.ref_audio_path

        import mlx.core as mx
        import numpy as np
        import soundfile as sf

        logger.info(f"Generating TTS: '{data.text[:50]}...' lang={data.language}")

        # Generate audio
        audio, sample_rate = model.generate(
            text=data.text,
            voice=voice_prompt,
            language=data.language,
            speed=data.speed,
        )

        # Convert to numpy if needed
        if hasattr(audio, 'tolist'):
            audio = np.array(audio)

        # Apply effects if any
        if data.effects_chain or profile.effects_chain:
            chain = data.effects_chain or profile.effects_chain
            audio = _apply_effects(audio, sample_rate, chain)

        # Write to WAV bytes
        buf = io.BytesIO()
        sf.write(buf, audio, sample_rate, format="WAV")
        wav_bytes = buf.getvalue()

        return Response(
            content=wav_bytes,
            media_type="audio/wav",
            headers={"Content-Disposition": 'attachment; filename="speech.wav"'},
        )

    except Exception as e:
        logger.error(f"TTS generation failed: {e}")
        raise HTTPException(500, str(e))

def _apply_effects(audio, sample_rate: int, effects_chain: list):
    """Apply audio effects chain."""
    try:
        import numpy as np
        from pedalboard import Pedalboard, Reverb, Chorus, Compressor, LowShelfFilter, HighShelfFilter
        import pedalboard

        board_effects = []
        for effect in effects_chain:
            etype = effect.get("type", "")
            params = effect.get("params", {})
            if etype == "reverb":
                board_effects.append(Reverb(room_size=params.get("room_size", 0.3)))
            elif etype == "chorus":
                board_effects.append(Chorus())
            elif etype == "compressor":
                board_effects.append(Compressor())

        if board_effects:
            board = Pedalboard(board_effects)
            audio = board(audio.astype(np.float32), sample_rate)
    except ImportError:
        pass  # pedalboard not available, skip effects
    except Exception as e:
        logger.warning(f"Effects failed: {e}")

    return audio

# ── STT Transcription ─────────────────────────────────────────────────────────

@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: Optional[str] = Form(None),
    model: Optional[str] = Form("base"),
):
    """Transcribe audio to text using Whisper via mlx-audio."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        stt = get_stt_model(model or "base")
        result = stt.transcribe(tmp_path, language=language)
        text = result.get("text", "").strip() if isinstance(result, dict) else str(result).strip()
        return {"text": text, "duration": 0.0}
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        raise HTTPException(500, str(e))
    finally:
        Path(tmp_path).unlink(missing_ok=True)

# ── Model status ──────────────────────────────────────────────────────────────

AVAILABLE_MODELS = [
    {
        "model_name": "qwen3-tts-0.6b",
        "display_name": "Qwen3-TTS 0.6B (Fast)",
        "hf_repo_id": "Qwen/Qwen3-TTS-0.6B",
        "type": "tts",
        "size_mb": 1200,
    },
    {
        "model_name": "qwen3-tts-1.7b",
        "display_name": "Qwen3-TTS 1.7B (High Quality)",
        "hf_repo_id": "Qwen/Qwen3-TTS-1.7B",
        "type": "tts",
        "size_mb": 3400,
    },
    {
        "model_name": "whisper-tiny",
        "display_name": "Whisper Tiny (Fast STT)",
        "hf_repo_id": "openai/whisper-tiny",
        "type": "stt",
        "size_mb": 75,
    },
    {
        "model_name": "whisper-base",
        "display_name": "Whisper Base (STT)",
        "hf_repo_id": "openai/whisper-base",
        "type": "stt",
        "size_mb": 145,
    },
    {
        "model_name": "whisper-small",
        "display_name": "Whisper Small (Better STT)",
        "hf_repo_id": "openai/whisper-small",
        "type": "stt",
        "size_mb": 460,
    },
    {
        "model_name": "whisper-large-v3-turbo",
        "display_name": "Whisper Large v3 Turbo (Best STT)",
        "hf_repo_id": "openai/whisper-large-v3-turbo",
        "type": "stt",
        "size_mb": 1550,
    },
]

@app.get("/models/status")
async def model_status():
    from huggingface_hub import constants as hf_constants
    cache_dir = Path(hf_constants.HF_HUB_CACHE)

    result = []
    for m in AVAILABLE_MODELS:
        repo_dir = cache_dir / ("models--" + m["hf_repo_id"].replace("/", "--"))
        downloaded = repo_dir.exists() and any(repo_dir.rglob("*.safetensors"))
        loaded = (
            (_tts_model is not None and m["type"] == "tts") or
            (_stt_model is not None and m["type"] == "stt")
        )
        result.append({
            **m,
            "downloaded": downloaded,
            "loaded": loaded,
            "downloading": False,
        })
    return {"models": result}

@app.get("/effects/available")
async def available_effects():
    """List available audio effects."""
    return {
        "effects": [
            {"type": "reverb", "name": "Reverb", "params": {"room_size": {"min": 0.0, "max": 1.0, "default": 0.3}}},
            {"type": "chorus", "name": "Chorus", "params": {}},
            {"type": "compressor", "name": "Compressor", "params": {}},
            {"type": "speed", "name": "Speed", "params": {"factor": {"min": 0.5, "max": 2.0, "default": 1.0}}},
        ]
    }
