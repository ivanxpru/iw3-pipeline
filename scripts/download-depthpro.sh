#!/bin/bash
# Докачка gated-весов Depth Pro на инстансе (если в образе не запечены).
# apple/DepthPro-checkpoints — gated репозиторий HuggingFace (лицензия Apple ML):
# нужен HF_TOKEN аккаунта, где приняты условия лицензии.
# Использование: HF_TOKEN=hf_xxx bash /workspace/scripts/download-depthpro.sh
set -euo pipefail

CHECKPOINT_DIR="${NUNIF_HOME:-/workspace/nunif_home}/iw3/pretrained_models/hub/checkpoints"
TARGET="$CHECKPOINT_DIR/depth_pro.pt"

mkdir -p "$CHECKPOINT_DIR"

if [ -f "$TARGET" ] && [ "$(stat -c %s "$TARGET")" -gt 1500000000 ]; then
    echo "DepthPro weight already present: $TARGET"
    exit 0
fi

if [ -z "${HF_TOKEN:-}" ]; then
    echo "ERROR: HF_TOKEN is not set." >&2
    echo "Get a token at https://huggingface.co/settings/tokens and accept the" >&2
    echo "license at https://huggingface.co/apple/DepthPro-checkpoints first." >&2
    exit 1
fi

# wget из окружения инстанса может быть без TLS-прокси — используем curl с retry.
curl -fL --retry 5 --retry-delay 3 \
    -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/apple/DepthPro-checkpoints/resolve/main/depth_pro.pt?download=true" \
    -o "$TARGET"

SIZE=$(stat -c %s "$TARGET")
echo "Downloaded: $TARGET ($SIZE bytes)"
# Веса ViT-Huge ~2 ГБ; всё, что меньше 1.5 ГБ — обрыв/усечённый файл.
if [ "$SIZE" -lt 1500000000 ]; then
    echo "ERROR: file too small, download truncated" >&2
    exit 1
fi
echo "OK"
