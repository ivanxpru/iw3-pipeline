# iw3-pipeline

Самодостаточный Docker-образ для **nagadomi/nunif `iw3`** (2D → Full SBS 3D, HEVC Main10). Отдельный репозиторий по образцу `v2d-pipeline/` — старый [`docker/Dockerfile`](../docker/Dockerfile) (DA3 + self-written Z-buffer) **не трогаем**.

## Что внутри

| | |
|---|---|
| База | `nvidia/cuda:12.6.3-base-ubuntu24.04` (85.6 МБ) → Ubuntu 24.04, **Python 3.12.3** |
| Стек | `torch==2.14.1+cu126` / `torchvision==0.29.1+cu126`, `av==19.0.2` (PyAV со встроенными `hevc_nvenc`/`libx265`), `timm`, `boto3` |
| Код | `nunif` с пином коммита `b1548e8ff08758f336cdab14443647318ef5e0e9` (07.11.2026) |
| Модели | DA3MONO-LARGE (~1.34 ГБ), VDA_L (1.54 ГБ), `row_flow_v3`/`v3_sym`/`v2`, `mlbw_*`, `mask_mlbw`, `light_(video_)inpaint`, `depth_aa`, `sod_v1` + все torch.hub-форки. ZoeD_Any_N и Depth Pro УДАЛЕНЫ 11.11.2026 (не используем; Depth Pro при надобности — S3 `s3://v2d-storage/models/depth-pro/depth_pro.pt`) |
| venv | `/opt/venv` → при старте `/workspace/venv` |

**Почему cu126, а не cu132:** CUDA 13.x требует драйвер ≥580.65.06, на офферах Qudata встречается 535.x. cu126 работает с ≥525 и покрывает sm_75/80/86/90.

**Почему `/opt`, а не `/workspace`:** Qudata монтирует volume поверх `/workspace`, всё из слоя образа скрывается. `entrypoint.sh` делает `cp -rn` в `/workspace` и создаёт симлинк `/opt/venv → /workspace/venv` (shebang'ы pip-скриптов указывают на `/opt/venv`).

## NVENC: два обязательных условия

1. **`NVIDIA_DRIVER_CAPABILITIES=all`** — задано в Dockerfile. Базовый образ
   `nvidia/cuda:12.6.3-base-ubuntu24.04` по умолчанию ставит `compute,utility`
   (без `video`); Qudata не всегда переопределяет его на `all`. Без этого
   `/dev/nvidia-encode*` не монтируются и NVENC мёртв даже на драйвере 580.
2. **Драйвер ≥560** — PyAV 19.0.2 несёт FFmpeg 9, который не открывает
   `avcodec_open2("hevc_nvenc")` на 535/550 (`NotImplementedError`), хотя
   системный ffmpeg 6.1 при этом кодирует. `has_nvenc()` в iw3 врёт: он
   проверяет только наличие кодека в `av.codecs_available`.

Проверка сразу после аренды (до установки стека и закачки видео):

```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
echo "$NVIDIA_DRIVER_CAPABILITIES"
python -c "import av; c=av.CodecContext.create('hevc_nvenc','w'); c.width=640; c.height=360; c.pix_fmt='yuv420p'; c.open(); print('NVENC OK')"
```

Не выполняется хотя бы одно → гасить инстанс и брать другой оффер.

## Сборка

Правки в `Dockerfile` попадают на инстансы **только после `git push` в `main`**: workflow `.github/workflows/docker-publish.yml` собирает и пушит `ivanxphub/iw3-pipeline:latest` + `:<sha>` (или `workflow_dispatch`). Локально не собирать — на proliant legacy-builder без buildx тихо умирает. Пока пуша не было, аренда использует прежний образ, и `NVIDIA_DRIVER_CAPABILITIES=all` даёт **только env шаблона**.

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
  name="iw3-pipeline-vda",
  image="ivanxphub/iw3-pipeline", image_tag="latest",
  is_private=true, ssh_enabled=true, ssh_username="root",
  min_storage_gb=50,
  env_variables={"NUNIF_HOME": "/workspace/nunif_home",
                 "NVIDIA_DRIVER_CAPABILITIES": "all",
                 "TORCH_HOME": "/opt/iw3-home/torch_hub"})
```

> **АКТУАЛЬНЫЙ ШАБЛОН (11.11, образ с коммитами `b807bcf`+`1e4f3ee`):
> `iw3-pipeline-v2` = `6af3d629596b1fe98eb52684`** — entrypoint сам:
> mkdir-фикс /opt→/workspace, отключение CUDA-compat на GeForce, авто-патч
> DepthPro video-mode, `scripts/denoise-source.sh` на борту. Аренда = моментальный старт.
> Старые: `iw3-pipeline-depthpro` (`6af13aeb7c9019f1f3a36cfe`), `iw3-pipeline-vda`
> (`6af01a097c9019f1f3a35b59`), `iw3-pipeline` (`6aef20c6b7ade1a05d8750ca`),
> `iw3-pipeline-nvenc` (`6aefd1f8bdea72d60d010ada`).
> Шаблоны Qudata НЕ обновляются автоматически. `NVIDIA_DRIVER_CAPABILITIES=all`

## Depth Pro — удалён из образа (11.11.2026)

Модель отклонена вердиктом пользователя (10–11.11, «края плывущие»), образ
похудел на −1.9 ГБ — из-за него (и ZoeD) развёртывание на Qudata падало по
таймауту ~15 мин. Если когда-нибудь понадобится:

- Веса: S3 `s3://v2d-storage/models/depth-pro/depth_pro.pt` (1 904 446 787 Б;
  `s3-sync.sh env-up` для ключей) — тот же вес, что `apple/DepthPro` на HF
  (открытый репо, gated: false).
- Положить в `/workspace/nunif_home/iw3/pretrained_models/hub/checkpoints/depth_pro.pt`
  (`depth_pro_model.py`). Запуск: `python -m iw3 ... --depth-model DepthPro`
  (без `--resolution` и `--depth-aa`, фикс 1536×1536).
- Скрипт `scripts/download-depthpro.sh` в образе остался — тянет из S3, затем HF.
- Примечание: код ml-depth-pro — MIT; лицензия весов — Apple AMLR.
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
