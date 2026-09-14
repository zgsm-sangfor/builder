#!/bin/bash

set -e

#
# build-mirror.sh - 构建离线安装包 costrict-mirror.tar.gz
#
# 选项:
#   --arch <all|amd64|arm64>
#                     all 时分别为 amd64 与 arm64 生成独立的离线包
#                     (costrict-mirror-amd64.tar.gz、costrict-mirror-arm64.tar.gz)；
#                     amd64/arm64 时仅打包指定架构，输出 costrict-mirror-${arch}.tar.gz；
#                     未指定时自动检测当前平台架构，仅打包当前平台的包
#   --no-images   打包时忽略 images 目录
#   --force   强制更新 costrict-static 内容（即使本地已存在）
#   --github-first    下载文件时优先从 GitHub 下载（默认优先从 zgsm.sangfor.com 下载）
#
# 流程:
#   Step 1: 获取/更新 costrict-static 的内容
#   Step 2: 打包 site 目录并拷贝到 costrict-static 下
#   Step 3: 为每个目标架构分别打包 costrict-static、packages、images 为
#           costrict-mirror-<arch>.tar.gz
#
# 架构相关内容（指定 --arch 时仅保留目标架构，其余架构内容被排除）:
#   images/<arch>/                              镜像目录
#   costrict-static/linux/<arch>/               离线安装包（docker/compose/jq 等）
#   costrict-static/nginx-1.31.1-<arch>.tar     按架构命名的 nginx 镜像
#

ZGSM_BASE_URL="https://zgsm.sangfor.com/costrict-static"
GITHUB_BASE_URL="https://github.com/zgsm-sangfor/costrict-static/releases/download/v1.2.0"
STATIC_DIR="costrict-static"
MANIFEST_FILE="${STATIC_DIR}/MANIFEST"
SITE_DIR="site"
SITE_TAR="mirror-site.tar"
NGINX_IMAGE="nginx:1.31.1"
# 支持的架构列表：离线包默认同时提供 amd64 与 arm64 两种架构
SUPPORTED_ARCHES=("amd64" "arm64")
# 目标架构：all 打包全部架构；amd64/arm64 仅打包指定架构；为空时自动检测当前平台架构
ARCH=""
# 实际参与打包的架构列表（解析参数后确定）
TARGET_ARCHES=("${SUPPORTED_ARCHES[@]}")
NGINX_IMAGE_TAR="${STATIC_DIR}/nginx-1.31.1.tar"
STATIC_TAR_FILE="costrict-static.tar"

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 离线安装包 costrict-mirror.tar.gz"
    echo ""
    echo "选项:"
    echo "  --arch <all|amd64|arm64>"
    echo "                    all：分别为 amd64 与 arm64 生成独立的离线包；"
    echo "                    amd64/arm64：仅打包指定架构，输出 costrict-mirror-<arch>.tar.gz；"
    echo "                    未指定时自动检测当前平台架构，仅打包当前平台的包"
    echo "  --no-images       不包含 images 目录"
    echo "  --github-first    下载文件时优先从 GitHub 下载（默认优先从 ${ZGSM_BASE_URL} 下载）"
    echo "  --force           强制更新本地文件（即使本地已存在）"
    echo "  --help, -h        显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. 获取/更新 costrict-static 的内容（从 ${ZGSM_BASE_URL} 或 GitHub 下载 MANIFEST 及其列出的文件）"
    echo "  2. 打包 site 目录为 ${SITE_TAR} 并拷贝到 ${STATIC_DIR} 下"
    echo "  3. 为每个目标架构分别打包为 costrict-mirror-<arch>.tar.gz"
    echo ""
    echo "示例:"
    echo "  $0                  # 自动检测当前平台架构并打包（不忽略 images，已有静态文件不更新）"
    echo "  $0 --arch all       # 分别为 amd64 与 arm64 生成独立的离线包"
    echo "  $0 --arch amd64     # 仅打包 amd64 相关内容，输出 costrict-mirror-amd64.tar.gz"
    echo "  $0 --arch arm64     # 仅打包 arm64 相关内容，输出 costrict-mirror-arm64.tar.gz"
    echo "  $0 --no-images      # 打包但不包含 images 目录"
    echo "  $0 --force          # 强制更新静态文件后打包"
    echo "  $0 --github-first   # 优先从 GitHub 下载静态文件后打包"
    echo ""
}

