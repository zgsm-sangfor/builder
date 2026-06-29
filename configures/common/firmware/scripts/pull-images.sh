#!/bin/bash

# 本脚本运行的前提条件：
#   1. linux机器
#   2. 安装了docker
#

IMAGE_LIST_FILE=""
IMAGE_LIST_STR=""
PROXY=""

function usage() {
    echo "usage: pull-images.sh [options]"
    echo "  pull SHENMA images"
    echo "options:"
    echo "  [-i <IMAGE_LIST_STR>]  - 镜像列表,需将该列表中的所有镜像保存到指定的目录下"
    echo "  [-f <IMAGE_LIST_FILE>] - 镜像列表文件,需将把该文件中指定的镜像保存到指定目录下"
    echo "  [--proxy <PROXY>]      - 代理站点,如 hub.dbin.site, 拉取时通过代理站点下载并 tag 回原始镜像名"
    echo "examples:"
    echo "  pull-images.sh -f .images.list"
    echo "  pull-images.sh -f .images.list --proxy hub.dbin.site"
}

# 解析 --proxy 长选项（在 getopts 之前处理）
while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy)
            PROXY="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

while getopts ":i:f:s:" opt
do
    case $opt in
    i)
        IMAGE_LIST_STR=$OPTARG
        ;;
    f)
        IMAGE_LIST_FILE=$OPTARG
        ;;
    ?)
        usage
        exit 1;;
    esac
done

echo IMAGE_LIST_STR  = ${IMAGE_LIST_STR}
echo IMAGE_LIST_FILE = ${IMAGE_LIST_FILE}
echo PROXY          = ${PROXY}

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
                echo "docker pull ${PROXY}/${image}"
                docker pull ${PROXY}/${image}
                echo "docker tag ${PROXY}/${image} ${image}"
                docker tag ${PROXY}/${image} ${image}
            else
                echo "docker pull ${image}"
                docker pull ${image}
            fi
        fi
    done
}

pull_images
