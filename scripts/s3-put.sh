#!/usr/bin/env bash
# Выгрузка результата в DagsHub S3 ПРЯМО С СЕРВЕРА.
# ВАЖНО: снимаем S3_PROXY/HTTP(S)_PROXY — на сервере нет локального прокси
# 127.0.0.1:2080, boto3 иначе упирается в него (memory/s3-storage.md).
# Для файлов >1 ГБ использовать put_object, НЕ upload_file (ретраит на s3proxy).
#
#   bash /workspace/scripts/s3-put.sh /workspace/output/out.mp4 output/out.mp4
set -euo pipefail
FILE="${1:?укажите локальный путь}"
KEY="${2:-output/$(basename "$FILE")}"

set -a
source /workspace/.s3env
set +a
unset S3_PROXY HTTP_PROXY HTTPS_PROXY http_proxy https_proxy

/workspace/venv/bin/python - "$FILE" "$KEY" <<'PY'
import os, sys, boto3
path, key = sys.argv[1], sys.argv[2]
s = boto3.client("s3",
    endpoint_url=os.environ["S3_ENDPOINT"],
    region_name=os.environ["AWS_DEFAULT_REGION"],
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"])
with open(path, "rb") as f:
    s.put_object(Bucket=os.environ["S3_BUCKET"], Key=key, Body=f,
                 ContentLength=os.path.getsize(path))
h = s.head_object(Bucket=os.environ["S3_BUCKET"], Key=key)
print("S3_OK", key, h["ContentLength"])
PY
