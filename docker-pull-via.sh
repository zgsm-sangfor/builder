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
#   --os <OS>          目标平台操作系统（可选：linux/darwin），未指定时自动检测
#   --arch <ARCH>      目标平台架构（可选：amd64/arm64），未指定时自动检测
#   -h, --help         显示帮助信息
#
# 说明：
#   --os 与 --arch 用于 docker pull 的 --platform 参数，拼接格式为 "${os}/${arch}"。
#
# 使用示例：
#   ./docker-pull-via.sh --proxy-id ghcr.io/user/app:v1.0 --image-id docker.io/user/app:v1.0
#   ./docker-pull-via.sh --proxy-id zgsm/one-api:v1.0.4 --image-id zgsm/one-api:v1.0.4
#   ./docker-pull-via.sh --proxy-id ghcr.io/user/app:v1.0 --image-id docker.io/user/app:v1.0 --os linux --arch arm64
#

usage() {
    echo "Usage: docker-pull-via.sh [OPTIONS]"
    echo "Options:"
    echo "  --image-id <ID>    tag后的目标镜像ID（必填），格式如 repo/name:tag"
    echo "  --proxy-id <ID>    docker pull直接拉取的代理镜像ID（必填），格式如 repo/name:tag"
    echo "  --os <OS>          目标平台操作系统（可选：linux/darwin），未指定时自动检测"
    echo "  --arch <ARCH>      目标平台架构（可选：amd64/arm64），未指定时自动检测"
    echo "  -h, --help         显示帮助信息"
    echo ""
    echo "Examples:"
    echo "  ./docker-pull-via.sh --proxy-id ghcr.io/user/app:v1.0 --image-id docker.io/user/app:v1.0"
    echo "  ./docker-pull-via.sh --proxy-id zgsm/one-api:v1.0.4 --image-id zgsm/one-api:v1.0.4"
    echo "  ./docker-pull-via.sh --proxy-id ghcr.io/user/app:v1.0 --image-id docker.io/user/app:v1.0 --os linux --arch arm64"
    exit 1
}

# 默认参数值
IMAGE_ID=""
PROXY_ID=""
OS=""
ARCH=""

# 解析命令行选项
args=$(getopt -o h --long help,image-id:,proxy-id:,os:,arch: -n 'docker-pull-via.sh' -- "$@")
[ $? -ne 0 ] && usage

eval set -- "$args"

while true; do
    case "$1" in
        -h|--help) usage; exit 0;;
        --image-id) IMAGE_ID="$2"; shift 2;;
        --proxy-id) PROXY_ID="$2"; shift 2;;
        --os) OS="$2"; shift 2;;
        --arch) ARCH="$2"; shift 2;;
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

# =============================================
# 解析目标平台（os/arch）
# =============================================
# 解析目标 OS: 优先使用 --os 指定值, 未指定则自动检测 (支持: linux, darwin)
if [ -z "$OS" ]; then
    case "$(uname -s)" in
        Linux)  OS="linux" ;;
        Darwin) OS="darwin" ;;
        *)      OS="" ;;
    esac
fi
case "$OS" in
    linux|darwin) ;;
    "")
        echo "Error: 无法自动检测操作系统, 请使用 --os 指定 (支持: linux, darwin)"
        exit 1
        ;;
    *)
        echo "Error: 不支持的 --os 取值: $OS (支持: linux, darwin)"
        exit 1
        ;;
esac

# 解析目标架构: 优先使用 --arch 指定值, 未指定则自动检测 (支持: amd64, arm64)
if [ -z "$ARCH" ]; then
    case "$(uname -m)" in
        x86_64|amd64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)             ARCH="" ;;
    esac
fi
case "$ARCH" in
    amd64|arm64) ;;
    "")
        echo "Error: 无法自动检测系统架构, 请使用 --arch 指定 (支持: amd64, arm64)"
        exit 1
        ;;
    *)
        echo "Error: 不支持的 --arch 取值: $ARCH (支持: amd64, arm64)"
        exit 1
        ;;
esac

PLATFORM="${OS}/${ARCH}"

echo "=============================================="
echo "Proxy Image ID:  $PROXY_ID"
echo "Target Image ID: $IMAGE_ID"
echo "Platform:        $PLATFORM"
echo "=============================================="

# =============================================
# Pull 代理镜像到本地
# =============================================
echo ""
echo ">>> Pulling image: $PROXY_ID (platform: $PLATFORM) ..."
docker pull --platform "$PLATFORM" "$PROXY_ID"
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
