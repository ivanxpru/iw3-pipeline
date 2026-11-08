# syntax=docker/dockerfile:1.7
# iw3-pipeline — Docker-образ для nagadomi/nunif iw3 (2D → Full SBS 3D).
#
# СТРОГО ОТДЕЛЬНО от docker/Dockerfile (тот — старый v2d/DA3 пайплайн, не трогаем).
# Сборка ТОЛЬКО через GitHub Actions (iw3-pipeline/.github/workflows/docker-publish.yml):
# на локальном proliant legacy-builder без buildx тихо умирает (memory/docker-lessons.md).
#
# База: минимальный nvidia/cuda:12.6.3-base-ubuntu24.04 (85.6 МБ) → Ubuntu 24.04,
# Python 3.12.3 — ровно минимум iw3. torch cu126, НЕ cu132: CUDA 13.x требует
# драйвер >=580.65.06, а на офферах Qudata бывает 535.x (sm_75/80/86).
#
# ВАЖНО: Qudata монтирует volume ПОВЕРХ /workspace. Поэтому и venv, и репозиторий,
# и NUNIF_HOME запекаем в /opt/... , а entrypoint.sh идемпотентно переносит их
# в /workspace при старте (cp -rn, без перезаписи существующего).
#
# Контекст сборки = КОРЕНЬ ЭТОЙ ПАПКИ (iw3-pipeline/), не родительский репо.
#   docker build -f Dockerfile -t ivanxphub/iw3-pipeline:latest .

FROM nvidia/cuda:12.6.3-base-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NUNIF_HOME=/opt/iw3-home \
    IW3_COMMIT=b1548e8ff08758f336cdab14443647318ef5e0e9 \
    NVIDIA_DRIVER_CAPABILITIES=all

# 🚨 NVENC (08.11.2026): базовый nvidia/cuda:12.6.3-base ставит
# NVIDIA_DRIVER_CAPABILITIES=compute,utility (без video). В заезде 07.11
# платформа Qudata сама переопределяла его на all, и NVENC работал.
# 08.11 два инстанса поднялись без переопределения: /dev/nvidia-encode*
# отсутствуют, `OpenEncodeSessionEx: unsupported device`, PyAV не открывает
# hevc_nvenc даже на драйвере 580.178.04. Явный ENV в образе гарантирует
# capability video независимо от платформы. Второе условие — драйвер >=560
# (встроенный в PyAV 19 FFmpeg 9), см. memory/iw3-experiment.md §8.
# Шаблон Qudata тоже может задать env, но образ должен быть самодостаточным.

# ---------- Системные пакеты ----------
# Комментарии НЕ ставить сразу после строки с `\` — shell склейка съест команду
# (урок memory/docker-lessons.md). Каждый RUN — отдельный законченный блок.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
        python3 python3-venv python3-pip python3-dev \
        git wget curl ca-certificates \
        rsync tmux htop \
        libgl1 libglib2.0-0 \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# ---------- Репозиторий nunif (пин коммита, разобранного 07.11.2026) ----------
RUN git clone --depth 1 https://github.com/nagadomi/nunif.git /opt/nunif
RUN cd /opt/nunif && \
    if ! git cat-file -e "${IW3_COMMIT}^{commit}" 2>/dev/null; then \
        git fetch --depth 1 origin "$IW3_COMMIT"; \
    fi && \
    git checkout --detach "$IW3_COMMIT" && \
    git log -1 --format='iw3 commit %h %ad %s' --date=short

# ---------- venv + PyTorch cu126 ----------
# Порядок важен: torch ПЕРВЫМ. requirements-torch-cu126.txt фиксирует
# torch==2.14.1+cu126 / torchvision==0.29.1+cu126 (cp312-manylinux_2_28_x86_64).
RUN python3 -m venv /opt/venv
RUN /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel
RUN /opt/venv/bin/pip install --no-cache-dir -r /opt/nunif/requirements-torch-cu126.txt
RUN /opt/venv/bin/pip install --no-cache-dir -r /opt/nunif/requirements.txt
RUN /opt/venv/bin/pip install --no-cache-dir boto3

