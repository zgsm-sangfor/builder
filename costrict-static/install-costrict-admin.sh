#!/bin/bash

set -e

#
# install-costrict-admin.sh - 安装 costrict-admin 命令行工具
#
# 从 packages/costrict-admin 目录中查找当前系统平台的最新版本，
# 将其安装到 /usr/bin（如有权限）或当前目录下。
#

PACKAGE_NAME="costrict-admin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(dirname "${SCRIPT_DIR}")/packages"
BINARY_NAME="${PACKAGE_NAME}"

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "从 ${PACKAGES_DIR}/${PACKAGE_NAME} 目录安装 ${PACKAGE_NAME} 命令行工具。"
    echo ""
    echo "功能:"
    echo "  - 自动检测当前操作系统和 CPU 架构"
    echo "  - 查找当前平台的最新版本"
    echo "  - 若有 /usr/bin 写入权限，安装到 /usr/bin/${BINARY_NAME}"
    echo "  - 若无权限，则安装到当前目录下"
    echo ""
    echo "选项:"
    echo "  --help, -h        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                 # 自动检测平台并安装"
    echo ""
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

#
# 检测当前操作系统
#
detect_os() {
    local os_name
    os_name=$(uname -s)
    case "${os_name}" in
        Linux)
            echo "linux"
            ;;
        Darwin)
            echo "darwin"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "错误: 不支持的操作系统: ${os_name}" >&2
            exit 1
            ;;
    esac
}

#
# 检测当前 CPU 架构
#
detect_arch() {
    local arch_name
    arch_name=$(uname -m)
    case "${arch_name}" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64|aarch64_be|armv8b|armv8l)
            echo "arm64"
            ;;
        *)
            echo "错误: 不支持的 CPU 架构: ${arch_name}" >&2
            exit 1
            ;;
    esac
}

CURRENT_OS=$(detect_os)
CURRENT_ARCH=$(detect_arch)

echo "----------------------------------------------------------------"
echo "检测到当前平台: ${CURRENT_OS}/${CURRENT_ARCH}"
echo "----------------------------------------------------------------"

#
# 查找安装源目录
#
PKG_PLATFORM_DIR="${PACKAGES_DIR}/${PACKAGE_NAME}/${CURRENT_OS}/${CURRENT_ARCH}"

if [ ! -d "${PKG_PLATFORM_DIR}" ]; then
    echo "错误: 未找到 ${PACKAGE_NAME} 的安装包目录: ${PKG_PLATFORM_DIR}" >&2
    echo ""
    echo "请确保已通过 build-components.sh 构建了 ${PACKAGE_NAME} 包。" >&2
    echo "可用的平台目录:" >&2
    if [ -d "${PACKAGES_DIR}/${PACKAGE_NAME}" ]; then
        find "${PACKAGES_DIR}/${PACKAGE_NAME}" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | while read -r d; do
            echo "  ${d}" >&2
        done
    else
        echo "  (无 — ${PACKAGES_DIR}/${PACKAGE_NAME} 目录不存在)" >&2
    fi
    exit 1
fi

#
# 查找最新版本
#
echo "正在查找 ${CURRENT_OS}/${CURRENT_ARCH} 平台的最新版本..."

LATEST_VERSION=""
LATEST_VERSION_DIR=""

# 遍历版本目录，使用版本号排序获取最新版本
for version_dir in "${PKG_PLATFORM_DIR}"/*/; do
    [ -d "${version_dir}" ] || continue
    ver=$(basename "${version_dir}")
    # 移除尾部斜杠后的版本名
    ver="${ver%/}"
    if [ -z "${LATEST_VERSION}" ]; then
        LATEST_VERSION="${ver}"
        LATEST_VERSION_DIR="${version_dir}"
    else
        # 使用 sort -V 进行版本号比较
        if printf '%s\n%s\n' "${LATEST_VERSION}" "${ver}" | sort -V | tail -1 | grep -q "^${ver}$"; then
            LATEST_VERSION="${ver}"
            LATEST_VERSION_DIR="${version_dir}"
        fi
    fi
done

if [ -z "${LATEST_VERSION}" ]; then
    echo "错误: 在 ${PKG_PLATFORM_DIR} 下未找到任何版本目录。" >&2
    exit 1
fi

echo "找到最新版本: ${LATEST_VERSION}"
echo "源目录: ${LATEST_VERSION_DIR}"

#
# 查找二进制文件
#
# 在版本目录中查找可执行文件（优先匹配包名，其次查找任意文件）
SOURCE_BINARY=""

# 首先尝试精确匹配包名
if [ -f "${LATEST_VERSION_DIR}${BINARY_NAME}" ]; then
    SOURCE_BINARY="${LATEST_VERSION_DIR}${BINARY_NAME}"
elif [ -f "${LATEST_VERSION_DIR}${BINARY_NAME}.exe" ]; then
    SOURCE_BINARY="${LATEST_VERSION_DIR}${BINARY_NAME}.exe"
else
    # 尝试查找目录中的第一个普通文件作为备选
    for f in "${LATEST_VERSION_DIR}"*; do
        if [ -f "${f}" ]; then
            SOURCE_BINARY="${f}"
            break
        fi
    done
fi

if [ -z "${SOURCE_BINARY}" ]; then
    echo "错误: 在 ${LATEST_VERSION_DIR} 中未找到可执行文件。" >&2
    echo "目录内容:" >&2
    ls -la "${LATEST_VERSION_DIR}" >&2
    exit 1
fi

echo "源文件: ${SOURCE_BINARY}"

#
# 确定安装目标目录
#
INSTALL_DIR=""

if [ -d "/usr/bin" ] && [ -w "/usr/bin" ]; then
    INSTALL_DIR="/usr/bin"
    echo "检测到 /usr/bin 可写，将安装到系统路径。"
else
    INSTALL_DIR="."
    echo "/usr/bin 不可写或不存在，将安装到当前目录: $(pwd)"
fi

TARGET_PATH="${INSTALL_DIR}/${BINARY_NAME}"

#
# 执行安装
#
echo ""
echo "正在安装 ${BINARY_NAME} (版本 ${LATEST_VERSION}) -> ${TARGET_PATH}..."

cp "${SOURCE_BINARY}" "${TARGET_PATH}"
chmod +x "${TARGET_PATH}"

echo ""
echo "----------------------------------------------------------------"
echo "安装完成: ${TARGET_PATH}"
echo "----------------------------------------------------------------"

# 如果安装到当前目录，给出 PATH 提示
if [ "${INSTALL_DIR}" = "." ]; then
    echo ""
    echo "提示: 安装到了当前目录，你可以通过以下方式使用:"
    echo "  ./${BINARY_NAME} [参数]"
    echo ""
    echo "或者将当前目录加入 PATH:"
    echo "  export PATH=\"\$(pwd):\$PATH\""
fi
