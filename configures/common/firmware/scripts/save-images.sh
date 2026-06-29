#!/bin/bash

# 本脚本运行的前提条件：
#   1. linux机器
#   2. 安装了docker
#
# 输出目录结构（与 download-images.sh 的远程读取结构保持一致）:
#   ${SAVE_DIR}/${short_name}/${short_name}-${tag}.tar

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

usage() {
    cat <<EOF
usage: $(basename "$0") [options]
  将 Docker 镜像保存为 tar 文件

options:
  -o|--output  <DIR>      输出目录 (默认: ./images)
  -i|--images  <STR>      镜像列表字符串, 格式: name:tag (空格/换行分隔多个)
  -f|--file    <FILE>     镜像列表文件路径 (默认: .images.list, 格式: name:tag 每行一个)
  -h|--help               显示帮助信息

examples:
  $(basename "$0") -f .images.list
  $(basename "$0") -i 'nginx:1.27.1 redis:7.2.4' -o /tmp/images
  $(basename "$0") -f my-images.list -o ./v1-images
EOF
}

# 使用getopt解析参数
TEMP=$(getopt -o o:i:f:h --long output:,images:,file:,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    usage >&2
    exit 1
fi
eval set -- "$TEMP"

# 默认值
SAVE_DIR="./images"
images_str=""
images_file=".images.list"

# 解析参数
while true ; do
    case "$1" in
        -o|--output)
            SAVE_DIR="$2"
            shift 2
            ;;
        -i|--images)
            images_str="$2"
            shift 2
            ;;
        -f|--file)
            images_file="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --) shift ; break ;;
        *)
            log "ERROR" "参数解析错误: $1"
            usage >&2
            exit 1
            ;;
    esac
done

# 检查 docker 命令
if ! command -v docker >/dev/null 2>&1; then
    log "ERROR" "未找到 docker 命令"
    exit 1
fi

# 收集镜像列表
IMAGES=""
if [ -n "$images_str" ]; then
    IMAGES="$images_str"
elif [ -n "$images_file" ]; then
    if [ ! -f "$images_file" ]; then
        log "ERROR" "镜像列表文件不存在: $images_file"
        exit 1
    fi
    IMAGES=$(cat "$images_file" | tr -d '\r')
else
    log "ERROR" "必须指定镜像列表 (-i/--images 或 -f/--file)" >&2
    usage >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$SAVE_DIR"

error_count=0
success_count=0

# 处理每个镜像
for image in $IMAGES; do
    # 跳过空行
    [ -z "$image" ] && continue
    # 跳过注释行 (以 # 开头)
    [[ "$image" =~ ^# ]] && continue

    # 解析镜像名和tag: image-name:tag
    # 取最后一个冒号作为分隔符，兼容 image-name 中包含端口号的情况
    if [[ "$image" =~ ^(.+):([^:]+)$ ]]; then
        image_name="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
    else
        log "WARN" "跳过无效镜像ID (格式应为 name:tag): $image"
        continue
    fi

    # 提取短名称 (去掉 repo 前缀, 即最后一个 '/' 之前的部分)
    # 与 download-images.sh 保持一致的命名规则: ${short_name}/${short_name}-${tag}.tar
    short_name="${image_name##*/}"
    output_path="${SAVE_DIR}/${short_name}/${short_name}-${tag}.tar"
    output_parent=$(dirname "$output_path")
    mkdir -p "$output_parent"

    log "INFO" "正在保存镜像: ${image}  ->  ${output_path}"
    if docker save -o "$output_path" "$image"; then
        log "INFO" "保存成功: ${image}  ->  ${output_path}"
        ((success_count++))
    else
        log "ERROR" "保存失败: ${image}"
        rm -f "$output_path"
        ((error_count++))
    fi
done

log "INFO" "保存完成 — 成功: ${success_count} 个"
if [ "$error_count" -gt 0 ]; then
    log "ERROR" "失败: ${error_count} 个"
    exit 1
fi
