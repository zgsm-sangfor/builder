#!/bin/bash
# ============================================================================
# 环境升级脚本
# ============================================================================
# 功能说明:
#   本脚本用于升级各模块的环境配置，执行以下操作：
#     1. 检查指定目录或所有子目录
#     2. 若存在 do-upgrade-env.sh 脚本，则执行该脚本
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
升级各模块的环境配置，执行各目录下的 do-upgrade-env.sh 脚本

用法: $0 [options]

选项:
    --backend <PATH>   指定后端路径，默认为当前路径
    --package, -p      指定模块目录列表（空格分隔），从这些目录中搜寻 do-upgrade-env.sh
    -h, --help         显示帮助信息

说明:
    若未指定 --package，则搜索 --backend 路径的子目录，从中找到 do-upgrade-env.sh 执行

示例:
    $0                                    # 升级当前目录所有子目录
    $0 --backend ../backend               # 升级指定后端路径的所有子目录
    $0 -p "../license-manager ../costrict-system"  # 升级指定模块目录

EOF
}

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

upgrade_env() {
    local target_dir="$1"
    local upgrade_script="${target_dir}do-upgrade-env.sh"

    if [[ ! -d "$target_dir" ]]; then
        log "ERROR" "目录不存在: $target_dir"
        return 1
    fi

    if [[ ! -f "$upgrade_script" ]]; then
        log "INFO" "$upgrade_script 不存在，跳过"
        return 0
    fi

    log "INFO" "执行 $upgrade_script ..."
    if bash "$upgrade_script"; then
        log "INFO" "$upgrade_script 执行成功"
    else
        log "ERROR" "$upgrade_script 执行失败"
        return 1
    fi

    return 0
}

upgrade_envs() {
    local dirs=("$@")

    if [[ ${#dirs[@]} -eq 0 ]]; then
        # 未指定目录，遍历后端路径下的所有子目录
        log "INFO" "开始升级 ${BACKEND_PATH} 下所有子目录的环境配置..."
        for subdir in "${BACKEND_PATH}"/*/; do
            if [[ ! -d "$subdir" ]]; then
                continue
            fi
            upgrade_env "$subdir" || return 1
        done
    else
        # 指定了目录，升级指定目录
        log "INFO" "开始升级指定目录的环境配置..."
        for dir in "${dirs[@]}"; do
            upgrade_env "$dir" || return 1
        done
    fi

    log "INFO" "环境配置升级完成"
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
    if ! upgrade_envs "${PACKAGE_DIRS[@]}"; then
        log "ERROR" "环境配置升级失败"
        exit 1
    fi
}

main
