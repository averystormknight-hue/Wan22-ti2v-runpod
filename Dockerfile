FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

# System deps (includes common runtime libs often needed by image/video stacks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip git curl ffmpeg ca-certificates \
    libgl1 libglib2.0-0 fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# ComfyUI (pinned)
WORKDIR /comfyui
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . \
 && git checkout acbf08c

# CUDA-enabled torch stack (cu121) before other Python deps
RUN pip3 install torch==2.4.1+cu121 torchvision==0.19.1+cu121 torchaudio==2.4.1+cu121 \
    --extra-index-url https://download.pytorch.org/whl/cu121

# Pin numpy to 1.x for ComfyUI compatibility
RUN pip3 install "numpy<2"

# ComfyUI requirements
RUN pip3 install -r requirements.txt

# Custom nodes (all pinned)
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git custom_nodes/ComfyUI-VideoHelperSuite \
 && cd custom_nodes/ComfyUI-VideoHelperSuite && git checkout 3234937ff5f3ca19068aaba5042771514de2429d

RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git custom_nodes/ComfyUI-KJNodes \
 && cd custom_nodes/ComfyUI-KJNodes && git checkout 7b13271

RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git custom_nodes/ComfyUI-WanVideoWrapper \
 && cd custom_nodes/ComfyUI-WanVideoWrapper && git checkout bf1d77f \
 && sed -i 's/^        story_mem_latents = image_embeds.get(\"story_mem_latents\", None)/        image_cond_mask = None\\n        story_mem_latents = image_embeds.get(\"story_mem_latents\", None)/' nodes_sampler.py

# Install node-specific deps when present
RUN for NODE in /comfyui/custom_nodes/*/requirements.txt; do \
    if [ -f "$NODE" ]; then echo "Installing dependencies for $NODE"; pip3 install -r "$NODE"; fi; \
done

# App layer
WORKDIR /app
COPY requirements.txt .
RUN pip3 install -r requirements.txt

COPY . .

# Ensure entrypoint script is executable
RUN chmod +x /app/entrypoint.sh

CMD ["/app/entrypoint.sh"]
