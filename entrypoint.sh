#!/bin/bash
# Entrypoint iw3-pipeline.
# Qudata монтирует volume ПОВЕРХ /workspace → всё, что запечено в слое образа
# (/opt/venv, /opt/nunif, /opt/iw3-home, /opt/scripts), скрывается пустым volume.
# Идемпотентно переносим в /workspace, НЕ перезаписывая существующие файлы.
set -euo pipefail

export NUNIF_HOME=/workspace/nunif_home
# VDA_L лежит в /opt/iw3-home/torch_hub/hub/checkpoints (см. Dockerfile);
# TORCH_HOME направляет torch.hub.load_state_dict_from_url туда же,
# иначе VDA_L попытается докачаться в /root/.cache/torch.
export TORCH_HOME=/opt/iw3-home/torch_hub

# mkdir ОБЯЗАТЕЛЕН: `cp -rn src/. dest/` падает, если dest не существует,
# а `|| true` это молча глотает → на чистом volume стек «пропадает» (баг 10.11).
mkdir -p /workspace/input /workspace/output /workspace/logs /workspace/scripts \
         /workspace/venv /workspace/nunif /workspace/nunif_home

# cp -rn: не трогаем то, что уже есть (например, докачано с S3 в прошлой сессии).
[ -d /opt/venv ]      && cp -rn /opt/venv/.      /workspace/venv/      2>/dev/null || true
[ -d /opt/nunif ]     && cp -rn /opt/nunif/.     /workspace/nunif/     2>/dev/null || true
[ -d /opt/iw3-home ]  && cp -rn /opt/iw3-home/.  /workspace/nunif_home/ 2>/dev/null || true
[ -d /opt/scripts ]   && cp -rn /opt/scripts/.   /workspace/scripts/    2>/dev/null || true

# Обрывки wget / пустые файлы от прошлых заездов не должны считаться готовыми весами.
find /workspace/nunif_home -type f -size 0 -delete 2>/dev/null || true

# GeForce + compat = CUDA error 804: compat libcuda (для datacenter) перекрывает
# системный драйвер через ldconfig. На инстансе с GeForce compat не нужен.
if [ -d /usr/local/cuda-12.6/compat ] && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -qi geforce; then
    mv /usr/local/cuda-12.6/compat /usr/local/cuda-12.6/compat.disabled 2>/dev/null || true
    ldconfig 2>/dev/null || true
fi

# Depth Pro: апстрим-флаг консервативный (покадровый инференс через видео-пайплайн
# работает — проверено 09.11 и 10.11).
DPM=/workspace/nunif/iw3/depth_models/depth_pro_model.py
if [ -f "$DPM" ] && grep -A1 "def is_video_supported" "$DPM" | grep -q "return False"; then
    sed -i -E "s/(def is_video_supported\(self\):\n[ \t]*)return False/\1return True/" "$DPM" 2>/dev/null \
      || python3 - "$DPM" <<'PYEOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = s.replace("def is_video_supported(self):\n        return False", "def is_video_supported(self):\n        return True")
open(p, "w").write(s)
PYEOF
fi

# venv создавался в /opt/venv, поэтому shebang'ы внутри указывают на старый путь.
# Лечим симлинком, чтобы `source /workspace/venv/bin/activate` работал без пересборки.
if [ -d /workspace/venv ] && [ ! -e /opt/venv ]; then
    ln -s /workspace/venv /opt/venv
fi

echo "=== IW3 READY ==="
echo "  source /workspace/venv/bin/activate && cd /workspace/nunif"
echo "  NUNIF_HOME=$NUNIF_HOME"
echo "  python -m iw3 -h"

exec "$@"
