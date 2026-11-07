#!/usr/bin/env bash
# Проверка окружения iw3 внутри контейнера. CUDA-часть — только на GPU-инстансе.
set -euo pipefail
cd /workspace/nunif
source /workspace/venv/bin/activate

python - <<'PY'
import os, sys, torch, av
print("python      :", sys.version.split()[0])
print("torch       :", torch.__version__, "cuda", torch.version.cuda)
print("cuda avail  :", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu         :", torch.cuda.get_device_name(0))
print("av          :", av.__version__)
for c in ("hevc_nvenc", "h264_nvenc", "libx265", "libx264"):
    print(f"codec {c:<12}:", c in av.codecs_available)
print("NUNIF_HOME  :", os.environ.get("NUNIF_HOME"))
PY

python -m iw3 -h >/dev/null && echo "python -m iw3 -h: OK"

echo "=== чекпойнты ==="
find /workspace/nunif_home/iw3/pretrained_models/hub/checkpoints -maxdepth 1 -type f \
    -printf '%10s  %f\n' | sort -n | tail -20
