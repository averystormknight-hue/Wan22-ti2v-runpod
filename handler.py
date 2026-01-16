import base64
import json
import os
import shutil
import time
import uuid

import requests
import runpod

COMFY_URL = os.getenv("COMFY_URL", "http://127.0.0.1:8188")
WORKFLOW_PATH = os.getenv("WORKFLOW_PATH", "/app/workflows/wan22_ti2v_api.json")
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
        return {"status": "ok"}

    wait_for_comfyui()

    image_filename = save_input_image(inp)
    if not image_filename:
        return {"error": "image_url, image_base64, or image_path is required for TI2V."}

    with open(WORKFLOW_PATH, "r") as f:
        workflow = json.load(f)

    mapping = build_mapping(inp, image_filename)
    workflow = replace_tokens(workflow, mapping)

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
