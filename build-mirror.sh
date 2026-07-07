#!/bin/bash

set -e

#
# build-mirror.sh - 构建离线安装包 costrict-mirror.tar.gz
#
# 选项:
#   --ignore-images   打包时忽略 images 目录
#   --update-static   强制更新 costrict-static 内容（即使本地已存在）
#
# 流程:
#   Step 1: 获取/更新 costrict-static 的内容
#   Step 2: 打包 site 目录并拷贝到 costrict-static 下
#   Step 3: 将 costrict-static、packages、images 打包为 costrict-mirror.tar.gz
#

BASE_URL="https://zgsm.sangfor.com"
STATIC_DIR="costrict-static"
MANIFEST_FILE="${STATIC_DIR}/MANIFEST"
SITE_DIR="site"
SITE_TAR="mirror-site.tar"
OUTPUT_FILE="costrict-mirror.tar.gz"

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 离线安装包 costrict-mirror.tar.gz"
    echo ""
    echo "选项:"
    echo "  --ignore-images   打包时忽略 images 目录"
    echo "  --update-static   强制更新 costrict-static 内容（即使本地已存在）"
    echo "  --help, -h        显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. 获取/更新 costrict-static 的内容（从 ${BASE_URL} 下载 MANIFEST 及其列出的文件）"
    echo "  2. 打包 site 目录为 ${SITE_TAR} 并拷贝到 ${STATIC_DIR} 下"
    echo "  3. 将 ${STATIC_DIR}、packages、images 打包为 ${OUTPUT_FILE}"
    echo ""
    echo "示例:"
    echo "  $0                              # 仅打包（不忽略 images，已有静态文件不更新）"
    echo "  $0 --ignore-images              # 打包但不包含 images"
    echo "  $0 --update-static              # 强制更新静态文件后打包"
    echo ""
}

# 解析参数
IGNORE_IMAGES=false
UPDATE_STATIC=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ignore-images)
            IGNORE_IMAGES=true
            shift
            ;;
        --update-static)
            UPDATE_STATIC=true
            shift
            ;;
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
# Step 1: 获取/更新 costrict-static 的内容
#
echo "----------------------------------------------------------------"
echo "Step 1: 获取/更新 ${STATIC_DIR} 内容..."
echo "----------------------------------------------------------------"

# 创建 costrict-static 目录（如果不存在）
mkdir -p "${STATIC_DIR}"

# 先尝试从 GitHub Releases 下载 costrict-static.tar，将其中的 linux 目录解压到 costrict-static 下
STATIC_TAR_URL="https://github.com/zgsm-sangfor/costrict-static/releases/download/v1.1.0/costrict-static.tar"
STATIC_TAR_FILE="costrict-static.tar"

echo "正在尝试从 GitHub Releases 下载 ${STATIC_TAR_FILE}..."
download_success=false
if command -v curl &> /dev/null; then
    curl -fSL -o "${STATIC_TAR_FILE}" "${STATIC_TAR_URL}" && download_success=true || true
elif command -v wget &> /dev/null; then
    wget -q -O "${STATIC_TAR_FILE}" "${STATIC_TAR_URL}" && download_success=true || true
fi

if [ "$download_success" = true ] && [ -f "${STATIC_TAR_FILE}" ]; then
    echo "下载成功，正在提取 linux 目录到 ${STATIC_DIR}/..."
    tar -xf "${STATIC_TAR_FILE}" -C "${STATIC_DIR}" linux/
    rm -f "${STATIC_TAR_FILE}"
    echo "${STATIC_TAR_FILE} 中的 linux 目录提取完成。"
else
    echo "从 GitHub Releases 下载 ${STATIC_TAR_FILE} 失败，将使用原有 MANIFEST 方式获取。"
fi

