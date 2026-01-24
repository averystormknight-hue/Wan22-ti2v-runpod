FROM --platform=linux/amd64 nvidia/cuda:12.1.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

# System deps (includes common runtime libs often needed by image/video stacks)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip git curl ffmpeg ca-certificates patch \
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

RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git custom_nodes/ComfyUI-WanVideoWrapper

# Apply local patch to WanVideoWrapper (init image_cond_mask)
COPY patches /patches
RUN cd custom_nodes/ComfyUI-WanVideoWrapper && patch -p1 -N --silent < /patches/nodes_sampler.patch || true

# Force-disable the T2V check that blocks image_embeds (since we use dummy embeds)
# Inject image_cond = None to force T2V mode and avoid tensor mismatch
RUN sed -i 's/has_ref = image_embeds.get("has_ref", False)/has_ref = image_embeds.get("has_ref", False); image_cond = None/' custom_nodes/ComfyUI-WanVideoWrapper/nodes_sampler.py || true

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
