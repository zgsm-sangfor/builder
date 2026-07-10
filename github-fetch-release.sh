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

# 标记是否由脚本自动生成的URL（用于后续判断是否需要尝试API回退）
AUTO_GENERATED_URL=false

# 如果未指定URL，则自动拼接
if [ -z "$PACKAGE_URL" ]; then
    AUTO_GENERATED_URL=true
    PACKAGE_URL="https://github.com/${PACKAGE_REPO}/releases/download/v${PACKAGE_VERSION}/${PACKAGE_NAME}-${PACKAGE_OS}-${PACKAGE_ARCH}-v${PACKAGE_VERSION}"
    if [ "$PACKAGE_OS" = "windows" ]; then
        PACKAGE_URL="${PACKAGE_URL}.exe"
    fi
fi

#
# 通过 GitHub API 查询 Release 中匹配 OS/ARCH 的资产 API URL
# 说明：返回 API URL（如 https://api.github.com/repos/.../releases/assets/123）
#       而非 browser_download_url，因为私有仓库的 browser_download_url
#       会重定向到 objects.githubusercontent.com，跨主机重定向时 curl
#       会剥离 Authorization 头导致 404。
#       使用 API URL 下载（同主机重定向）可保留认证头。
# 参数: repo, version, os, arch, package
# 返回: 匹配的资产 API URL（url 字段），若未找到则返回空字符串
#
fetch_release_asset_api_url() {
    local repo="$1"
    local version="$2"
    local target_os="$3"
    local target_arch="$4"
    local target_package="$5"

    local api_url="https://api.github.com/repos/${repo}/releases/tags/v${version}"
    local auth_header=""
    if [ -n "${GH_TOKEN}" ]; then
        auth_header="Authorization: Bearer ${GH_TOKEN}"
    elif [ -n "${GITHUB_TOKEN}" ]; then
        auth_header="Authorization: Bearer ${GITHUB_TOKEN}"
    fi

    # 调用 GitHub API 获取 release 信息
    local api_response
    if [ -n "${auth_header}" ]; then
        api_response=$(curl -sfL -H "${auth_header}" "${api_url}" 2>/dev/null)
    else
        api_response=$(curl -sfL "${api_url}" 2>/dev/null)
    fi

    if [ $? -ne 0 ] || [ -z "$api_response" ]; then
        return 1
    fi

    # 从 assets 数组中查找匹配的资产，返回 API url 字段（非 browser_download_url）
    # 匹配规则：资产文件名中同时包含 package 名称、os 和 arch（不区分大小写）
    local asset_url
    asset_url=$(echo "$api_response" | jq -r --arg pkg "$target_package" --arg os "$target_os" --arg arch "$target_arch" \
        '.assets[] | select(.name | ascii_downcase | (contains($pkg) and contains($os) and contains($arch))) | .url' 2>/dev/null | head -1)

    if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
        return 1
    fi

    echo "$asset_url"
    return 0
}

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
# 说明：
#   - 公共仓库：直接用 browser_download_url 下载（无需认证）
#   - 私有仓库：必须通过 GitHub API 资产端点下载，因为 browser_download_url
#     会重定向到 objects.githubusercontent.com，跨主机重定向时 curl 会剥离
#     Authorization 头，导致 404。API 端点（api.github.com）同主机重定向保留认证头。
do_download_direct() {
    local url="$1"
    local output="$2"

    if [ -n "${GH_TOKEN}" ]; then
        curl -fSL -H "Authorization: Bearer ${GH_TOKEN}" -o "${output}" "${url}"
    elif [ -n "${GITHUB_TOKEN}" ]; then
        curl -fSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -o "${output}" "${url}"
    else
        curl -fSL -o "${output}" "${url}"
    fi
}

# 通过 GitHub API 资产端点下载（适用于私有仓库）
# API URL 格式: https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}
# 需要设置 Accept: application/octet-stream 以获取二进制内容
do_download_api() {
    local api_url="$1"
    local output="$2"

    if [ -n "${GH_TOKEN}" ]; then
        curl -fSL -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/octet-stream" -o "${output}" "${api_url}"
    elif [ -n "${GITHUB_TOKEN}" ]; then
        curl -fSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/octet-stream" -o "${output}" "${api_url}"
    else
        curl -fSL -H "Accept: application/octet-stream" -o "${output}" "${api_url}"
    fi
}

#
# 下载策略：
#   1. 优先尝试直接 URL（适合公共仓库或 URL 由用户通过 --url 显式指定）
#   2. 若失败且 URL 是自动生成的，通过 GitHub API 获取资产 API URL 重试
#      （API URL 重定向在 api.github.com 同主机内，认证头不会丢失）
#
do_download_direct "${PACKAGE_URL}" "${TARGET_FILE}"
DOWNLOAD_EXIT_CODE=$?

if [ $DOWNLOAD_EXIT_CODE -ne 0 ] && [ "$AUTO_GENERATED_URL" = true ]; then
    echo "Direct URL failed, trying GitHub API to discover asset..."
    ASSET_API_URL=$(fetch_release_asset_api_url "$PACKAGE_REPO" "$PACKAGE_VERSION" "$PACKAGE_OS" "$PACKAGE_ARCH" "$PACKAGE_NAME")
    if [ $? -eq 0 ] && [ -n "$ASSET_API_URL" ]; then
        echo "Found asset API URL: ${ASSET_API_URL}"
        do_download_api "${ASSET_API_URL}" "${TARGET_FILE}"
        DOWNLOAD_EXIT_CODE=$?
    else
        echo "Warning: Could not find matching asset via GitHub API for ${PACKAGE_NAME} (os=${PACKAGE_OS}, arch=${PACKAGE_ARCH})"
    fi
fi

if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to download from: ${PACKAGE_URL}"
    rm -f "${TARGET_FILE}"
    exit 1
fi

# 设置可执行权限
chmod +x "${TARGET_FILE}" 2>/dev/null

echo ""
echo "Successfully downloaded: ${TARGET_FILE}"
exit 0
