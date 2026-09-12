#!/bin/bash

#
# github-fetch-release.sh - 从GitHub下载指定版本的release
#
#   从GitHub Release页面下载指定平台(OS/ARCH)和版本的二进制发布包，
#   保存到 packages/{package}/{os}/{arch}/{version}/ 目录下。
#
# 下载方式（官方方法优先）：
#   1. 优先使用官方 GitHub CLI（gh release download）——自动处理私有仓库认证，
#      与 local-build.sh 保持一致；若系统未安装 gh，则自动下载官方二进制并复用
#      （可用 GH_FETCH_NO_BOOTSTRAP=1 禁用该自动下载）；
#   2. 无 gh 或 gh 失败时回退到 curl 直连 URL，再回退到 GitHub API 资产端点。
#
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

# 官方方法：使用 GitHub CLI (gh release download) 下载 Release 资产
# 说明：
#   - gh 会自动处理私有仓库认证（基于 `gh auth login` 凭据或 GH_TOKEN/GITHUB_TOKEN 环境变量）；
#   - --pattern 使用资产文件名 glob（形如 {package}-{os}-{arch}-*）定位目标资产；
#   - --output 将匹配到的单个资产写入指定文件，--clobber 覆盖已存在文件。
# 参数: repo, version, os, arch, package, output
do_download_gh() {
    local repo="$1"
    local version="$2"
    local target_os="$3"
    local target_arch="$4"
    local target_package="$5"
    local output="$6"

    "${GH_BIN}" release download "v${version}" \
        --repo "${repo}" \
        --pattern "${target_package}-${target_os}-${target_arch}-*" \
        --output "${output}" \
        --clobber
}

# gh 可执行文件路径（由 ensure_gh 设置；默认回退到 PATH 中的 gh）
GH_BIN="gh"
# 官方 CLI 引导目录：系统未安装 gh 时，自动下载官方二进制并缓存到此目录复用
GH_BOOTSTRAP_DIR="${GH_BOOTSTRAP_DIR:-${HOME:-/tmp}/.cache/costrict/gh-cli}"

# 确保官方 GitHub CLI (gh) 可用（即“如果没有 gh，自动下载”）：
#   1. 系统已安装 gh -> 直接使用；
#   2. 引导目录已缓存官方二进制 -> 复用；
#   3. 否则自动从官方仓库 cli/cli 下载对应平台最新版并解压到引导目录。
# 可通过 GH_FETCH_NO_BOOTSTRAP=1 禁用自动下载。
# 成功返回 0 并设置 GH_BIN；失败返回 1（由调用方回退到 curl）。
ensure_gh() {
    # 1. 系统已安装
    if command -v gh >/dev/null 2>&1; then
        GH_BIN="$(command -v gh)"
        return 0
    fi

    # 2. 引导目录缓存（兼容 gh 与 gh.exe）
    local cached
    cached="$(find "${GH_BOOTSTRAP_DIR}" -type f \( -name gh -o -name gh.exe \) 2>/dev/null | head -1)"
    if [ -n "${cached}" ]; then
        chmod +x "${cached}" 2>/dev/null
        GH_BIN="${cached}"
        export PATH="$(dirname "${cached}"):${PATH}"
        return 0
    fi

    if [ "${GH_FETCH_NO_BOOTSTRAP:-}" = "1" ]; then
        return 1
    fi

    # 3. 自动下载官方二进制
    if ! command -v curl >/dev/null 2>&1; then
        echo "Warning: curl is required to bootstrap the gh CLI." >&2
        return 1
    fi

    local os_raw arch_raw gh_os gh_arch
    os_raw="$(uname -s)"
    arch_raw="$(uname -m)"

    case "${os_raw}" in
        Linux*)                        gh_os="linux" ;;
        Darwin*)                       gh_os="macOS" ;;
        MINGW*|MSYS*|CYGWIN*|Windows*) gh_os="windows" ;;
        *) echo "Warning: unsupported OS for gh bootstrap: ${os_raw}" >&2; return 1 ;;
    esac

    case "${arch_raw}" in
        x86_64|amd64)  gh_arch="amd64" ;;
        aarch64|arm64) gh_arch="arm64" ;;
        *) echo "Warning: unsupported arch for gh bootstrap: ${arch_raw}" >&2; return 1 ;;
    esac

    local api_url tag ver asset_name archive url
    api_url="https://api.github.com/repos/cli/cli/releases/latest"
    tag="$(curl -sfL "${api_url}" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)"
    if [ -z "${tag}" ] || [ "${tag}" = "null" ]; then
        echo "Warning: failed to query the latest gh CLI version." >&2
        return 1
    fi
    ver="${tag#v}"

    case "${gh_os}" in
        windows) asset_name="gh_${ver}_windows_${gh_arch}.zip" ;;
        macOS)   asset_name="gh_${ver}_macOS_${gh_arch}.zip" ;;
        *)       asset_name="gh_${ver}_linux_${gh_arch}.tar.gz" ;;
    esac

    echo "gh not found; downloading official GitHub CLI ${tag} (${gh_os}/${gh_arch})..."
    mkdir -p "${GH_BOOTSTRAP_DIR}" || return 1
    archive="${GH_BOOTSTRAP_DIR}/${asset_name}"
    url="https://github.com/cli/cli/releases/download/${tag}/${asset_name}"
    if ! curl -fSL -o "${archive}" "${url}"; then
        echo "Warning: failed to download gh CLI from: ${url}" >&2
        rm -f "${archive}"
        return 1
    fi

    case "${asset_name}" in
        *.zip)
            if ! command -v unzip >/dev/null 2>&1; then
                echo "Warning: unzip is required to extract the gh CLI." >&2
                return 1
            fi
            unzip -oq "${archive}" -d "${GH_BOOTSTRAP_DIR}" || return 1
            ;;
        *)
            tar -xzf "${archive}" -C "${GH_BOOTSTRAP_DIR}" || return 1
            ;;
    esac

    local extracted
    extracted="$(find "${GH_BOOTSTRAP_DIR}" -type f \( -name gh -o -name gh.exe \) 2>/dev/null | head -1)"
    if [ -z "${extracted}" ]; then
        echo "Warning: gh binary not found after extraction." >&2
        return 1
    fi

    chmod +x "${extracted}" 2>/dev/null
    GH_BIN="${extracted}"
    export PATH="$(dirname "${extracted}"):${PATH}"
    rm -f "${archive}"
    echo "gh CLI ready: ${GH_BIN}"
    return 0
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

