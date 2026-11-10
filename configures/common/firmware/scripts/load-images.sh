#!/bin/bash

# 本脚本运行的前提条件：
#   1. linux机器
#   2. 安装了docker
#
# 从目录加载镜像, 目录结构与远程web服务器存储结构同构:
#   ${LOAD_DIR}/${arch}/${short-name}/${short-name}-${tag}.tar

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

LOAD_DIR="./images"
arch=""

function usage() {
    echo "usage: load-images.sh [options]"
    echo "  load SHENMA images from <LOAD_DIR>"
    echo "options:"
    echo "  [-l <LOAD_DIR>]        - 从该目录加载镜像 (默认: ./images)"
    echo "  [-a|--arch <ARCH>]     - 目标平台架构 (amd64/arm64), 不指定时自动检测当前平台"
    echo "  [-h]                   - 显示帮助信息"
    echo "examples:"
    echo "  load-images.sh -l ./images"
    echo "  load-images.sh -l ./images -a amd64"
}

# 使用getopt解析参数
TEMP=$(getopt -o l:a:h --long load-dir:,arch:,help -n "$0" -- "$@")
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
        -a|--arch)
            arch="$2"
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
    log "ERROR" "无法自动检测系统架构, 请使用 --arch 指定 (支持: amd64, arm64)"
    exit 1
fi

echo LOAD_DIR = ${LOAD_DIR}
echo ARCH     = ${arch}

function load_images() {
    local dir="${LOAD_DIR}/${arch}"
    if [ ! -d "${dir}" ]; then
        log "WARN" "镜像目录不存在: ${dir}"
        return 0
    fi

    local found=0
    while IFS= read -r image; do
        [ -z "${image}" ] && continue
        found=1
        echo "docker load -i ${image}"
        docker load -i ${image}
    done < <(find "${dir}" -type f -name '*.tar')

    if [ ${found} -eq 0 ]; then
        log "WARN" "目录中未找到镜像文件: ${dir}"
    fi
}

load_images
