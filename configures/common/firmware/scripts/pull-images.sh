#!/bin/bash

# 本脚本运行的前提条件：
#   1. linux机器
#   2. 安装了docker
#

IMAGE_LIST_FILE=""
IMAGE_LIST_STR=""
PROXY=""
arch=""

function usage() {
    echo "usage: pull-images.sh [options]"
    echo "  pull SHENMA images"
    echo "options:"
    echo "  [-i <IMAGE_LIST_STR>]  - 镜像列表,需将该列表中的所有镜像保存到指定的目录下"
    echo "  [-f <IMAGE_LIST_FILE>] - 镜像列表文件,需将把该文件中指定的镜像保存到指定目录下"
    echo "  [-a|--arch <ARCH>]     - 目标平台架构 (amd64/arm64), 不指定时自动检测当前平台"
    echo "  [--proxy <PROXY>]      - 代理站点,如 hub.dbin.site, 拉取时通过代理站点下载并 tag 回原始镜像名"
    echo "examples:"
    echo "  pull-images.sh -f .images.list"
    echo "  pull-images.sh -f .images.list --proxy hub.dbin.site"
    echo "  pull-images.sh -f .images.list -a arm64"
}

# 使用getopt解析参数
TEMP=$(getopt -o i:f:a:h --long images:,file:,arch:,proxy:,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    usage
    exit 1
fi
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -i|--images)
            IMAGE_LIST_STR="$2"
            shift 2
            ;;
        -f|--file)
            IMAGE_LIST_FILE="$2"
            shift 2
            ;;
        -a|--arch)
            arch="$2"
            shift 2
            ;;
        --proxy)
            PROXY="$2"
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

echo IMAGE_LIST_STR  = ${IMAGE_LIST_STR}
echo IMAGE_LIST_FILE = ${IMAGE_LIST_FILE}
echo PROXY          = ${PROXY}
echo ARCH           = ${arch}

IMAGES=""
if [ "${IMAGE_LIST_STR}" != "" ]; then
    IMAGES="${IMAGE_LIST_STR}"
fi

if [ "${IMAGE_LIST_FILE}" != "" ]; then
    IMAGES=`cat ${IMAGE_LIST_FILE}`
fi

function pull_images() {
    for image in `echo ${IMAGES}`; do
        # 检查镜像是否存在，使用与 verify-images.sh 相同的方式
        image_id=$(docker image inspect "${image}" --format='{{.Id}}' 2> /dev/null)
        if [ -n "${image_id}" ]; then
            echo "镜像 ${image} 已存在，跳过拉取"
        else
            if [ -n "${PROXY}" ]; then
                echo "docker pull --platform linux/${arch} ${PROXY}/${image}"
                docker pull --platform "linux/${arch}" ${PROXY}/${image}
                echo "docker tag ${PROXY}/${image} ${image}"
                docker tag ${PROXY}/${image} ${image}
            else
                echo "docker pull --platform linux/${arch} ${image}"
                docker pull --platform "linux/${arch}" ${image}
            fi
        fi
    done
}

pull_images
