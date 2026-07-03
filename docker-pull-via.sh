#!/bin/bash

#
# docker-pull-via.sh - 通过代理镜像拉取并tag为目标镜像
#
# 功能：
#   从 --proxy-id 指定的镜像地址拉取镜像，然后将其 tag 为 --image-id 指定的目标镜像名。
#   适用于 github action 自动构建并推送到 docker hub/ghcr.io 的场景，
#   通过代理地址拉取后 tag 为本地使用的镜像名。
#
# 选项说明：
#   --image-id <ID>    tag后的目标镜像ID（必填），格式如 repo/name:tag
#   --proxy-id <ID>    docker pull直接拉取的代理镜像ID（必填），格式如 repo/name:tag
#   -h, --help         显示帮助信息
#
# 使用示例：
#   ./docker-pull-via.sh --proxy-id ghcr.io/user/app:v1.0 --image-id docker.io/user/app:v1.0
#   ./docker-pull-via.sh --proxy-id zgsm/one-api:v1.0.4 --image-id zgsm/one-api:v1.0.4
#

usage() {
    echo "Usage: docker-pull-via.sh [OPTIONS]"
    echo "Options:"
    echo "  --image-id <ID>    tag后的目标镜像ID（必填），格式如 repo/name:tag"
    echo "  --proxy-id <ID>    docker pull直接拉取的代理镜像ID（必填），格式如 repo/name:tag"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "Examples:"
    echo "  ./docker-pull-via.sh --proxy-id ghcr.io/user/app:v1.0 --image-id docker.io/user/app:v1.0"
    echo "  ./docker-pull-via.sh --proxy-id zgsm/one-api:v1.0.4 --image-id zgsm/one-api:v1.0.4"
    exit 1
}

# 默认参数值
IMAGE_ID=""
PROXY_ID=""

# 解析命令行选项
args=$(getopt -o h --long help,image-id:,proxy-id: -n 'docker-pull-via.sh' -- "$@")
[ $? -ne 0 ] && usage

eval set -- "$args"

while true; do
    case "$1" in
        -h|--help) usage; exit 0;;
        --image-id) IMAGE_ID="$2"; shift 2;;
        --proxy-id) PROXY_ID="$2"; shift 2;;
        --) shift; break;;
        *) usage;;
    esac
done

# 检查必填参数
if [ -z "$IMAGE_ID" ]; then
    echo "Error: --image-id is required!"
    usage
fi

if [ -z "$PROXY_ID" ]; then
    echo "Error: --proxy-id is required!"
    usage
fi

# 检查docker命令是否可用
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker command not found! Please install Docker."
    exit 1
fi

echo "=============================================="
echo "Proxy Image ID:  $PROXY_ID"
echo "Target Image ID: $IMAGE_ID"
echo "=============================================="

# =============================================
# Pull 代理镜像到本地
# =============================================
echo ""
echo ">>> Pulling image: $PROXY_ID ..."
docker pull "$PROXY_ID"
if [ $? -ne 0 ]; then
    echo "Error: Failed to pull image $PROXY_ID"
    exit 1
fi
echo "Successfully pulled image: $PROXY_ID"

# =============================================
# Tag 为目标镜像名
# =============================================
if [ "$PROXY_ID" != "$IMAGE_ID" ]; then
    echo ""
    echo ">>> Tagging image: $PROXY_ID -> $IMAGE_ID ..."
    docker tag "$PROXY_ID" "$IMAGE_ID"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to tag image $PROXY_ID as $IMAGE_ID"
        exit 1
    fi
    echo "Successfully tagged image as $IMAGE_ID"
else
    echo ""
    echo ">>> Proxy ID and Image ID are the same, skipping tag step."
fi

echo ""
echo "Done. Image '$IMAGE_ID' is ready."

exit 0