#
# 下载策略（官方方法优先）：
#   1. 优先使用官方 GitHub CLI：`gh release download`
#      （自动处理私有仓库认证，与 local-build.sh 保持一致）
#   2. 无 gh 或 gh 失败时，回退到直接 URL（curl）
#      （适合公共仓库或 URL 由用户通过 --url 显式指定）
#   3. 若仍失败且 URL 是自动生成的，通过 GitHub API 获取资产 API URL 重试
#      （API URL 重定向在 api.github.com 同主机内，认证头不会丢失）
#
DOWNLOAD_SUCCEEDED=false

if ensure_gh; then
    echo "Using official method: gh release download"
    if do_download_gh "${PACKAGE_REPO}" "${PACKAGE_VERSION}" "${PACKAGE_OS}" "${PACKAGE_ARCH}" "${PACKAGE_NAME}" "${TARGET_FILE}"; then
        DOWNLOAD_SUCCEEDED=true
    else
        echo "gh download failed, falling back to curl..."
    fi
else
    echo "gh unavailable, using curl..."
fi

if [ "$DOWNLOAD_SUCCEEDED" != true ]; then
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
            if [ -z "${GH_TOKEN}" ] && [ -z "${GITHUB_TOKEN}" ]; then
                echo "Hint: No GH_TOKEN/GITHUB_TOKEN is set. If the repository '${PACKAGE_REPO}' is private,"
                echo "      GitHub returns HTTP 404 for unauthenticated requests and the download will always fail."
                echo "      Authenticate the official GitHub CLI (auto-installed when missing), or export a token and retry:"
                echo "        gh auth login            # 官方 CLI 登录（推荐）"
                echo "        export GH_TOKEN=<your-github-token>"
            fi
        fi
    fi

    if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
        echo "Error: Failed to download from: ${PACKAGE_URL}"
        rm -f "${TARGET_FILE}"
        exit 1
    fi
fi

# 设置可执行权限
chmod +x "${TARGET_FILE}" 2>/dev/null

echo ""
echo "Successfully downloaded: ${TARGET_FILE}"
exit 0
