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

mkdir -p /workspace/input /workspace/output /workspace/logs /workspace/scripts

# cp -rn: не трогаем то, что уже есть (например, докачано с S3 в прошлой сессии).
[ -d /opt/venv ]      && cp -rn /opt/venv/.      /workspace/venv/      2>/dev/null || true
[ -d /opt/nunif ]     && cp -rn /opt/nunif/.     /workspace/nunif/     2>/dev/null || true
[ -d /opt/iw3-home ]  && cp -rn /opt/iw3-home/.  /workspace/nunif_home/ 2>/dev/null || true
[ -d /opt/scripts ]   && cp -rn /opt/scripts/.   /workspace/scripts/    2>/dev/null || true

# Обрывки wget / пустые файлы от прошлых заездов не должны считаться готовыми весами.
find /workspace/nunif_home -type f -size 0 -delete 2>/dev/null || true

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
