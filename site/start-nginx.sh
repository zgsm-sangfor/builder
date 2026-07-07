#!/bin/bash

#
#   在本地启动一个nginx，构建一个可供下载包的站点
#   设置cloud地址为http://localhost即可通过该站点更新软件
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$(pwd)"
IMAGES_BASE="${IMAGES_BASE:-${SCRIPT_DIR}/../images}"
service docker start
docker load -i ${SCRIPT_DIR}/../costrict-static/nginx-1.27.1.tar || docker load -i ${IMAGES_BASE}/nginx/nginx-1.27.1.tar
docker compose up -d

