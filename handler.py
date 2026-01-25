import base64

# Startup marker for test logs
print("[TI2V] handler imported and starting…")
import json
import os
import shutil
import time
import uuid

import requests
import runpod

COMFY_URL = os.getenv("COMFY_URL", "http://127.0.0.1:8188")
WORKFLOW_PATH = os.getenv("WORKFLOW_PATH", "/app/workflows/wan22_t2v_api.json")
INPUT_DIR = os.getenv("COMFY_INPUT_DIR", "/comfyui/input")
OUTPUT_DIR = os.getenv("COMFY_OUTPUT_DIR", "/comfyui/output")
COMFY_START_TIMEOUT = int(os.getenv("COMFY_START_TIMEOUT", "900"))


def wait_for_comfyui(timeout=COMFY_START_TIMEOUT):
    start = time.time()
    while time.time() - start < timeout:
        try:
            requests.get(f"{COMFY_URL}/system_stats", timeout=3)
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError("ComfyUI did not start in time")


def save_input_image(inp):
    os.makedirs(INPUT_DIR, exist_ok=True)

    if "image_path" in inp and inp["image_path"]:
        src = inp["image_path"]
        ext = os.path.splitext(src)[1] or ".png"
        name = f"input_{uuid.uuid4().hex}{ext}"
        dst = os.path.join(INPUT_DIR, name)
        shutil.copyfile(src, dst)
        return name

    if "image_url" in inp and inp["image_url"]:
        resp = requests.get(inp["image_url"], timeout=30)
        resp.raise_for_status()
        data = resp.content
    elif "image_base64" in inp and inp["image_base64"]:
        raw = inp["image_base64"]
        if raw.startswith("data:"):
            raw = raw.split(",", 1)[1]
        data = base64.b64decode(raw)
    else:
        return None

    name = f"input_{uuid.uuid4().hex}.png"
    dst = os.path.join(INPUT_DIR, name)
    with open(dst, "wb") as f:
        f.write(data)
    return name


def replace_tokens(obj, mapping):
    if isinstance(obj, dict):
        return {k: replace_tokens(v, mapping) for k, v in obj.items()}
    if isinstance(obj, list):
        return [replace_tokens(v, mapping) for v in obj]
    if isinstance(obj, str):
        if obj in mapping:
            return mapping[obj]
        for key, val in mapping.items():
            if isinstance(val, str) and key in obj:
                obj = obj.replace(key, val)
        return obj
    return obj


def lora_name(value):
    if not value:
        return "none"
    return value


def build_mapping(inp, image_filename):
    prompt = inp.get("prompt", "")
    negative = inp.get("negative_prompt", "")
    width = int(inp.get("width", 480))
    height = int(inp.get("height", 832))
    length = int(inp.get("length", 81))
    steps = int(inp.get("steps", 10))
    cfg = float(inp.get("cfg", 2.0))
    seed = int(inp.get("seed", 42))
    scheduler = inp.get("scheduler", "dpm++_sde")
    context_overlap = int(inp.get("context_overlap", 48))
    context_frames = int(inp.get("context_frames", min(length, 81)))

    pairs = inp.get("lora_pairs", [])
    highs = ["none"] * 4
    lows = ["none"] * 4
    high_weights = [1.0] * 4
    low_weights = [1.0] * 4
    for idx in range(min(4, len(pairs))):
        pair = pairs[idx] or {}
        highs[idx] = lora_name(pair.get("high"))
        lows[idx] = lora_name(pair.get("low"))
        high_weights[idx] = float(pair.get("high_weight", 1.0))
        low_weights[idx] = float(pair.get("low_weight", 1.0))

    return {
        "__PROMPT__": prompt,
        "__NEGATIVE__": negative,
        "__IMAGE_FILENAME__": image_filename or "",
        "__WIDTH__": width,
        "__HEIGHT__": height,
        "__LENGTH__": length,
        "__STEPS__": steps,
        "__CFG__": cfg,
        "__SEED__": seed,
        "__SCHEDULER__": scheduler,
        "__CONTEXT_FRAMES__": context_frames,
        "__CONTEXT_OVERLAP__": context_overlap,
        "__LORA1_HIGH__": highs[0],
        "__LORA1_LOW__": lows[0],
        "__LORA1_HIGH_WEIGHT__": high_weights[0],
        "__LORA1_LOW_WEIGHT__": low_weights[0],
        "__LORA2_HIGH__": highs[1],
        "__LORA2_LOW__": lows[1],
        "__LORA2_HIGH_WEIGHT__": high_weights[1],
        "__LORA2_LOW_WEIGHT__": low_weights[1],
        "__LORA3_HIGH__": highs[2],
        "__LORA3_LOW__": lows[2],
        "__LORA3_HIGH_WEIGHT__": high_weights[2],
        "__LORA3_LOW_WEIGHT__": low_weights[2],
        "__LORA4_HIGH__": highs[3],
        "__LORA4_LOW__": lows[3],
        "__LORA4_HIGH_WEIGHT__": high_weights[3],
        "__LORA4_LOW_WEIGHT__": low_weights[3],
    }

