#!/bin/bash

#
#   在本地启动一个nginx，构建一个可供下载包的站点
#   设置cloud地址为http://localhost即可通过该站点更新软件
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$(pwd)"
IMAGES_BASE="${IMAGES_BASE:-${SCRIPT_DIR}/../images}"

# 依据宿主机 CPU 架构选择 nginx 镜像。
# 离线包中的 nginx 镜像按架构分别提供，若加载到异构架构镜像会导致：
#   exec /docker-entrypoint.sh: exec format error
case "$(uname -m)" in
    x86_64)        NGINX_ARCH="amd64" ;;
    aarch64|arm64) NGINX_ARCH="arm64" ;;
    *)             NGINX_ARCH="" ;;
esac

STATIC_DIR="${SCRIPT_DIR}/../costrict-static"

# 候选镜像包，按优先级排列：优先按架构命名，兼容回退到旧的单架构文件名
CANDIDATE_TARS=()
[ -n "${NGINX_ARCH}" ] && CANDIDATE_TARS+=("${STATIC_DIR}/nginx-1.31.1-${NGINX_ARCH}.tar")
CANDIDATE_TARS+=("${STATIC_DIR}/nginx-1.31.1.tar")
[ -n "${NGINX_ARCH}" ] && CANDIDATE_TARS+=("${IMAGES_BASE}/${NGINX_ARCH}/nginx/nginx-1.31.1.tar")
CANDIDATE_TARS+=("${IMAGES_BASE}/nginx/nginx-1.31.1.tar")

service docker start

loaded=false
for tar in "${CANDIDATE_TARS[@]}"; do
    if [ -f "${tar}" ] && docker load -i "${tar}"; then
        loaded=true
        break
    fi
done

if [ "${loaded}" != true ]; then
    echo "错误: 未找到可用的 nginx 镜像包 (架构: ${NGINX_ARCH:-unknown})" >&2
    exit 1
fi

docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d

