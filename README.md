# Wan2.2 TI2V Serverless

[![Runpod](https://api.runpod.io/badge/averystormknight-hue/Wan22-ti2v-runpod)](https://console.runpod.io/hub/averystormknight-hue/Wan22-ti2v-runpod)

RunPod Serverless worker for Wan2.2 text + image to video (TI2V) with LoRA support, powered by ComfyUI.

## Features 
- TI2V workflow with prompt/negative prompt, steps, cfg, and length controls 
- Up to 4 LoRA pairs (high/low) per request
- Network volume support for models + LoRAs
- Auto-downloads model weights when no volume is attached
- Runsync-compatible API responses with base64 video output

## Requirements
- GPU: 80GB VRAM recommended
- Network Volume: 100GB recommended (optional but best for persistence)
- If no volume is attached, ensure container disk is large enough (40GB+).
- Model files on volume (or auto-downloaded when no volume):
  - `/runpod-volume/models/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors`
  - `/runpod-volume/models/vae/wan2.2_vae.safetensors`
  - `/runpod-volume/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors`
  - `/runpod-volume/models/clip_vision/clip_vision_h.safetensors`

## Volume Setup (download models)
If you attach a volume, put the model files here so they persist across restarts.

```bash
mkdir -p /runpod-volume/models/diffusion_models \
         /runpod-volume/models/vae \
         /runpod-volume/models/text_encoders \
         /runpod-volume/models/clip_vision

BASE22="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files"
BASE21="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files"

F=wan2.2_ti2v_5B_fp16.safetensors
curl -L -o /runpod-volume/models/diffusion_models/$F "$BASE22/diffusion_models/$F"

F=wan2.2_vae.safetensors
curl -L -o /runpod-volume/models/vae/$F "$BASE22/vae/$F"

F=umt5_xxl_fp8_e4m3fn_scaled.safetensors
curl -L -o /runpod-volume/models/text_encoders/$F "$BASE21/text_encoders/$F"

F=clip_vision_h.safetensors
curl -L -o /runpod-volume/models/clip_vision/$F "$BASE21/clip_vision/$F"
```

If no volume is attached, the worker auto-downloads to:
```
/comfyui/models/
```

## LoRA Setup
Place LoRA files in:
```
/runpod-volume/loras/
```

If you only have a single LoRA file (no paired low/high), set the other side to `"none"`.

## API Usage
**Request**
```json
{
  "input": {
    "prompt": "A cinematic slow dolly shot of a neon alley in the rain.",
    "negative_prompt": "blurry, low quality, distorted",
    "image_url": "https://example.com/input.png",
    "width": 480,
    "height": 832,
    "length": 81,
    "steps": 10,
    "cfg": 2.0,
    "seed": 42,
    "lora_pairs": [
      {
        "high": "my_high_lora.safetensors",
        "low": "none",
        "high_weight": 1.0,
        "low_weight": 1.0
      }
    ]
  }
}
```

**Response**
```json
{
  "video": "data:video/mp4;base64,..."
}
```

## Environment Variables
- `COMFY_URL` (default: `http://127.0.0.1:8188`)
- `WORKFLOW_PATH` (default: `/app/workflows/wan22_ti2v_api.json`)
- `COMFY_INPUT_DIR` (default: `/comfyui/input`)
- `COMFY_OUTPUT_DIR` (default: `/comfyui/output`)
- `NOVA_SKIP_MODEL_DOWNLOAD` (set to `1` to disable auto-download)

## Notes
- TI2V requires an image input (`image_url`, `image_base64`, or `image_path`).
- Build times are long due to pinned ComfyUI + custom nodes.

## Troubleshooting: Docker build context errors
- If you see an error like `unable to prepare context: path "/app/.../temp/https:/github.com/averystormknight-hue/Wan22-ti2v-runpod.git" not found` (note the missing second slash), make sure the build context is the checked-out repository (use `.`) and that the Git URL keeps the double slash in `https://`.
- Example local build flow:
  ```bash
  git clone https://github.com/averystormknight-hue/Wan22-ti2v-runpod.git
  cd Wan22-ti2v-runpod
  docker build -t wan22-ti2v-runpod:latest .
  ```

## Troubleshooting: "commit does not belong to any branch"
- This message appears when you deploy from a detached commit (e.g., downloading a ZIP or checking out a specific commit SHA). RunPod cannot verify or sync that state.
- Fix: create a branch that points at the commit, push it, and set RunPod to use that branch:
  ```bash
  git checkout -b main            # or another branch name you want to deploy
  git push -u origin main
  ```
- In the RunPod UI, click **Sync from GitHub** and ensure the worker uses the branch you just pushed.