def switch_to_t2v_node(workflow):
    """Switch Node 541 from I2V encoder to WanVideoEmptyEmbeds for T2V generation."""
    if "541" in workflow and isinstance(workflow["541"], dict):
        node = workflow["541"]
        node["class_type"] = "WanVideoEmptyEmbeds"
        inputs = node.get("inputs", {})
        
        # Standardize frame count parameters
        length = inputs.get("num_frames", inputs.get("video_frames", "__LENGTH__"))
        inputs["num_frames"] = length
        inputs["video_frames"] = length
        inputs["empty_latent_video_frames"] = length
        
        # Standardize dimension parameters
        width = inputs.get("width", "__WIDTH__")
        height = inputs.get("height", "__HEIGHT__")
        inputs["empty_latent_width"] = width
        inputs["empty_latent_height"] = height
        
        # Remove inputs not needed for T2V empty embeds
        for key in ["start_image", "image", "vae", "clip_embeds"]:
            inputs.pop(key, None)
            
    return workflow

def get_output_file(history):
    outputs = history.get("outputs", {})
    for node in outputs.values():
        for key in ("videos", "gifs", "images"):
            files = node.get(key, [])
            for item in files:
                filename = item.get("filename")
                subfolder = item.get("subfolder", "")
                if not filename:
                    continue
                path = os.path.join(OUTPUT_DIR, subfolder, filename)
                if os.path.exists(path):
                    return path
    return None


def handler(job):
    inp = job.get("input", {})
    if inp.get("test_mode"):
        print("[TI2V] test_mode short-circuit")
        return {"status": "ok"}

    wait_for_comfyui()

    # T2V endpoint: image is optional; ensure a placeholder exists to keep loaders happy
    image_filename = save_input_image(inp)
    if not image_filename:
        os.makedirs(INPUT_DIR, exist_ok=True)
        placeholder = os.path.join(INPUT_DIR, "placeholder_1x1.png")
        if not os.path.exists(placeholder):
            # 1x1 transparent PNG
            png_bytes = base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="
            )
            with open(placeholder, "wb") as f:
                f.write(png_bytes)
        image_filename = os.path.basename(placeholder)

    with open(WORKFLOW_PATH, "r") as f:
        workflow = json.load(f)

    # Force attention_mode to 'sdpa' to support non-H100 GPUs (e.g. A100/L40)
    for node_id in ("122", "549"):
        if node_id in workflow:
            inputs = workflow[node_id].get("inputs", {})
            if "attention_mode" in inputs:
                print(f"Forcing attention_mode to 'sdpa' on node {node_id}")
                inputs["attention_mode"] = "sdpa"

    mapping = build_mapping(inp, image_filename)
    workflow = replace_tokens(workflow, mapping)
    workflow = switch_to_t2v_node(workflow)

    try:
        resp = requests.post(
            f"{COMFY_URL}/prompt",
            json={"prompt": workflow},
            timeout=30,
        )
        resp.raise_for_status()
        prompt_id = resp.json()["prompt_id"]
    except requests.exceptions.RequestException as exc:
        return {"error": f"Failed to submit prompt to ComfyUI: {exc}"}

    start = time.time()
    while time.time() - start < 1800:
        try:
            hist_resp = requests.get(
                f"{COMFY_URL}/history/{prompt_id}",
                timeout=10,
            )
            hist_resp.raise_for_status()
            hist = hist_resp.json()
        except (requests.exceptions.RequestException, ValueError) as exc:
            return {"error": f"Failed while polling ComfyUI: {exc}"}
        if prompt_id in hist:
            out_path = get_output_file(hist[prompt_id])
            if out_path:
                with open(out_path, "rb") as f:
                    data = base64.b64encode(f.read()).decode("utf-8")
                return {"video": f"data:video/mp4;base64,{data}"}
        time.sleep(2)

    return {"error": "Timed out waiting for output."}


runpod.serverless.start({"handler": handler})
