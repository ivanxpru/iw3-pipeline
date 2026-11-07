#!/usr/bin/env bash
# Эталонный полный рендер iw3 (одобрен пользователем 07.11.2026).
# См. memory/iw3-samples.md: test30_iw3_MAX_border_d50_c000.mp4.
#
#   bash /workspace/scripts/render-full.sh /workspace/input/gary_moore.mp4 /workspace/output/out_LRF_Full_SBS.mp4
set -euo pipefail
SRC_REPO=/workspace/nunif
OUT_DIR=/workspace/output
IN="${1:-/workspace/input/gary_moore.mp4}"
OUT="${2:-$OUT_DIR/Gary_Moore_iw3_MAX_border_FULL.mp4}"

source /workspace/venv/bin/activate
cd "$SRC_REPO"
mkdir -p "$OUT_DIR"

exec python -m iw3 -y \
    -i "$IN" -o "$OUT" \
    --depth-model Any_V3_Mono \
    --method row_flow_v3 \
    --divergence 5.0 \
    --convergence 0.0 \
    --preserve-screen-border \
    --edge-dilation 2 1 \
    --synthetic-view both \
    --max-fps 30 \
    --video-codec hevc_nvenc \
    --pix-fmt yuv420p10le \
    --crf 12 --preset p7