# 下载单个文件
# file_path 是./costrict-static目录下的文件或子目录（如 ./linux/amd64/xxx）
#
download_file() {
    local file_path="$1"

    # 去除首尾空白
    file_path=$(echo "${file_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 去掉 ./ 前缀（防御性处理）
    file_path="${file_path#./}"

    # 安全检查：禁止路径遍历攻击
    if [[ "${file_path}" == *".."* ]]; then
        echo "  [错误] 非法文件路径（包含 ..）: ${file_path}"
        return 1
    fi

    # 安全检查：路径不能为空
    if [[ -z "${file_path}" ]]; then
        echo "  [错误] 文件路径为空"
        return 1
    fi

    # 直接使用 file_path 作为本地存储路径和远程 URL 路径
    local local_path="./${STATIC_DIR}/${file_path}"
    local remote_url="${BASE_URL}/costrict-static/${file_path}"
    local file_dir

    file_dir=$(dirname "${local_path}")

    # 检查是否需要下载
    local need_download=false
    if [ "$UPDATE_STATIC" = true ]; then
        need_download=true
    elif [ ! -f "${local_path}" ]; then
        need_download=true
    else
        echo "  [跳过] ${file_path} (本地已存在)"
        return 0
    fi

    # 创建目标目录
    mkdir -p "${file_dir}"

    echo "  [下载] ${file_path} <- ${remote_url}"
    if command -v curl &> /dev/null; then
        curl -fSL -o "${local_path}" "${remote_url}"
    elif command -v wget &> /dev/null; then
        wget -q -O "${local_path}" "${remote_url}"
    else
        echo "错误: 未找到 curl 或 wget，无法下载文件。"
        exit 1
    fi
}

# 执行 MANIFEST 下载
download_file "./MANIFEST"

# 读取 MANIFEST 并逐文件下载
if [ -f "${MANIFEST_FILE}" ]; then
    echo ""
    echo "正在根据 MANIFEST 下载文件..."
    while IFS= read -r file_path || [ -n "$file_path" ]; do
        # 跳过空行和注释行（以 # 开头）
        [[ -z "${file_path}" ]] && continue
        [[ "${file_path}" =~ ^[[:space:]]*# ]] && continue

        download_file "${file_path}"
    done < "${MANIFEST_FILE}"
    echo "MANIFEST 中列出的文件处理完成。"
else
    echo "警告: MANIFEST 文件不存在，跳过文件下载。"
fi

#
# Step 2: 打包 site 目录并拷贝到 costrict-static 下
#
echo ""
echo "----------------------------------------------------------------"
echo "Step 2: 打包 site 目录..."
echo "----------------------------------------------------------------"

if [ -d "${SITE_DIR}" ]; then
    echo "正在将 ${SITE_DIR} 目录打包为 ${SITE_TAR}..."
    tar -cf "${SITE_TAR}" -C "${SITE_DIR}" .
    echo "正在将 ${SITE_TAR} 拷贝到 ${STATIC_DIR}/ 目录..."
    cp "${SITE_TAR}" "${STATIC_DIR}/${SITE_TAR}"
    # 清理临时 tar 文件
    rm -f "${SITE_TAR}"
    echo "site 目录打包完成: ${STATIC_DIR}/${SITE_TAR}"
else
    echo "警告: ${SITE_DIR} 目录不存在，跳过 site 打包。"
fi

#
# Step 3: 打包 costrict-static、packages、images 为 costrict-mirror.tar.gz
#
echo ""
echo "----------------------------------------------------------------"
echo "Step 3: 打包离线安装包 ${OUTPUT_FILE}..."
echo "----------------------------------------------------------------"

# 构建 tar 命令的参数列表
TAR_ARGS=("-czf" "${OUTPUT_FILE}")

# 始终包含 costrict-static（如果存在）
if [ -d "${STATIC_DIR}" ]; then
    TAR_ARGS+=("${STATIC_DIR}")
else
    echo "警告: ${STATIC_DIR} 目录不存在。"
fi

# 始终包含 packages（如果存在）
if [ -d "packages" ]; then
    TAR_ARGS+=("packages")
else
    echo "警告: packages 目录不存在。"
fi

# 根据 --ignore-images 决定是否包含 images
if [ "$IGNORE_IMAGES" = true ]; then
    echo "已指定 --ignore-images，跳过 images 目录。"
    echo "正在下载 nginx-1.27.1.tar 镜像..."
    download_file "./nginx-1.27.1.tar"
else
    if [ -d "images" ]; then
        TAR_ARGS+=("images")
    else
        echo "警告: images 目录不存在。"
    fi
fi

# 执行打包
echo "正在执行: tar ${TAR_ARGS[*]}"
tar "${TAR_ARGS[@]}"

echo ""
echo "----------------------------------------------------------------"
echo "离线安装包构建完成: ${OUTPUT_FILE}"
echo "----------------------------------------------------------------"