# ---------- Прогрев torch.hub + чекпойнтов (без GPU!) ----------
# update_hub качает zipball'ы форков ZoeDepth/MiDaS/Depth-Anything/DA3_iw3/VDA/pro.
# download_models тянет ZoeD_Any_N (~1.34 ГБ) — дефолтную depth-модель iw3.
# DA3MONO-LARGE грузим через create_depth_model(...).load(gpu=-1): форк hubconf
# кладёт model.safetensors в $NUNIF_HOME/iw3/pretrained_models/hub/checkpoints/.
RUN cd /opt/nunif && /opt/venv/bin/python -m iw3.update_hub
RUN cd /opt/nunif && /opt/venv/bin/python -m iw3.download_models
RUN cd /opt/nunif && /opt/venv/bin/python -c "from iw3.depth_model_factory import create_depth_model; m=create_depth_model('Any_V3_Mono'); m.load(gpu=-1); print('DA3 checkpoint:', m.get_model_path('Any_V3_Mono'))"

# ---------- VDA_L (Video Depth Anything Large) ----------
# 08.11.2026: добавлен для борьбы с «завихрением фона» при движении объекта.
# VDA — temporal-стабильная depth (память между кадрами), в отличие от
# покадровой Any_V3_Mono. Апстрим-форк nagadomi/Video-Depth-Anything_iw3
# НЕ умеет автокачать vitl/vitb (только vits) — требует файл вручную в
# torch.hub.get_dir()/checkpoints (= $TORCH_HOME/hub/checkpoints;
# НЕ зависит от NUNIF_HOME). Имя файла — по hubconf.py форка.
# Кладём в /opt/iw3-home/torch_hub (не /root/.cache) — Qudata монтирует
# volume ПОВЕРХ /workspace, но /opt сохраняется в слое образа;
# entrypoint выставляет TORCH_HOME=/opt/iw3-home/torch_hub.
RUN mkdir -p /opt/iw3-home/torch_hub/hub/checkpoints && \
    cd /opt/iw3-home/torch_hub/hub/checkpoints && \
    wget -c -q --tries=0 --timeout=60 \
        "https://huggingface.co/depth-anything/Video-Depth-Anything-Large/resolve/main/video_depth_anything_vitl.pth?download=true" \
        -O video_depth_anything_vitl.pth && \
    stat -c '%s %n' video_depth_anything_vitl.pth && \
    test "$(stat -c %s video_depth_anything_vitl.pth)" = "1538392012"

# Стерео/inpaint/AA чекпойнты: маленькие, но без них первый запуск лезет в сеть.
# Все URL — из iw3/stereo_model_factory.py, iw3/inpaint_utils.py, iw3/models/depth_aa.py.
RUN mkdir -p /opt/iw3-home/iw3/pretrained_models/hub/checkpoints && \
    cd /opt/iw3-home/iw3/pretrained_models/hub/checkpoints && \
    for f in \
        iw3_row_flow_v3_20250627.pth \
        iw3_row_flow_v3_sym_20250628.pth \
        iw3_row_flow_v2_20240130.pth \
        iw3_mlbw_l2_d1_20250627.pth \
        iw3_mlbw_l2_d2_20250627.pth \
        iw3_mlbw_l2_d3_20250627.pth \
        iw3_mlbw_l2s_d1_20250627.pth \
        iw3_mlbw_l4_d1_20250627.pth \
        iw3_mask_mlbw_l2_d1_20250903.pth \
        iw3_light_inpaint_v1_20250919.pth \
        iw3_light_video_inpaint_v1_20250919.pth \
        iw3_depth_aa_20250530.pth \
        iw3_sod_v1_20260125.pth ; do \
        wget -c -q --tries=0 --timeout=60 \
            "https://github.com/nagadomi/nunif/releases/download/0.0.0/$f" || exit 1; \
    done && \
    ls -la && du -sh /opt/iw3-home

# ---------- Sanity на этапе сборки (CUDA недоступна, проверяем импорты/кодеки) ----------
RUN cd /opt/nunif && /opt/venv/bin/python -c "import torch, av, sys; print('python:', sys.version.split()[0]); print('torch :', torch.__version__, 'cuda', torch.version.cuda); print('av    :', av.__version__); [print('codec', c, ':', c in av.codecs_available) for c in ('hevc_nvenc','h264_nvenc','libx265','libx264')]"
RUN cd /opt/nunif && /opt/venv/bin/python -m iw3 -h >/dev/null && echo "iw3 CLI OK"

# ---------- Скрипты + структура ----------
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh
RUN mkdir -p /workspace/input /workspace/output /workspace/logs /workspace/scripts
WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]
