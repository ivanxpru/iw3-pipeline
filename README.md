# iw3-pipeline

Самодостаточный Docker-образ для **nagadomi/nunif `iw3`** (2D → Full SBS 3D, HEVC Main10). Отдельный репозиторий по образцу `v2d-pipeline/` — старый [`docker/Dockerfile`](../docker/Dockerfile) (DA3 + self-written Z-buffer) **не трогаем**.

## Что внутри

| | |
|---|---|
| База | `nvidia/cuda:12.6.3-base-ubuntu24.04` (85.6 МБ) → Ubuntu 24.04, **Python 3.12.3** |
| Стек | `torch==2.14.1+cu126` / `torchvision==0.29.1+cu126`, `av==19.0.2` (PyAV со встроенными `hevc_nvenc`/`libx265`), `timm`, `boto3` |
| Код | `nunif` с пином коммита `b1548e8ff08758f336cdab14443647318ef5e0e9` (07.11.2026) |
| Модели | DA3MONO-LARGE (~1.34 ГБ), ZoeD_Any_N (~1.34 ГБ), `row_flow_v3`/`v3_sym`/`v2`, `mlbw_*`, `mask_mlbw`, `light_(video_)inpaint`, `depth_aa`, `sod_v1` + все torch.hub-форки |
| venv | `/opt/venv` → при старте `/workspace/venv` |

**Почему cu126, а не cu132:** CUDA 13.x требует драйвер ≥580.65.06, на офферах Qudata встречается 535.x. cu126 работает с ≥525 и покрывает sm_75/80/86/90.

**Почему `/opt`, а не `/workspace`:** Qudata монтирует volume поверх `/workspace`, всё из слоя образа скрывается. `entrypoint.sh` делает `cp -rn` в `/workspace` и создаёт симлинк `/opt/venv → /workspace/venv` (shebang'ы pip-скриптов указывают на `/opt/venv`).

## Сборка

**Только через GitHub Actions** (`.github/workflows/docker-publish.yml`): на локальном proliant legacy-builder без buildx тихо умирает (`memory/docker-lessons.md`). Контекст сборки — **корень этой папки**.

```
cd iw3-pipeline
git init && git remote add origin <repo> && git add . && git commit -m "iw3 pipeline"
git push -u origin main           # → ivanxphub/iw3-pipeline:latest
```

Логин Docker Hub `ivanxphub`, секреты `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` уже настроены в `v2d-pipeline` — перенести в новый репо. Кэш `type=gha` обязателен: torch + 2.7 ГБ весов.

## Регистрация шаблона Qudata

```
create_template(
  name="iw3-pipeline-full",
  image="ivanxphub/iw3-pipeline", image_tag="latest",
  is_private=true, ssh_enabled=true, ssh_username="root",
  min_storage_gb=50,
  env_variables={"NUNIF_HOME": "/workspace/nunif_home"})
```

⚠️ **Не задавать `NVIDIA_DRIVER_CAPABILITIES`** — в заезде 07.11 платформа сама выставила `all` (иначе NVENC может пропасть). `/workspace` не создаётся автоматически — entrypoint делает `mkdir -p`.

## Использование на инстансе

```bash
source /workspace/venv/bin/activate && cd /workspace/nunif
python -m iw3 -h
bash /workspace/scripts/check-iw3.sh

# Эталонный полный рендер (одобрен, d=5.0 / c=0.0 / --preserve-screen-border):
bash /workspace/scripts/render-full.sh /workspace/input/gary_moore.mp4 \
     /workspace/output/Gary_Moore_iw3_MAX_border_FULL.mp4

# Выгрузка в S3 (без прокси!, одиночный put_object):
bash /workspace/scripts/s3-put.sh /workspace/output/Gary_Moore_iw3_MAX_border_FULL.mp4 \
     output/Gary_Moore_iw3_MAX_border_FULL.mp4
```

Параметры эталона и все A/B — `memory/iw3-samples.md`. Проверенные цифры: 7680×2160 HEVC Main10 + AAC, `crf=12 / preset=p7`, ~5.7 FPS на RTX 4060 Ti, 11 005 кадров за 32 мин, файл 2 023 249 613 Б.

## Грабли, учтённые в образе

- `RUN \` + комментарий сразу после `\` → shell склейка съедает команду. Комментарии только между `RUN`.
- `av==19.0.2` требует Python ≥3.12 → Ubuntu 24.04, не 22.04.
- `upload_file()` даже с `multipart_threshold=8TiB` **ретраит** на DagsHub s3proxy для файлов ~2 ГБ; работает одиночный `put_object`. См. `memory/s3-storage.md`.
- `S3_PROXY` из `.s3env` годится только с локали; на сервере его надо `unset`.
- Локально `numpy/torch/cv2` = SIGILL (Turion) — сборка CUDA-образа GPU не требует, но **запускать** всё только на арендованном инстансе.
- Системный ffmpeg в образе нужен только для `ffprobe`/диагностики; кодирует сам PyAV.
