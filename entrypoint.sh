#!/usr/bin/env bash
set -euo pipefail

MODEL_ROOT="/comfyui/models"
LORA_ROOT="/comfyui/models/loras"

# Wire shared storage safely (prefer volume when present)
if [ -d /runpod-volume ]; then
  mkdir -p /runpod-volume/models /runpod-volume/loras
  MODEL_ROOT="/runpod-volume/models"
  LORA_ROOT="/runpod-volume/loras"

  # Point ComfyUI to the volume-backed models so loaders see the files
  if [ -e /comfyui/models ] && [ ! -L /comfyui/models ]; then
    mv /comfyui/models "/comfyui/models.local.$(date +%s)"
  fi
  ln -sfn "$MODEL_ROOT" /comfyui/models

  if [ -e /comfyui/models/loras ] && [ ! -L /comfyui/models/loras ]; then
    mv /comfyui/models/loras "/comfyui/models/loras.local.$(date +%s)"
  fi
  ln -sfn "$LORA_ROOT" /comfyui/models/loras

elif [ -d /workspace ]; then
  # Some RunPod templates mount the volume at /workspace; normalize to expected path
  mkdir -p /workspace/models /workspace/loras
  MODEL_ROOT="/workspace/models"
  LORA_ROOT="/workspace/loras"
  ln -sfn /workspace /runpod-volume

  if [ -e /comfyui/models ] && [ ! -L /comfyui/models ]; then
    mv /comfyui/models "/comfyui/models.local.$(date +%s)"
  fi
  ln -sfn "$MODEL_ROOT" /comfyui/models

  if [ -e /comfyui/models/loras ] && [ ! -L /comfyui/models/loras ]; then
    mv /comfyui/models/loras "/comfyui/models/loras.local.$(date +%s)"
  fi
  ln -sfn "$LORA_ROOT" /comfyui/models/loras
else
  mkdir -p "$MODEL_ROOT" "$LORA_ROOT"
fi

download_if_missing() {
  local url="$1"
  local dest="$2"

  if [ -s "$dest" ]; then
    echo "Found $(basename "$dest")"
    return 0
  fi

  echo "Downloading $(basename "$dest")"
  mkdir -p "$(dirname "$dest")"
  curl -L --fail --retry 8 --retry-delay 5 --retry-connrefused \
    --output "$dest" --continue-at - "$url"
}

if [ "${NOVA_SKIP_MODEL_DOWNLOAD:-0}" != "1" ]; then
  WAN_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"
  WAN_BASE_21="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files"

  download_if_missing \
    "${WAN_BASE}/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors" \
    "${MODEL_ROOT}/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors"
  download_if_missing \
    "${WAN_BASE}/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors" \
    "${MODEL_ROOT}/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors"
  download_if_missing \
    "${WAN_BASE_21}/vae/wan_2.1_vae.safetensors" \
    "${MODEL_ROOT}/vae/wan_2.1_vae.safetensors"
  download_if_missing \
    "${WAN_BASE_21}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
    "${MODEL_ROOT}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
  download_if_missing \
    "${WAN_BASE_21}/clip_vision/clip_vision_h.safetensors" \
    "${MODEL_ROOT}/clip_vision/clip_vision_h.safetensors"

  # Preload T2V LoRAs (4 pairs) for 14B without needing a volume
  download_if_missing \
    "https://huggingface.co/wolfer45/masturbationv1dtwr-high-t2v-wan22/resolve/main/masturbationv1dtwr-high-t2v-wan22.safetensors" \
    "${LORA_ROOT}/masturbationv1dtwr-high-t2v-wan22.safetensors"
  download_if_missing \
    "https://huggingface.co/wolfer45/masturbationv1dtwr-low-t2v-wan22/resolve/main/masturbationv1dtwr-low-t2v-wan22.safetensors" \
    "${LORA_ROOT}/masturbationv1dtwr-low-t2v-wan22.safetensors"
  download_if_missing \
    "https://huggingface.co/wangkanai/wan22-fp8-t2v-loras-nsfw/resolve/main/loras/wan/wan22-action-missionary-pov-t2v-high.safetensors" \
    "${LORA_ROOT}/wan22-action-missionary-pov-t2v-high.safetensors"
  download_if_missing \
    "https://huggingface.co/wangkanai/wan22-fp8-t2v-loras-nsfw/resolve/main/loras/wan/wan22-action-missionary-pov-t2v-low.safetensors" \
    "${LORA_ROOT}/wan22-action-missionary-pov-t2v-low.safetensors"
  download_if_missing \
    "https://huggingface.co/wangkanai/wan22-fp8-t2v-loras-nsfw/resolve/main/loras/wan/wan22-action-doggystyle-t2v-14b-high.safetensors" \
    "${LORA_ROOT}/wan22-action-doggystyle-t2v-14b-high.safetensors"
  download_if_missing \
    "https://huggingface.co/wangkanai/wan22-fp8-t2v-loras-nsfw/resolve/main/loras/wan/wan22-action-doggystyle-t2v-14b-low.safetensors" \
    "${LORA_ROOT}/wan22-action-doggystyle-t2v-14b-low.safetensors"
  download_if_missing \
    "https://huggingface.co/wangkanai/wan22-fp8-t2v-loras-nsfw/resolve/main/loras/wan/wan22-action-orgasm-t2v-14b-high.safetensors" \
    "${LORA_ROOT}/wan22-action-orgasm-t2v-14b-high.safetensors"
  download_if_missing \
    "https://huggingface.co/wangkanai/wan22-fp8-t2v-loras-nsfw/resolve/main/loras/wan/wan22-action-orgasm-t2v-14b-low.safetensors" \
    "${LORA_ROOT}/wan22-action-orgasm-t2v-14b-low.safetensors"
