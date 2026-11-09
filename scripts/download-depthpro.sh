#!/bin/bash
# Докачка весов Depth Pro на инстансе (запасной путь — в образе вес уже запечён).
# ОСНОВНОЙ источник: DagsHub S3 (s3://$S3_BUCKET/models/depth-pro/depth_pro.pt)
# — канал с арендованных серверов до HF нестабилен (memory/s3-storage.md),
# а все нужные ключи уже на сервере в /workspace/.s3env (s3-sync.sh env-up).
# Запасной: HF apple/DepthPro (открытый репо, токен не нужен).
# depth_pro.pt = 1 904 446 787 байт.
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

# --- 1) Пробуем S3 (ключи из /workspace/.s3env, ставится s3-sync.sh env-up) ---
if [ -f /workspace/.s3env ]; then
    # на сервере прокси НЕ нужен (и вреден: 127.0.0.1:2080 там не существует)
    unset S3_PROXY HTTP_PROXY HTTPS_PROXY http_proxy https_proxy || true
    set -a; source /workspace/.s3env; set +a
    export AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null
    if aws --region "${AWS_DEFAULT_REGION:-us-east-1}" --endpoint-url "$S3_ENDPOINT" \
           s3api get-object \
           --bucket "$S3_BUCKET" --key "models/depth-pro/depth_pro.pt" \
           "$TARGET" 2>/dev/null; then
        SIZE=$(stat -c %s "$TARGET")
        echo "Downloaded from S3: $TARGET ($SIZE bytes)"
        [ "$SIZE" = "$EXPECTED_SIZE" ] && { echo "OK"; exit 0; }
        echo "ERROR: S3 copy has wrong size, removing" >&2
        rm -f "$TARGET"
    else
        echo "S3 download failed, falling back to HuggingFace..."
    fi
fi

# --- 2) Запасной путь: HuggingFace (репо apple/DepthPro, gated: false) ---
curl -fL --retry 5 --retry-delay 3 \
    "https://huggingface.co/apple/DepthPro/resolve/main/depth_pro.pt?download=true" \
    -o "$TARGET"

SIZE=$(stat -c %s "$TARGET")
echo "Downloaded from HF: $TARGET ($SIZE bytes)"
if [ "$SIZE" != "$EXPECTED_SIZE" ]; then
    echo "ERROR: unexpected size (expected $EXPECTED_SIZE), download truncated" >&2
    exit 1
fi
echo "OK"
