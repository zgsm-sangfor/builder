#!/bin/bash

#
# github-fetch-release.sh - 从GitHub下载指定版本的release
#
# 功能：
#   从GitHub Release页面下载指定平台(OS/ARCH)和版本的二进制发布包，
#   保存到 packages/{package}/{os}/{arch}/{version}/ 目录下。
#
# 选项说明：
#   --os <OS>            操作系统（必填），如 linux, darwin, windows
#   --arch <ARCH>        架构（必填），如 amd64, arm64
#   --version <VERSION>  版本号（必填）
#   --package <NAME>     包名称（必填），如 costrict-admin
#   --repo <REPO>        GitHub仓库名（可选），默认: zgsm-sangfor/<package>
#   --url <URL>          GitHub Release下载URL（可选），默认自动拼接
#   --output-dir <DIR>   输出根目录（可选），默认: ../packages
#   --output <FILE>      输出文件路径（可选），默认: 自动拼接到 {output-dir}/{package}/{os}/{arch}/{version}/{package}
#   -h, --help           显示帮助信息
#
# 使用示例：
#   ./github-fetch-release.sh --os linux --arch amd64 --version 1.0.133 --package costrict-admin
#   ./github-fetch-release.sh --os darwin --arch arm64 --version 1.0.1 --package costrict-model-proxy --repo zgsm-sangfor/costrict-model-proxy
#   ./github-fetch-release.sh --os linux --arch amd64 --version 1.0.133 --package costrict-admin --url https://github.com/zgsm-sangfor/costrict-admin/releases/download/v1.0.133/costrict-admin-linux-amd64-v1.0.133
#

usage() {
    echo "Usage: github-fetch-release.sh [OPTIONS]"
    echo ""
    echo "从GitHub下载指定版本的release发布包。"
    echo ""
    echo "Options:"
    echo "  --os <OS>            操作系统（必填），如 linux, darwin, windows"
    echo "  --arch <ARCH>        架构（必填），如 amd64, arm64"
    echo "  --version <VERSION>  版本号（必填）"
    echo "  --package <NAME>     包名称（必填），如 costrict-admin"
    echo "  --repo <REPO>        GitHub仓库名（可选），默认: zgsm-sangfor/<package>"
    echo "  --url <URL>          GitHub Release下载URL（可选），默认自动拼接"
    echo "  --output-dir <DIR>   输出根目录（可选），默认: ../packages"
    echo "  --output <FILE>      输出文件路径（可选），默认: {output-dir}/{package}/{os}/{arch}/{version}/{package}"
    echo "  -h, --help           显示帮助信息"
    echo ""
    echo "Examples:"
    echo "  github-fetch-release.sh --os linux --arch amd64 --version 1.0.133 --package costrict-admin"
    echo "  github-fetch-release.sh --os darwin --arch arm64 --version 1.0.1 --package costrict-model-proxy --repo zgsm-sangfor/costrict-model-proxy"
    exit 1
}

# 默认参数值
PACKAGE_OS=""
PACKAGE_ARCH=""
PACKAGE_VERSION=""
PACKAGE_NAME=""
PACKAGE_REPO=""
PACKAGE_URL=""
OUTPUT_DIR="./packages"
OUTPUT_FILE=""

# 解析命令行选项
args=$(getopt -o h --long help,os:,arch:,version:,package:,repo:,url:,output-dir:,output: -n 'github-fetch-release.sh' -- "$@")
if [ $? -ne 0 ]; then
    usage
fi

eval set -- "$args"

while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --os)
            PACKAGE_OS="$2"
            shift 2
            ;;
        --arch)
            PACKAGE_ARCH="$2"
            shift 2
            ;;
        --version)
            PACKAGE_VERSION="$2"
            shift 2
            ;;
        --package)
            PACKAGE_NAME="$2"
            shift 2
            ;;
        --repo)
            PACKAGE_REPO="$2"
            shift 2
            ;;
        --url)
            PACKAGE_URL="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            usage
            ;;
    esac
done

# 验证必填参数
if [ -z "$PACKAGE_OS" ]; then
    echo "Error: --os is required."
    usage
fi

if [ -z "$PACKAGE_ARCH" ]; then
    echo "Error: --arch is required."
    usage
fi

if [ -z "$PACKAGE_VERSION" ]; then
    echo "Error: --version is required."
    usage
fi

if [ -z "$PACKAGE_NAME" ]; then
    echo "Error: --package is required."
    usage
fi

# 设置默认repo
if [ -z "$PACKAGE_REPO" ]; then
    PACKAGE_REPO="zgsm-sangfor/${PACKAGE_NAME}"
fi

# 如果未指定URL，则自动拼接
if [ -z "$PACKAGE_URL" ]; then
    PACKAGE_URL="https://github.com/${PACKAGE_REPO}/releases/download/v${PACKAGE_VERSION}/${PACKAGE_NAME}-${PACKAGE_OS}-${PACKAGE_ARCH}-v${PACKAGE_VERSION}"
    if [ "$PACKAGE_OS" = "windows" ]; then
        PACKAGE_URL="${PACKAGE_URL}.exe"
    fi
fi

# 构建目标路径（Windows平台追加 .exe 后缀）
if [ -z "$OUTPUT_FILE" ]; then
    TARGET_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}/${PACKAGE_OS}/${PACKAGE_ARCH}/${PACKAGE_VERSION}"
    TARGET_FILE="${TARGET_DIR}/${PACKAGE_NAME}"
    if [ "$PACKAGE_OS" = "windows" ]; then
        TARGET_FILE="${TARGET_FILE}.exe"
    fi
else
    TARGET_FILE="$OUTPUT_FILE"
    TARGET_DIR=$(dirname "$TARGET_FILE")
fi

echo "============================================"
echo "Fetching GitHub Release"
echo "============================================"
echo "  Package : ${PACKAGE_NAME}"
echo "  Version : ${PACKAGE_VERSION}"
echo "  OS      : ${PACKAGE_OS}"
echo "  Arch    : ${PACKAGE_ARCH}"
echo "  Repo    : ${PACKAGE_REPO}"
echo "  URL     : ${PACKAGE_URL}"
echo "  Target  : ${TARGET_FILE}"
echo "============================================"

# 创建目标目录
mkdir -p "${TARGET_DIR}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create directory: ${TARGET_DIR}"
    exit 1
fi

# 下载release文件
# 优先使用 GH_TOKEN 或 GITHUB_TOKEN 环境变量进行认证（支持私有仓库）
AUTH_HEADER=""
if [ -n "${GH_TOKEN}" ]; then
    AUTH_HEADER="-H \"Authorization: Bearer ${GH_TOKEN}\""
elif [ -n "${GITHUB_TOKEN}" ]; then
    AUTH_HEADER="-H \"Authorization: Bearer ${GITHUB_TOKEN}\""
fi

if [ -n "${AUTH_HEADER}" ]; then
    eval curl -fSL ${AUTH_HEADER} -o "\"${TARGET_FILE}\"" "\"${PACKAGE_URL}\""
else
    curl -fSL -o "${TARGET_FILE}" "${PACKAGE_URL}"
fi
if [ $? -ne 0 ]; then
    echo "Error: Failed to download from: ${PACKAGE_URL}"
    rm -f "${TARGET_FILE}"
    exit 1
fi

# 设置可执行权限
chmod +x "${TARGET_FILE}" 2>/dev/null

echo ""
echo "Successfully downloaded: ${TARGET_FILE}"
exit 0
