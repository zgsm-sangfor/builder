#!/bin/bash

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

gen_images_env() {
    local output_file="$1"
    
    # 切换到目标目录
    cd "${WORK_DIR}" || {
        log "ERROR" "无法切换到目录: ${WORK_DIR}"
        return 1
    }
    
    log "INFO" "开始收集镜像环境配置..."
    
    # 清空或创建输出文件
    > "$output_file"
    
    # 查找所有 image.env 文件并合并内容
    local found_files=0
    while IFS= read -r env_file; do
        found_files=$((found_files + 1))
        log "INFO" "处理镜像配置文件: $env_file"
        
        # 将非空、非注释行追加到输出文件
        grep -v '^#' "$env_file" | grep -v '^$' | tr -d '\r' >> "$output_file"
    done < <(find . -name "image.env" -type f)
    
    if [[ $found_files -eq 0 ]]; then
        log "WARN" "未找到任何 image.env 文件"
    else
        log "INFO" "已收集 ${found_files} 个镜像环境配置文件"
        log "INFO" "镜像环境配置已合并到: $output_file"
    fi
    
    # 切换回原目录
    cd - >/dev/null
    return 0
}

merge_env() {
    local target="$1"
    local source="$2"
    
    # 检查 source 文件是否存在
    if [[ ! -f "$source" ]]; then
        log "ERROR" "源文件不存在: $source"
        return 1
    fi
    
    # 检查 target 文件是否存在，不存在则创建
    if [[ ! -f "$target" ]]; then
        touch "$target"
    fi
    
    log "INFO" "开始合并环境配置: $source -> $target"
    
    # 读取 source 文件的非注释行和非空行，追加到 target 文件
    local line_count=0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过注释行（以 # 开头，包括前面有空格的情况）
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        # 跳过纯空格的行
        if [[ -z "${line// /}" ]]; then
            continue
        fi
        
        # 追加到 target 文件
        echo "$line" >> "$target"
        line_count=$((line_count + 1))
    done < "$source"
    
    log "INFO" "已追加 ${line_count} 行到: $target"
    return 0
}

gen_lack_env() {
    # source 加载 .costrict.env和costrict-admin.env，
    #   该文件中可能定义了COSTRICT_HOST，COSTRICT_PORT，COSTRICT_BASEURL
    #   如果没定义，则设定一个默认值追加到.env
    if [ -f "${IN_COSTRICT_ENV}" ]; then
        . "${IN_COSTRICT_ENV}"
    fi
    if [[ -f "${IN_COSTRICT_ADMIN_ENV}" ]]; then
        . "${IN_COSTRICT_ADMIN_ENV}"
    fi
    local server_ip=$(hostname -I | awk '{ print $1 }')

    if [ -z "${COSTRICT_HOST:-}" ]; then
        COSTRICT_HOST="${server_ip}"
        echo "COSTRICT_HOST=\"${server_ip}\"" >> ${OUT_DOT_ENV}
    fi
    
    if [ -z "${COSTRICT_PORT:-}" ]; then
        COSTRICT_PORT="${PORT_APISIX_ENTRY}"
        echo "COSTRICT_PORT=\"${PORT_APISIX_ENTRY}\"" >> ${OUT_DOT_ENV}
    fi

    if [ -z "${COSTRICT_BASEURL:-}" ]; then
        echo "COSTRICT_BASEURL=\"http://${COSTRICT_HOST}:${COSTRICT_PORT}\"" >> ${OUT_DOT_ENV}
    fi
}

gen_dot_env() {
    # 清空 .env 文件（如果存在）
    > ${OUT_DOT_ENV} 2>/dev/null || :  # 使用 : 确保命令总是成功
    # 调用 merge_env，将 ".images.env,.costrict.env,.install.env" 合并到 ".env" 文件中
    merge_env ${OUT_DOT_ENV} ${OUT_IMAGES_ENV}
    merge_env ${OUT_DOT_ENV} ${IN_COSTRICT_ENV}
    merge_env ${OUT_DOT_ENV} ${IN_INSTALL_ENV}
    
    # 如果存在 costrict-admin.env，则将其合并到 .env
    if [[ -f "${IN_COSTRICT_ADMIN_ENV}" ]]; then
        merge_env "${OUT_DOT_ENV}" "${IN_COSTRICT_ADMIN_ENV}"
    fi
    
    gen_lack_env

    return 0
}

# 使用getopt解析参数
TEMP=$(getopt -o d: --long dir: -n "$0" -- "$@")
eval set -- "$TEMP"

# 默认值
WORK_DIR=$(pwd)

# 解析参数
while true ; do
    case "$1" in
        -d|--dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --) shift ; break ;;
        *) echo "参数解析错误" >&2 ; exit 1 ;;
    esac
done

[[ "${WORK_DIR: -1}" != "/" ]] && WORK_DIR="${WORK_DIR}/"

# 安装过程生成的记录所有镜像地址的env
OUT_IMAGES_ENV="${WORK_DIR}.images.env"
# 安装过程生成的记录镜像URL的列表文件
OUT_IMAGES_LIST="${WORK_DIR}.images.list"
# 安装结束时构建的记录所有环境变量，可供docker-compose.yml使用的变量文件
OUT_DOT_ENV="${WORK_DIR}.env"
# 安装过程记录的配置(安装目录)
IN_INSTALL_ENV="/root/.costrict.install.env"
# 出厂预设的配置costrict.env.in，经过了本地化处理(比如重新生成密码)
IN_COSTRICT_ENV="${WORK_DIR}.costrict.env"
# 管理员配置
IN_COSTRICT_ADMIN_ENV="${WORK_DIR}costrict-admin.env"

mkdir -p "${WORK_DIR}"

# 根据各个目录下的image.env构建.images.env
log "INFO" "生成镜像环境变量文件: ${OUT_IMAGES_ENV} ..."
if ! gen_images_env ${OUT_IMAGES_ENV}; then
    exit 1
fi

# 从.images.env提取镜像列表.images.list
log "INFO" "生成镜像列表文件: $OUT_IMAGES_LIST ..."
awk -F'=' '{print $2}' "${OUT_IMAGES_ENV}" > "${OUT_IMAGES_LIST}"

# 把.costrict.env,.images.env合并成.env文件
log "INFO" "生成环境变量文件 ${OUT_DOT_ENV} ..."
if ! gen_dot_env; then
    exit 1
fi
