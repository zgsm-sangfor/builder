#!/bin/bash

# 本脚本运行的前提条件：
#   1. linux机器
#   2. 安装了docker
#
# 镜像目录结构与远程web服务器存储结构同构:
#   ${LOAD_DIR}/${arch}/${short-name}/${short-name}-${tag}.tar

# 从.env文件读取配置
if [ -f "$(dirname "$0")/.env" ]; then
    # shellcheck disable=SC1090
    source "$(dirname "$0")/.env"
else
    echo "Error: .env file not found in $(dirname "$0")"
    exit 1
fi

LOAD_DIR="./images"
arch=""
SPECIFIC_FILE=""

function usage() {
    echo "Usage: push-images.sh [options]"
    echo "Push docker images to Harbor registry"
    echo ""
    echo "Options:"
    echo "  -l <LOAD_DIR>    Load all images from directory (default: ./images)"
    echo "  -f <IMAGE_FILE>  Push specific image file"
    echo "  -a|--arch <ARCH> Target platform arch (amd64/arm64), auto-detect if omitted"
    echo "  -s <HOST>        Harbor host (default: harbor.sangfor.com)"
    echo "  -r <REPO>        Harbor repository (default: zgsm)"
    echo "  -u <USER>        Harbor username (default: admin)"
    echo "  -p <PASS>        Harbor password (default: )"
    echo "  -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Push all images for detected arch from directory"
    echo "  push-images.sh -l ./images"
    echo ""
    echo "  # Push all images for a specific arch"
    echo "  push-images.sh -l ./images -a amd64"
    echo ""
    echo "  # Push single image file"
    echo "  push-images.sh -f ./images/amd64/nginx/nginx-1.27.1.tar"
    echo ""
    echo "  # Customize Harbor parameters"
    echo "  push-images.sh -l ./images -s myharbor.com -u myuser"
}

# 使用getopt解析参数
TEMP=$(getopt -o l:f:s:r:u:p:a:h --long load-dir:,file:,host:,repo:,user:,pass:,arch:,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    usage
    exit 1
fi
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -l|--load-dir)
            LOAD_DIR="$2"
            shift 2
            ;;
        -f|--file)
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        -a|--arch)
            arch="$2"
            shift 2
            ;;
        -s|--host)
            DH_HOST="$2"
            shift 2
            ;;
        -r|--repo)
            DH_REPO="$2"
            shift 2
            ;;
        -u|--user)
            DH_USER="$2"
            shift 2
            ;;
        -p|--pass)
            DH_PASS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --) shift ; break ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# 解析目标平台架构: 优先使用 --arch 指定值, 未指定则自动检测 (支持 amd64/arm64)
if [ -z "$arch" ]; then
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) arch="" ;;
    esac
fi
if [ -z "$arch" ]; then
    echo "Error: 无法自动检测系统架构, 请使用 --arch 指定 (支持: amd64, arm64)"
    exit 1
fi

echo LOAD_DIR = ${LOAD_DIR}
echo ARCH     = ${arch}

function push_images() {
    docker login "$DH_HOST" --username "$DH_USER" --password "$DH_PASS"

    if [ -n "$SPECIFIC_FILE" ]; then
        # 上传单个指定文件
        push_single_image "$SPECIFIC_FILE"
    else
        # 上传目录下所有文件 (目录结构: ${LOAD_DIR}/${arch}/${short-name}/*.tar)
        local image_dir="${LOAD_DIR}/${arch}"
        if [ ! -d "${image_dir}" ]; then
            echo "Error: 镜像目录不存在: ${image_dir}"
            exit 1
        fi
        while IFS= read -r image; do
            [ -z "${image}" ] && continue
            push_single_image "$image"
        done < <(find "${image_dir}" -type f -name '*.tar')
    fi
}

function push_single_image() {
    local image=$1
    
    # 执行 docker load 命令并捕获输出
    output=$(docker load -i "$image" 2>&1)

    # 检查命令是否成功执行
    if echo "$output" | grep -q "Loaded image:"; then
        # 提取镜像名和TAG
        IMAGE=$(echo "$output" | grep "Loaded image:" | awk '{print $3}')
        IMAGE_NAME=$(basename "$IMAGE" | cut -d: -f1)  # 获取镜像名最后一段
        IMAGE_TAG=$(basename "$IMAGE" | cut -d: -f2)   # 获取tag

        echo "docker tag $IMAGE $DH_HOST/$DH_REPO/$IMAGE_NAME:$IMAGE_TAG ..."
        docker tag "$IMAGE" "$DH_HOST/$DH_REPO/$IMAGE_NAME:$IMAGE_TAG"

        echo "Push image to $DH_HOST/$DH_REPO/$IMAGE_NAME:$IMAGE_TAG ..."
        docker push "$DH_HOST/$DH_REPO/$IMAGE_NAME:$IMAGE_TAG"

        echo "Push image to $DH_HOST/$DH_REPO/$IMAGE_NAME:latest"
        docker tag "$IMAGE" "$DH_HOST/$DH_REPO/$IMAGE_NAME:latest"
        docker push "$DH_HOST/$DH_REPO/$IMAGE_NAME:latest"
    else
        # 输出错误信息
        echo "Error loading image: $output"
        exit 1
    fi
}

push_images
