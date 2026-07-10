#!/bin/bash

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

merge_envs() {
    local output_file="$1"
    local source_file="$2"
    local work_dir="$3"
    
    # 切换到目标目录
    cd "${work_dir}" || {
        log "ERROR" "无法切换到目录: ${work_dir}"
        return 1
    }

    # 清空或创建输出文件
    > "$output_file"
    
    # 查找所有 $source_file 文件并合并内容
    local env_files=()  # 用于记录找到的文件名
    while IFS= read -r env_file; do
        env_files+=("$env_file")
        # 将非空、非注释行追加到输出文件
        grep -v '^#' "$env_file" | grep -v '^$' | tr -d '\r' >> "$output_file"
    done < <(find . -name "$source_file" -type f)
    
    if [[ ${#env_files[@]} -eq 0 ]]; then
        log "WARN" "未找到任何 $source_file 文件"
    else
        log "INFO" "环境变量文件 $output_file 已合并 ${#env_files[@]} 个 $source_file 文件："
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
        return 0
    fi
    
    # 检查 target 文件是否存在，不存在则创建
    if [[ ! -f "$target" ]]; then
        touch "$target"
    fi

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
    
    return $line_count
}

gen_lack_env() {
    # source 加载 .env，该文件中可能定义了COSTRICT_HOST，COSTRICT_PORT，COSTRICT_BASEURL
    #   如果没定义，则设定一个默认值追加到.env
    if [ -f "${OUT_DOT_ENV}" ]; then
        . "${OUT_DOT_ENV}"
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
    
    # 声明关联数组来存储文件路径、可选性和行数
    declare -A file_optional  # 标记文件是否可选：1=可选，0=必选
    declare -A line_counts    # 存储每个文件的行数
    
    # 定义需要合并的环境变量文件及其可选性
    file_optional["${OUT_IMAGES_ENV}"]=0        # 必选
    file_optional["${OUT_PORTS_ENV}"]=0         # 必选
    file_optional["${OUT_APPS_ENV}"]=1
    file_optional["${IN_COSTRICT_ENV}"]=0       # 必选
    file_optional["${IN_INSTALL_ENV}"]=0        # 必选
    file_optional["${IN_COSTRICT_ADMIN_ENV}"]=1 # 可选
    
    # 遍历所有文件，对每个文件进行 merge_env
    for file in "${!file_optional[@]}"; do
        # 检查文件是否存在
        if [[ -f "$file" ]]; then
            # 调用 merge_env 并捕获返回的行数
            merge_env "${OUT_DOT_ENV}" "$file"
            line_counts["$file"]=$?
        else
            line_counts["$file"]=0
        fi
    done
    
    # 输出所有文件及其对应的 line_count
    log "INFO" "环境变量文件 ${OUT_DOT_ENV} 已合并下列文件的内容："
    for file in "${!file_optional[@]}"; do
        if [[ ! -f "$file" ]]; then
            if [[ ${file_optional[$file]} -eq 1 ]]; then
                log "INFO" "  $file: 文件不存在，可忽略"
            else
                log "WARN" "  $file: 必要文件缺失，请检查"
            fi
        else
            log "INFO" "  $file: ${line_counts[$file]} 行"
        fi
    done
    
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
OUT_PORTS_ENV="${WORK_DIR}.ports.env"
OUT_APPS_ENV="${WORK_DIR}.apps.env"
# 安装结束时构建的记录所有环境变量，可供docker-compose.yml使用的变量文件
OUT_DOT_ENV="${WORK_DIR}.env"
# 安装过程记录的配置(安装目录)
IN_INSTALL_ENV="/root/.costrict.install.env"
# 出厂预设的配置costrict.env.in，经过了本地化处理(比如重新生成密码)
IN_COSTRICT_ENV="${WORK_DIR}.costrict.env"
# 管理员配置，输出到.env的末尾，即，允许管理员手动重置任一变量
IN_COSTRICT_ADMIN_ENV="${WORK_DIR}costrict-admin.env"

mkdir -p "${WORK_DIR}"

# 根据各个目录下的image.env构建.images.env
log "INFO" "生成镜像环境变量文件: ${OUT_IMAGES_ENV} ..."
if ! merge_envs "${OUT_IMAGES_ENV}" "image.env" "${WORK_DIR}"; then
    exit 1
fi

# 根据各个目录下的ports.env构建.ports.env
log "INFO" "生成端口环境变量文件: ${OUT_PORTS_ENV} ..."
if ! merge_envs "${OUT_PORTS_ENV}" "port.env" "${WORK_DIR}"; then
    exit 1
fi

log "INFO" "生成应用配置文件: ${OUT_APPS_ENV} ..."
if ! merge_envs "${OUT_APPS_ENV}" "app.env" "${WORK_DIR}"; then
    exit 1
fi

# 从.images.env提取镜像列表.images.list
log "INFO" "生成镜像列表文件: $OUT_IMAGES_LIST ..."
awk -F'=' '{print $2}' "${OUT_IMAGES_ENV}" > "${OUT_IMAGES_LIST}"

# 把.costrict.env,.images.env,.ports.env,.costrict.install.env,costrict-admin.env合并成.env文件
log "INFO" "生成环境变量文件 ${OUT_DOT_ENV} ..."
if ! gen_dot_env; then
    exit 1
fi