#
# 检测当前运行平台的 CPU 架构，映射为 SUPPORTED_ARCHES 中的取值
# 输出:
#   amd64      当前平台为 x86_64/amd64
#   arm64      当前平台为 aarch64/arm64
#   空字符串    无法识别的架构
#
detect_arch() {
    local machine
    machine="$(uname -m 2>/dev/null)"
    case "${machine}" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo ""
            ;;
    esac
}

#
# 从指定的URL地址同步文件到本地
#   去空白、去 ./ 前缀、防路径遍历、已存在则跳过、curl/wget 回退下载
# 参数:
#   $1 remote_url  web站点下载地址
#      例如: https://github.com/zgsm-sangfor/costrict-static/releases/download/v1.2.0/costrict-static.tar
#            https://zgsm.sangfor.com/costrict-static/MANIFEST
#   $2 local_path  本地保存路径（可选），缺省时取 URL 中最后一个路径段作为文件名，保存到当前目录
# 返回:
#   0  下载成功或本地已存在（跳过）
#   1  参数非法或下载失败
#
download_file() {
    local remote_url="$1"
    local local_path="$2"

    # 去除首尾空白
    remote_url=$(echo "${remote_url}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    local_path=$(echo "${local_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 安全检查：远程地址不能为空
    if [[ -z "${remote_url}" ]]; then
        echo "  [错误] GitHub Release 地址为空"
        return 1
    fi

    # 未指定本地路径时，使用 URL 中最后一个路径段作为文件名
    if [[ -z "${local_path}" ]]; then
        local_path="${remote_url##*/}"
    fi

    # 去掉 ./ 前缀（防御性处理）
    local_path="${local_path#./}"

    # 安全检查：本地路径不能为空
    if [[ -z "${local_path}" ]]; then
        echo "  [错误] 本地保存路径为空"
        return 1
    fi

    # 安全检查：禁止路径遍历攻击
    if [[ "${local_path}" == *".."* ]]; then
        echo "  [错误] 非法本地路径（包含 ..）: ${local_path}"
        return 1
    fi

    # 检查是否需要下载（已存在且未强制更新则跳过）
    if [ "$FORCE" != true ] && [ -f "${local_path}" ]; then
        echo "  [跳过] ${local_path} (本地已存在)"
        return 0
    fi

    # 创建目标目录
    local file_dir
    file_dir=$(dirname "${local_path}")
    mkdir -p "${file_dir}"

    echo "  [下载] ${local_path} <- ${remote_url}"
    if command -v curl &> /dev/null; then
        curl -fSL -o "${local_path}" "${remote_url}" || return 1
    elif command -v wget &> /dev/null; then
        wget -q -O "${local_path}" "${remote_url}" || return 1
    else
        echo "  [错误] 未找到 curl 或 wget，无法下载文件。"
        return 1
    fi

    return 0
}

#
# 从站点下载单个文件到本地指定路径
#   根据 --github-first 选项决定站点优先级：
#     - 指定 --github-first：优先从 GitHub 下载，失败时回退到 zgsm.sangfor.com
#     - 未指定：优先从 zgsm.sangfor.com 下载，失败时回退到 GitHub
#   未指定 --force 且本地文件已存在时跳过下载。
# 参数:
#   $1 path       站点内的相对文件路径
#   $2 output_dir 本地输出目录（可选），指定时保存到 <output_dir>/<path>，缺省时保存到当前目录
# 返回:
#   0  下载成功或本地已存在（跳过）
#   1  参数非法或所有站点均下载失败
#
fetch_file() {
    local path="$1"
    local output_dir="$2"

    # 去除首尾空白
    path=$(echo "${path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    output_dir=$(echo "${output_dir}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 去掉 ./ 前缀（防御性处理）
    path="${path#./}"

    # 安全检查：路径不能为空
    if [[ -z "${path}" ]]; then
        echo "  [错误] 本地保存路径为空"
        return 1
    fi

    # 安全检查：禁止路径遍历攻击
    if [[ "${path}" == *".."* ]]; then
        echo "  [错误] 非法本地路径（包含 ..）: ${path}"
        return 1
    fi

    # 计算本地保存路径：指定 output_dir 时保存到其目录下
    local local_path="${path}"
    if [[ -n "${output_dir}" ]]; then
        local_path="${output_dir}/${path}"
    fi

    # 未指定 --force 且文件已存在时跳过
    if [ "$FORCE" != true ] && [ -f "${local_path}" ]; then
        echo "  [跳过] ${local_path} (本地已存在)"
        return 0
    fi

    # 根据选项指定的优先级确定站点基地址顺序
    local sites
    if [ "$GITHUB_FIRST" = true ]; then
        sites=("${GITHUB_BASE_URL}" "${ZGSM_BASE_URL}")
    else
        sites=("${ZGSM_BASE_URL}" "${GITHUB_BASE_URL}")
    fi

    # 按优先级依次尝试各站点，任一成功即返回
    local site remote_url
    for site in "${sites[@]}"; do
        if [ -z "${site}" ]; then
            continue
        fi
        remote_url="${site}/${path}"
        if download_file "${remote_url}" "${local_path}"; then
            return 0
        fi
        # 下载失败时清理可能残留的残缺文件，避免影响后续站点回退
        rm -f "${local_path}"
        echo "  从 ${site} 下载失败，尝试下一站点..."
    done
    echo "  [错误] 所有站点均无法下载: ${path}"
    return 1
}

# 下载单个文件到costrict-static目录下
# file_path 是 ${STATIC_DIR} 目录下的相对路径（如 MANIFEST、linux/amd64/xxx）
#
fetch_static_file() {
    local file_path="$1"

    # 去除首尾空白
    file_path=$(echo "${file_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # 去掉 ./ 前缀（防御性处理）
    file_path="${file_path#./}"

    # 安全检查：路径不能为空
    if [[ -z "${file_path}" ]]; then
        echo "  [错误] 文件路径为空"
        return 1
    fi

    # 安全检查：禁止路径遍历攻击
    if [[ "${file_path}" == *".."* ]]; then
        echo "  [错误] 非法文件路径（包含 ..）: ${file_path}"
        return 1
    fi

    # 站点相对路径为 <file_path>，本地保存到 ${STATIC_DIR}/<file_path>
    # 但zgsm.sangfor.com的base_url已经包含了costrict-static
    # 由 fetch_file 根据选项优先级选择 GitHub 或 zgsm.sangfor.com 下载
    # 指定输出目录为 ${STATIC_DIR}，直接保存到 costrict-static 下
    fetch_file "${file_path}" "${STATIC_DIR}"
}

# 解析参数
NO_IMAGES=false
FORCE=false
GITHUB_FIRST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-images)
            NO_IMAGES=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --github-first)
            GITHUB_FIRST=true
            shift
            ;;
        --arch)
            if [ -z "${2:-}" ]; then
                echo "错误: --arch 需要指定架构 (支持: all, ${SUPPORTED_ARCHES[*]})"
                show_help
                exit 1
            fi
            ARCH="$2"
            shift 2
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

# 处理 --arch：校验取值并确定实际打包的架构列表
#   all           -> 打包全部支持的架构（各架构一个独立离线包）
#   amd64/arm64   -> 仅打包指定架构
#   未指定         -> 自动检测当前平台架构，仅打包当前平台的包
if [ -n "${ARCH}" ]; then
    if [ "${ARCH}" = "all" ]; then
        TARGET_ARCHES=("${SUPPORTED_ARCHES[@]}")
    else
        arch_valid=false
        for a in "${SUPPORTED_ARCHES[@]}"; do
            if [ "${ARCH}" = "${a}" ]; then
                arch_valid=true
                break
            fi
        done
        if [ "${arch_valid}" != true ]; then
            echo "错误: 不支持的 --arch 取值: ${ARCH} (支持: all, ${SUPPORTED_ARCHES[*]})"
            exit 1
        fi
        TARGET_ARCHES=("${ARCH}")
    fi
else
    # 未指定 --arch 时，自动检测当前平台架构，仅打包当前平台的包
    detected_arch="$(detect_arch)"
    if [ -z "${detected_arch}" ]; then
        echo "错误: 无法自动检测当前平台架构，请使用 --arch 显式指定 (支持: all, ${SUPPORTED_ARCHES[*]})"
        exit 1
    fi
    echo "未指定 --arch，自动检测到当前平台架构: ${detected_arch}"
    TARGET_ARCHES=("${detected_arch}")
fi

#
# Step 1: 获取/更新 costrict-static 的内容
#
echo "----------------------------------------------------------------"
echo "Step 1: 获取/更新 ${STATIC_DIR} 内容..."
echo "----------------------------------------------------------------"

# 创建 costrict-static 目录（如果不存在）
mkdir -p "${STATIC_DIR}"

echo "正在尝试下载 ${STATIC_TAR_FILE}..."
if fetch_file "${STATIC_TAR_FILE}"; then
    echo "下载成功，正在解压 ${STATIC_TAR_FILE} 到 ${STATIC_DIR}/..."
    tar -xf "${STATIC_TAR_FILE}" -C "${STATIC_DIR}"
    echo "${STATIC_TAR_FILE} 解压完成。"
else
    echo "下载 ${STATIC_TAR_FILE} 失败，将使用原有 MANIFEST 方式获取。"
fi

# 执行 MANIFEST 下载
fetch_static_file "./MANIFEST"

# 读取 MANIFEST 并逐文件下载
if [ -f "${MANIFEST_FILE}" ]; then
    echo ""
    echo "正在根据 MANIFEST 下载文件..."
    while IFS= read -r file_path || [ -n "$file_path" ]; do
        # 跳过空行和注释行（以 # 开头）
        [[ -z "${file_path}" ]] && continue
        [[ "${file_path}" =~ ^[[:space:]]*# ]] && continue

        # 去除首尾空白并去掉 ./ 前缀（与 fetch_static_file 保持一致）
        file_path=$(echo "${file_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        file_path="${file_path#./}"

        # 跳过 ${SITE_TAR}：该文件由 Step 2 本地打包 ${SITE_DIR} 生成，无需从远端下载
        # 注意：仅当 ${SITE_DIR} 目录存在时才会生成该 tar，否则仍需从远端下载，避免漏掉文件
        if [ -d "${SITE_DIR}" ] && [ "$(basename "${file_path}")" = "${SITE_TAR}" ]; then
            echo "  [跳过] ${file_path} (由 Step 2 本地生成，无需下载)"
            continue
        fi

        fetch_static_file "${file_path}"
    done < "${MANIFEST_FILE}"
    echo "MANIFEST 中列出的文件处理完成。"
else
    echo "警告: MANIFEST 文件不存在，跳过文件下载。"
fi


#
# Step 2: 使用static及site目录的内容，更新costrict-static目录
#   static目录下的内容原样拷贝，site 目录打包为 costrict-static/mirror-site.tar
#
echo ""
echo "----------------------------------------------------------------"
echo "Step 2: 使用static及site目录的内容，更新costrict-static目录..."
echo "----------------------------------------------------------------"
#
# 将 static 目录下的所有内容拷贝到 costrict-static 目录下
#
echo ""
echo "正在将 static 目录下的所有内容拷贝到 ${STATIC_DIR} 目录..."
if [ -d "static" ]; then
    cp -rf static/. "${STATIC_DIR}/"
    echo "static 目录内容拷贝完成: static/ -> ${STATIC_DIR}/"
else
    echo "警告: static 目录不存在，跳过拷贝。"
fi

if [ -d "${SITE_DIR}" ]; then
    echo "将 ${SITE_DIR} 目录打包为 ${STATIC_DIR}/${SITE_TAR}..."
    tar -cf "${SITE_TAR}" -C "${SITE_DIR}" .
    cp "${SITE_TAR}" "${STATIC_DIR}/${SITE_TAR}"
    rm -f "${SITE_TAR}"
    echo "site 目录打包完成: ${STATIC_DIR}/${SITE_TAR}"
else
    echo "警告: ${SITE_DIR} 目录不存在，跳过 site 打包。"
fi

# 按目标架构分别拉取并保存 nginx 镜像，避免跨架构运行时出现：
#   exec /docker-entrypoint.sh: exec format error
echo "正在准备 nginx 镜像: ${NGINX_IMAGE} (架构: ${TARGET_ARCHES[*]})"
for arch in "${TARGET_ARCHES[@]}"; do
    arch_tar="${STATIC_DIR}/nginx-1.31.1-${arch}.tar"
    if [ "$FORCE" != true ] && [ -f "${arch_tar}" ]; then
        echo "  [跳过] ${arch_tar} (本地已存在)"
        continue
    fi
    echo "  [拉取] ${NGINX_IMAGE} (linux/${arch})"
    if docker pull --platform "linux/${arch}" "${NGINX_IMAGE}"; then
        echo "  [保存] ${NGINX_IMAGE} (linux/${arch}) -> ${arch_tar}"
        docker save -o "${arch_tar}" "${NGINX_IMAGE}"
    else
        echo "  拉取失败，尝试下载预置镜像 ./nginx-1.31.1-${arch}.tar"
        fetch_static_file "./nginx-1.31.1-${arch}.tar"
    fi
done

#
# Step 3: 为每个目标架构分别打包 costrict-static、packages、images 为
#         costrict-mirror-<arch>.tar.gz
#
echo ""
echo "----------------------------------------------------------------"
echo "Step 3: 按架构打包离线安装包 (架构: ${TARGET_ARCHES[*]})..."
echo "----------------------------------------------------------------"

# 按目标架构逐个打包：每个包仅保留当前架构相关内容，排除其余架构：
#   images/<other>/、costrict-static/linux/<other>/、costrict-static/nginx-1.31.1-<other>.tar
BUILT_PACKAGES=()
for arch in "${TARGET_ARCHES[@]}"; do
    output_file="costrict-mirror-${arch}.tar.gz"
    echo ""
    echo "正在打包 ${arch} 架构离线安装包: ${output_file}..."

    # 构建 tar 命令的参数列表
    TAR_ARGS=("-czf" "${output_file}")

    # 排除其余架构的相关内容，仅保留当前架构
    for other_arch in "${SUPPORTED_ARCHES[@]}"; do
        if [ "${other_arch}" = "${arch}" ]; then
            continue
        fi
        TAR_ARGS+=("--exclude=images/${other_arch}")
        TAR_ARGS+=("--exclude=${STATIC_DIR}/linux/${other_arch}")
        TAR_ARGS+=("--exclude=${STATIC_DIR}/nginx-1.31.1-${other_arch}.tar")
    done

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

    # 根据 --no-images 决定是否包含 images
    if [ "$NO_IMAGES" = false ]; then
        if [ -d "images" ]; then
            TAR_ARGS+=("images")
        else
            echo "警告: images 目录不存在。"
        fi
    fi

    # 执行打包
    echo "正在执行: tar ${TAR_ARGS[*]}"
    tar "${TAR_ARGS[@]}"
    BUILT_PACKAGES+=("${output_file}")
done

echo ""
echo "----------------------------------------------------------------"
echo "离线安装包构建完成: ${BUILT_PACKAGES[*]}"
echo "----------------------------------------------------------------"
