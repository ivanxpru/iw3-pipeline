#!/bin/bash
# Докачка весов Depth Pro на инстансе (если по какой-то причине их нет в образе).
# Источник: apple/DepthPro на HuggingFace — ОТКРЫТЫЙ репозиторий (gated: false),
# токен не нужен. depth_pro.pt = 1 904 446 787 байт.
# Использование: bash /workspace/scripts/download-depthpro.sh
set -euo pipefail

CHECKPOINT_DIR="${NUNIF_HOME:-/workspace/nunif_home}/iw3/pretrained_models/hub/checkpoints"
TARGET="$CHECKPOINT_DIR/depth_pro.pt"
EXPECTED_SIZE=1904446787

mkdir -p "$CHECKPOINT_DIR"

if [ -f "$TARGET" ] && [ "$(stat -c %s "$TARGET")" = "$EXPECTED_SIZE" ]; then
    echo "DepthPro weight already present: $TARGET"
    exit 0
fi

curl -fL --retry 5 --retry-delay 3 \
    "https://huggingface.co/apple/DepthPro/resolve/main/depth_pro.pt?download=true" \
    -o "$TARGET"

SIZE=$(stat -c %s "$TARGET")
echo "Downloaded: $TARGET ($SIZE bytes)"
if [ "$SIZE" != "$EXPECTED_SIZE" ]; then
    echo "ERROR: unexpected size (expected $EXPECTED_SIZE), download truncated" >&2
    exit 1
fi
echo "OK"
