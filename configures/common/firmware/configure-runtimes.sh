#!/bin/bash
# ============================================================================
# 配置运行时环境脚本
# ============================================================================
# 功能说明:
#   本脚本用于配置 CoStrict 系统的运行时环境，执行以下操作：
#     1. 等待 APISIX 服务就绪
#     2. 配置 APISIX 路由（如 costrict-apps、costrict-admin 等）
#     3. 遍历各模块目录，执行 do-configure-runtime.sh 配置运行时环境
#
# 使用场景:
#   - 系统初始化时配置 APISIX 路由和运行时环境
#   - 系统升级后重新配置运行时环境
#
# 依赖说明:
#   - 需要 APISIX 服务已启动
#   - 需要 Docker Compose 环境已就绪
#   - 需要 configure.sh 提供 APISIX 连接配置
# ============================================================================

set -e
set -u
set -o pipefail 2>/dev/null || true

. ./configure.sh

# -------------------------- 日志 --------------------------
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

# -------------------------- 等待 APISIX 就绪 --------------------------
wait_for_apisix_ready() {
    local max_attempts=30
    local wait_seconds=2
    local attempt=1
    
    log "INFO" "等待APISIX服务启动..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "http://$APISIX_ADDR/apisix/admin/routes" -H "$AUTH" -H "$TYPE" -X GET > /dev/null 2>&1; then
            log "INFO" "APISIX服务已准备就绪，可以添加upstream配置"
            return 0
        fi
        log "INFO" "curl -s -f http://$APISIX_ADDR/apisix/admin/routes -H \"$AUTH\" -H \"$TYPE\" -X GET"
        log "INFO" "APISIX服务尚未就绪，等待${wait_seconds}秒后重试... (尝试 $attempt/$max_attempts)"
        sleep $wait_seconds
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "APISIX服务在${max_attempts}次尝试后仍未准备就绪"
    return 1
}

# -------------------------- 配置 APISIX 路由 --------------------------
configure_apisix_routes() {
    log "INFO" "配置APISIX路由..."
    
    # 等待APISIX服务就绪
    if ! wait_for_apisix_ready; then
        log "WARN" "APISIX服务启动失败，无法继续配置"
        return 1
    fi
    
    # 配置APISIX路由
    local apisix_scripts=(
        "apisix-costrict-apps.sh"
        "apisix-costrict-admin.sh"
        # "apisix-ai-gateway.sh"
        # "apisix-casdoor.sh"
        # "apisix-chatrag.sh"
        # "apisix-codereview.sh"
        # "apisix-completion-v2.sh"
        # "apisix-cotun.sh"
        # "apisix-credit-manager.sh"
        # "apisix-embedder.sh"
        # "apisix-grafana.sh"
        # "apisix-issue.sh"
        # "apisix-oidc-auth.sh"
    )
    
    for script in "${apisix_scripts[@]}"; do
        log "INFO" "执行APISIX配置: $script"
        if ! bash "$script"; then
            log "ERROR" "APISIX配置失败: $script"
            return 1
        fi
    done
    
    log "INFO" "APISIX路由配置完成"
    return 0
}

# -------------------------- 配置运行时环境 --------------------------
configure_runtimes() {
    log "INFO" "开始配置运行时环境..."

    for subdir in */; do
        if [[ ! -d "$subdir" ]]; then
            continue
        fi

        local configure_script="${subdir}do-configure-runtime.sh"
        if [[ -f "$configure_script" ]]; then
            log "INFO" "执行 $configure_script ..."
            if bash "$configure_script"; then
                log "INFO" "$configure_script 执行成功"
            else
                log "ERROR" "$configure_script 执行失败"
                return 1
            fi
        fi
    done

    log "INFO" "运行时环境配置完成"
    return 0
}

# -------------------------- Main --------------------------
main() {
    log "INFO" "开始配置运行时环境..."
    
    configure_apisix_routes || {
        log "ERROR" "APISIX路由配置失败"
        exit 1
    }
    
    configure_runtimes || {
        log "ERROR" "运行时环境配置失败"
        exit 1
    }
    
    log "INFO" "运行时环境配置全部完成"
}

main "$@"
