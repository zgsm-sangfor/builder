#!/bin/bash

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

usage() {
    cat <<EOF
usage: $(basename "$0") [options]
  从远程服务器下载镜像文件

options:
  -b|--base-url <URL>     HTTP基地址 (默认: https://zgsm.sangfor.com/shenma-images)
  -o|--output  <DIR>      输出目录 (默认: ./images)
  -i|--images  <STR>      镜像列表字符串, 格式: name:tag (空格/换行分隔多个)
  -f|--file    <FILE>     镜像列表文件路径 (默认: .images.list, 格式: name:tag 每行一个)
  -h|--help               显示帮助信息

examples:
  $(basename "$0") -f .images.list
  $(basename "$0") -i 'nginx:1.27.1 redis:7.2.4' -o /tmp/images
  $(basename "$0") -b https://example.com/images -f my-images.list -o ./downloads
EOF
}

# 使用getopt解析参数
TEMP=$(getopt -o b:o:i:f:h --long base-url:,output:,images:,file:,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    usage >&2
    exit 1
fi
eval set -- "$TEMP"

# 默认值
base_url="https://zgsm.sangfor.com/shenma-images"
output_dir="./images"
images_str=""
images_file=".images.list"

# 解析参数
while true ; do
    case "$1" in
        -b|--base-url)
            base_url="$2"
            shift 2
            ;;
        -o|--output)
            output_dir="$2"
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

# 检测下载工具
download_cmd=""
if command -v curl >/dev/null 2>&1; then
    download_cmd="curl"
elif command -v wget >/dev/null 2>&1; then
    download_cmd="wget"
else
    log "ERROR" "未找到 wget 或 curl 命令" >&2
    exit 1
fi

# 创建输出目录
mkdir -p "$output_dir"

# 收集镜像列表
IMAGES=""
if [ -n "$images_str" ]; then
    IMAGES="$images_str"
elif [ -n "$images_file" ]; then
    if [ ! -f "$images_file" ]; then
        log "ERROR" "镜像列表文件不存在: $images_file"
        exit 1
    fi
    IMAGES=$(cat "$images_file")
else
    log "ERROR" "必须指定镜像列表 (-i/--images 或 -f/--file)" >&2
    usage >&2
    exit 1
fi

# 去除 base_url 尾部斜杠
base_url="${base_url%/}"

error_count=0
success_count=0

# 处理每个镜像
for image in $IMAGES; do
    # 跳过空行
    [ -z "$image" ] && continue
    # 跳过注释行 (以 # 开头)
    [[ "$image" =~ ^# ]] && continue

    # 解析镜像名和tag: image-name:tag
    # 取最后一个冒号作为分隔符，兼容 image-name 中包含端口号的情况 (如 docker.io:8080/name:tag 不常见)
    if [[ "$image" =~ ^(.+):([^:]+)$ ]]; then
        image_name="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
    else
        log "WARN" "跳过无效镜像ID (格式应为 name:tag): $image"
        continue
    fi

    # 构建下载 URL: ${base-url}/{short-name}/{short-name}-{tag}.tar
    # 提取短名称 (去掉 repo 前缀, 即最后一个 '/' 之前的部分)
    short_name="${image_name##*/}"
    file_url="${base_url}/${short_name}/${short_name}-${tag}.tar"

    # 构建输出路径，目录结构镜像远程结构
    output_path="${output_dir}/${short_name}-${tag}.tar"
    output_parent=$(dirname "$output_path")
    mkdir -p "$output_parent"

    log "INFO" "正在下载: $image  ->  $file_url"

    has_error=false
    if [ "$download_cmd" = "wget" ]; then
        if ! wget -q "$file_url" -O "$output_path"; then
            has_error=true
            ((error_count++))
        fi
    else
        if ! curl -sS -f -o "$output_path" "$file_url"; then
            has_error=true
            ((error_count++))
        fi
    fi

    if [ "$has_error" = true ]; then
        log "WARN" "下载失败: $image"
        rm -f "$output_path"
    else
        log "INFO" "下载成功: $image  ->  $output_path"
        ((success_count++))
    fi
done

log "INFO" "下载完成 — 成功: ${success_count} 个"
if [ "$error_count" -gt 0 ]; then
    log "ERROR" "失败: ${error_count} 个"
    exit 1
fi
