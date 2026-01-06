#!/usr/bin/env bash
set -euo pipefail

# Wire shared storage safely
if [ -d /runpod-volume ]; then
  mkdir -p /runpod-volume/models
  mkdir -p /runpod-volume/loras

  # Link /comfyui/models -> /runpod-volume/models if not an existing non-symlink dir
  if [ -e /comfyui/models ] && [ ! -L /comfyui/models ]; then
    echo "Found existing /comfyui/models (not a symlink); leaving in place."
  else
    ln -sfn /runpod-volume/models /comfyui/models
  end

  # Link loras without deleting user data
  if [ -e /comfyui/models/loras ] && [ ! -L /comfyui/models/loras ]; then
    echo "Found existing /comfyui/models/loras (not a symlink); leaving in place."
  else
    ln -sfn /runpod-volume/loras /comfyui/models/loras
  fi
fi

mkdir -p /comfyui/input
mkdir -p /comfyui/output

# Start ComfyUI, then your handler. If you want handler to be PID1, swap to use 'exec'.
python3 /comfyui/main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch &
python3 -u /app/handler.py
