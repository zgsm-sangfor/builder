#!/bin/bash
# ============================================================================
# 环境升级脚本
# ============================================================================
# 功能说明:
#   本脚本用于升级各模块的环境配置，执行以下操作：
#     1. 检查指定目录或所有子目录
#     2. 若存在 do-configure-runtime.sh 脚本，则执行该脚本
#
# 使用场景:
#   - 升级各模块的环境配置
#   - 批量执行多个模块的升级脚本
# ============================================================================

set -e
set -u
set -o pipefail 2>/dev/null || true

# -------------------------- Initialize Configuration --------------------------
SCRIPT_NAME=$(basename "$0")

show_usage() {
    cat << EOF
升级各模块的环境配置，执行各目录下的 do-configure-runtime.sh 脚本

用法: $0 [options]

选项:
    --backend <PATH>   指定后端路径，默认为当前路径
    --package, -p      指定模块目录列表（空格分隔），从这些目录中搜寻 do-configure-runtime.sh
    -h, --help         显示帮助信息

说明:
    若未指定 --package，则搜索 --backend 路径的子目录，从中找到 do-configure-runtime.sh 执行

示例:
    $0                                    # 设置当前目录所有子目录
    $0 --backend ../backend               # 设置指定后端路径的所有子目录
    $0 -p "../license-manager ../costrict-system"  # 设置指定模块目录

EOF
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

configure_runtime() {
    local target_dir="$1"
    local configure_script="${target_dir}do-configure-runtime.sh"

    if [[ ! -d "$target_dir" ]]; then
        log "ERROR" "目录不存在: $target_dir"
        return 1
    fi

    if [[ ! -f "$configure_script" ]]; then
        return 0
    fi

    log "INFO" "执行 $configure_script ..."
    if bash "$configure_script"; then
        log "INFO" "$configure_script 执行成功"
    else
        log "ERROR" "$configure_script 执行失败"
        return 1
    fi

    return 0
}

configure_runtimes() {
    local dirs=("$@")

    if [[ ${#dirs[@]} -eq 0 ]]; then
        # 未指定目录，遍历后端路径下的所有子目录
        log "INFO" "开始设置 ${BACKEND_PATH} 下各模块的运行时环境..."
        for subdir in "${BACKEND_PATH}"/*/; do
            if [[ ! -d "$subdir" ]]; then
                continue
            fi
            configure_runtime "$subdir" || return 1
        done
    else
        # 指定了目录，升级指定目录
        log "INFO" "开始设置指定目录的运行时环境..."
        for dir in "${dirs[@]}"; do
            configure_runtime "$dir" || return 1
        done
    fi

    log "INFO" "运行时环境设置完成"
    return 0
}

# -------------------------- Parse Options --------------------------
BACKEND_PATH="$(pwd)"
PACKAGE_DIRS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            BACKEND_PATH="$2"
            shift 2
            ;;
        --package|-p)
            # 解析模块目录列表（空格分隔）
            IFS=' ' read -ra PACKAGE_DIRS <<< "$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            show_usage
            exit 1
            ;;
    esac
done

# -------------------------- Main Logic --------------------------
main() {
    if ! configure_runtimes "${PACKAGE_DIRS[@]}"; then
        log "ERROR" "运行时环境设置失败"
        exit 1
    fi
}

main