else
  REQUIRED=(
    "${MODEL_ROOT}/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors"
    "${MODEL_ROOT}/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors"
    "${MODEL_ROOT}/vae/wan_2.1_vae.safetensors"
    "${MODEL_ROOT}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    "${MODEL_ROOT}/clip_vision/clip_vision_h.safetensors"
    "${LORA_ROOT}/masturbationv1dtwr-high-t2v-wan22.safetensors"
    "${LORA_ROOT}/masturbationv1dtwr-low-t2v-wan22.safetensors"
    "${LORA_ROOT}/wan22-action-missionary-pov-t2v-high.safetensors"
    "${LORA_ROOT}/wan22-action-missionary-pov-t2v-low.safetensors"
    "${LORA_ROOT}/wan22-action-doggystyle-t2v-14b-high.safetensors"
    "${LORA_ROOT}/wan22-action-doggystyle-t2v-14b-low.safetensors"
    "${LORA_ROOT}/wan22-action-orgasm-t2v-14b-high.safetensors"
    "${LORA_ROOT}/wan22-action-orgasm-t2v-14b-low.safetensors"
  )
  MISSING=0
  for f in "${REQUIRED[@]}"; do
    if [ ! -s "$f" ]; then
      MISSING=1
      break
    fi
  done

  if [ "$MISSING" -eq 1 ]; then
    echo "NOVA_SKIP_MODEL_DOWNLOAD=1 set, but required models are missing. Downloading anyway…"
    WAN_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"
    WAN_BASE_21="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files"

    download_if_missing \
      "${WAN_BASE}/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors" \
      "${MODEL_ROOT}/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors"
    download_if_missing \
      "${WAN_BASE}/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors" \
      "${MODEL_ROOT}/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors"
    download_if_missing \
      "${WAN_BASE_21}/vae/wan_2.1_vae.safetensors" \
      "${MODEL_ROOT}/vae/wan_2.1_vae.safetensors"
    download_if_missing \
      "${WAN_BASE_21}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
      "${MODEL_ROOT}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    download_if_missing \
      "${WAN_BASE_21}/clip_vision/clip_vision_h.safetensors" \
      "${MODEL_ROOT}/clip_vision/clip_vision_h.safetensors"
  else
    echo "Skipping model downloads (NOVA_SKIP_MODEL_DOWNLOAD=1 and all required models present)."
  fi
fi

mkdir -p /comfyui/input
mkdir -p /comfyui/output

# Start ComfyUI, then your handler. If you want handler to be PID1, swap to use 'exec'.
python3 /comfyui/main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch &
python3 -u /app/handler.py
