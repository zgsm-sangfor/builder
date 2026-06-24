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
LOG_FILE="${SCRIPT_NAME%.*}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

. ./utils.sh

show_usage() {
    cat << EOF
升级各模块的环境配置，执行各目录下的 do-upgrade-env.sh 脚本

用法: $0 [目录...]

参数:
    目录        要检查的目录路径，默认为当前目录下的所有子目录

示例:
    $0                                    # 升级当前目录所有子目录
    $0 ../license-manager                 # 升级指定目录
    $0 ../license-manager ../costrict-system  # 升级多个指定目录

EOF
}

upgrade_env() {
    local target_dir="$1"
    local upgrade_script="${target_dir}/do-upgrade-env.sh"

    if [[ ! -d "$target_dir" ]]; then
        log "ERROR" "目录不存在: $target_dir"
        return 1
    fi

    if [[ ! -f "$upgrade_script" ]]; then
        log "WARN" "$upgrade_script 不存在，跳过"
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
        # 未指定目录，遍历当前目录下的所有子目录
        log "INFO" "开始升级所有子目录的环境配置..."
        for subdir in */; do
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

# -------------------------- Main Logic --------------------------
main() {
    log "INFO" "升级脚本启动，日志文件: $LOG_FILE"

    if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
        show_usage
        exit 0
    fi

    if ! upgrade_envs "$@"; then
        log "ERROR" "环境配置升级失败"
        exit 1
    fi
}

main "$@"
