#!/usr/bin/env bash
# denoise-source.sh — ПАЙПЛАЙН-1: подготовка исходника БЕЗ 3D-этапа.
#
# Денойз hqdn3d + lossless-интермедиат. Результат — чистый исходник,
# готовый для: iw3-рендера, просмотра, архивации, повторных экспериментов.
# Потеря качества = 0 (lossless x264, qp 0): что ушло на входе, то и в файле,
# кроме шума, который убрал фильтр.
#
# ЗАПУСКАТЬ НА СИЛЬНОМ CPU (арендованный сервер / любой ПК с ffmpeg),
# НЕ на microserver (Turion без AVX, слабый).
#
# Использование:
#   bash denoise-source.sh INPUT.mp4 [OUTPUT.mp4]
#   # OUTPUT по умолчанию: <input>_denoised.mp4
#
# Рекомендации (memory/iw3-samples.md, серия Denoise A/B 10.11):
#   - hqdn3d=4:3:6:4.5 — проверенный пресет («колки не пляшут, ореолов почти нет»).
#   - При тяжёлом шуме: HQDN3D="8:6:12:9" (сильнее, но может мылить мелкую текстуру).
#   - При почти чистом источнике: HQDN3D="2:1:3:2".
# Настройка силы: HQDN3D="luma_spatial:chroma_spatial:luma_tmp:chroma_tmp"
#
# NLM_GPU (14.11): GPU-денойз NLM. Фильтра nlmeans_cuda в FFmpeg НЕ существует;
# GPU-варианты: nlmeans_vulkan (дефолт) и nlmeans_opencl.
#   NLM_GPU=1 bash denoise-source.sh ...                 # nlmeans_vulkan
#   NLM_GPU=1 NLM_FILTER=nlmeans_opencl ...              # другой бекенд
#   NLM_GPU=1 NLM_S=3.0 ...                              # сила s (дефолт 3.0)
#   NLM_GPU=1 HQDN3D="2:1:3:2" ...                       # NLM + лёгкий hqdn3d (A/B)
# Цепочка: hwupload(derive_device=vulkan) -> nlmeans_vulkan -> hwdownload -> format=yuv420p.
set -euo pipefail

IN="${1:?Использование: denoise-source.sh INPUT.mp4 [OUTPUT.mp4]}"
[ -f "$IN" ] || { echo "Нет файла: $IN"; exit 1; }

BASE="$(basename "$IN")"
NAME="${BASE%.*}"
OUT="${2:-${NAME}_denoised.mp4}"

HQDN3D="${HQDN3D:-4:3:6:4.5}"

# GPU-этап NLM (только если NLM_GPU=1 и фильтр собран)
NLM_VF=""
if [ "${NLM_GPU:-0}" = "1" ]; then
  NLM_FILTER="${NLM_FILTER:-nlmeans_vulkan}"
  if ! ffmpeg -hide_banner -filters 2>/dev/null | grep -q "$NLM_FILTER"; then
    echo "ОШИБКА: $NLM_FILTER недоступен в этом ffmpeg (нужен образ iw3-pipeline >= этой версии)" >&2
    exit 1
  fi
  NLM_S="${NLM_S:-3.0}"
  case "$NLM_FILTER" in
    nlmeans_vulkan) NLM_VF="format=yuv420p,hwupload=derive_device=vulkan,nlmeans_vulkan=s=${NLM_S},hwdownload,format=yuv420p," ;;
    nlmeans_opencl) NLM_VF="format=yuv420p,hwupload=derive_device=opencl,nlmeans_opencl=s=${NLM_S},hwdownload,format=yuv420p," ;;
    *) echo "ОШИБКА: неизвестный NLM_FILTER=$NLM_FILTER" >&2; exit 1 ;;
  esac
  echo "==> GPU-денойз: $NLM_FILTER s=${NLM_S}"
fi

echo "==> Вход:      $IN"
echo "==> Выход:     $OUT (lossless x264 qp=0)"
echo "==> Фильтр:    ${NLM_VF}hqdn3d=$HQDN3D"

# Контроль источника
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -of default=nw=1 "$IN"

START=$(date +%s)
ffmpeg -y -i "$IN" -vf "${NLM_VF}hqdn3d=${HQDN3D}" \
  -c:v libx264 -qp 0 -preset veryfast \
  -an "$OUT.part" 2> /dev/null
mv "$OUT.part" "$OUT"
END=$(date +%s)

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")
FPS=$(echo "$DUR $END $START" | awk '{printf "%.1f", $1/($2-$3)}')

echo "==> Готово за $((END-START)) с (~${FPS} FPS, x$(echo "$DUR $END $START" | awk '{printf "%.0f", ($2-$3)/$1}') realtime)"
echo "==> Размеры:"
ls -la "$IN" "$OUT"
echo
echo "Дальше (на GPU-сервере):"
echo "  python -m iw3 -y -i $OUT -o out_SBS.mp4 --depth-model Any_V3_Mono \\"
echo "    --method row_flow_v3 --divergence 4.0 --convergence 0.0 \\"
echo "    --preserve-screen-border --edge-dilation 2 1 --synthetic-view both \\"
echo "    --max-fps 30 --video-codec libx265 --pix-fmt yuv420p10le --crf 12 --preset medium"
