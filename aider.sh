#!/bin/bash

# Configuración de conexión con LM Studio
export OPENAI_API_BASE="http://localhost:1234/v1"
export OPENAI_API_KEY="not-needed"

# Lanzamiento de Aider
# --architect: para que piense antes de actuar
# --map-tokens: ajustado para no saturar el contexto del modelo local
aider --model openai/qwen3-coder-next \
      --architect \
      --map-tokens 1024 \
      --auto-test \
      "$@"