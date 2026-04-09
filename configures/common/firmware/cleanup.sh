#!/bin/bash
# ============================================================================
# 系统卸载脚本
# ============================================================================
# 功能说明:
#   本脚本用于卸载 CoStrict 系统，执行以下操作：
#     1. 停止并移除所有 Docker 容器和网络
#     2. 删除系统配置文件和脚本
#     3. 清理初始化标识文件
#     4. 可选删除数据存储目录（默认保留）
#     5. 清理 Docker 镜像和卷（可选）
#
# 使用场景:
#   - 完全卸载 CoStrict 系统
#   - 清理系统以进行重新安装
#   - 清理测试环境
#
# 依赖说明:
#   - 需要安装 Docker 和 Docker Compose
#   - 需要 bash 4.0 或更高版本
#   - 需要 root 权限（用于删除系统目录）
#
# 注意事项:
#   - 卸载操作不可逆，请谨慎操作
#   - 默认删除数据存储目录，如需保留请使用 --keep-data 或单独保留数据库 --keep-db 
#   - 建议在卸载前使用 backup.sh 备份数据
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
    卸载 CoStrict 系统，停止并移除容器、删除配置文件、清理系统
    
    用法: $0 [选项]
    
    选项:
        --keep-data        保留数据存储目录，不删除数据
        --keep-db          保留数据存储目录下的数据库文件，仅保留 costrict-admin.db
        -f, --force        跳过确认提示，直接执行卸载
        -h, --help         显示帮助信息
    
    说明:
        安装目录和数据路径从安装环境文件 /root/.costrict.install.env 中读取。
    
    示例:
        $0                                          # 卸载系统
        $0 --keep-data                              # 保留数据存储目录
        $0 --keep-db                                # 保留数据库文件
        $0 -f                                       # 跳过确认，直接卸载
    
EOF
}

parse_arguments() {
    KEEP_DATA=false
    KEEP_DB=false
    SKIP_CONFIRM=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            --keep-db)
                KEEP_DB=true
                shift
                ;;
            -f|--force)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

confirm_uninstall() {
    if [ "$SKIP_CONFIRM" = true ]; then
        return 0
    fi
    
    log "WARN" "即将卸载 CoStrict 系统！"
    log "WARN" "此操作将："
    log "WARN" "  1. 停止所有相关 Docker 服务"
    log "WARN" "  2. 移除所有系统服务"
    log "WARN" "  3. 删除安装目录: $COSTRICT_BACKEND_DIR"
    if [ "$KEEP_DATA" = false ]; then
        if [ "$KEEP_DB" = true ]; then
            log "INFO" "  6. 删除数据存储目录（保留 costrict-admin.db）: $COSTRICT_DATA_DIR"
        else
            log "WARN" "  6. 删除数据存储目录: $COSTRICT_DATA_DIR"
        fi
    else
        log "INFO" "  6. 保留数据存储目录: $COSTRICT_DATA_DIR"
    fi
    
    echo ""
    read -p "确认卸载？请输入 'yes' 继续: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "INFO" "卸载操作已取消"
        exit 0
    fi
}

stop_docker_services() {
    log "INFO" "开始停止 Docker Compose 运行的服务..."
    
    # 检查安装目录是否存在
    if [[ ! -d "$COSTRICT_BACKEND_DIR" ]]; then
        log "WARN" "安装目录不存在，跳过停止服务: $COSTRICT_BACKEND_DIR"
        return 0
    fi
    
    # 切换到安装目录
    cd "$COSTRICT_BACKEND_DIR" || {
        log "WARN" "无法切换到安装目录: $COSTRICT_BACKEND_DIR"
        return 0
    }
    
    # 检查 docker-compose.yml 是否存在
    if [[ ! -f "docker-compose.yml" ]]; then
        log "WARN" "docker-compose.yml 文件不存在，跳过停止服务"
        cd - >/dev/null
        return 0
    fi
    
    # 检查 Docker 是否可用
    if ! command -v docker >/dev/null 2>&1; then
        log "WARN" "Docker未安装，跳过停止服务"
        cd - >/dev/null
        return 0
    fi
    
    # 检查 Docker 服务是否运行
    if ! docker info >/dev/null 2>&1; then
        log "WARN" "Docker服务未运行，跳过停止服务"
        cd - >/dev/null
        return 0
    fi
    
    # 停止 Docker Compose 服务
    if docker-compose -f docker-compose.yml down 2>/dev/null; then
        log "INFO" "Docker Compose 服务已停止"
    else
        log "WARN" "Docker Compose 服务停止失败，但继续卸载"
    fi
    
    # 切换回原目录
    cd - >/dev/null
    return 0
}

unregister_services() {
    local initd_dir="${COSTRICT_BACKEND_DIR}/init.d"
    
    # 检查 init.d 目录是否存在
    if [[ ! -d "$initd_dir" ]]; then
        log "INFO" "未找到 init.d 目录，跳过服务注销"
        return 0
    fi
    
    log "INFO" "开始注销系统服务..."
    
    # 遍历 init.d 目录下的所有脚本
    for service_script in "$initd_dir"/*; do
        if [[ ! -f "$service_script" ]]; then
            continue
        fi
        
        local service_name=$(basename "$service_script")
        local sys_initd_path="/etc/init.d/${service_name}"
        
        # 检查系统目录中是否存在该服务
        if [[ ! -e "$sys_initd_path" ]]; then
            continue
        fi
        
        log "INFO" "注销服务: $service_name"
        
        # 停止服务
        if sudo service "$service_name" status >/dev/null 2>&1; then
            sudo service "$service_name" stop 2>/dev/null || true
            log "INFO" "服务 $service_name 已停止"
        fi
        
        # 注销开机自启
        if command -v chkconfig >/dev/null 2>&1; then
            # 使用 chkconfig (CentOS/RHEL)
            sudo chkconfig "$service_name" off 2>/dev/null || true
            sudo chkconfig --del "$service_name" 2>/dev/null || true
            log "INFO" "服务 $service_name 已注销开机自启 (chkconfig)"
        elif command -v update-rc.d >/dev/null 2>&1; then
            # 使用 update-rc.d (Debian/Ubuntu)
            sudo update-rc.d -f "$service_name" remove 2>/dev/null || true
            log "INFO" "服务 $service_name 已注销开机自启 (update-rc.d)"
        fi
        
        # 删除系统服务脚本
        sudo rm -f "$sys_initd_path"
        
        log "INFO" "服务 $service_name 注销成功"
    done
    
    return 0
}

remove_backend_dir() {
    log "INFO" "检查并删除安装目录..."
    
    if [[ -d "$COSTRICT_BACKEND_DIR" ]]; then
        log "INFO" "删除目录: $COSTRICT_BACKEND_DIR"
        sudo rm -rf "$COSTRICT_BACKEND_DIR"
        log "INFO" "已删除: $COSTRICT_BACKEND_DIR"
    else
        log "INFO" "目录不存在: $COSTRICT_BACKEND_DIR"
    fi
}

remove_data_dir() {
    if [ "$KEEP_DATA" = true ]; then
        log "INFO" "根据 --keep-data 选项，保留数据存储目录: $COSTRICT_DATA_DIR"
        return 0
    fi
    
    # 备份数据库文件（如果启用 --keep-db 选项）
    local db_file="${COSTRICT_DATA_DIR}/data/costrict-admin/costrict-admin.db"
    local bak_file="${COSTRICT_BACKEND_DIR}/costrict-admin.db.bak"
    
    if [ "$KEEP_DB" = true ]; then
        if [[ -f "$db_file" ]]; then
            log "INFO" "准备备份数据库文件 $db_file 到 $bak_file"
            sudo cp "$db_file" "$bak_file"
            if [ $? -eq 0 ]; then
                log "INFO" "数据库文件备份成功"
            else
                log "ERROR" "数据库文件备份失败"
                return 1
            fi
        else
            log "WARN" "数据库文件不存在: $db_file，跳过备份"
        fi
    fi
    
    log "INFO" "检查并删除数据存储目录..."
    
    if [[ -d "$COSTRICT_DATA_DIR" ]]; then
        log "INFO" "删除目录: $COSTRICT_DATA_DIR"
        sudo rm -rf "$COSTRICT_DATA_DIR"
        log "INFO" "已删除: $COSTRICT_DATA_DIR"
        
        # 恢复数据库文件（如果启用 --keep-db 选项）
        if [ "$KEEP_DB" = true ]; then
            if [[ -f "$bak_file" ]]; then
                log "INFO" "恢复数据库文件: $bak_file"
                # 创建目标目录
                sudo mkdir -p "$(dirname "$db_file")"
                # 恢复数据库文件
                sudo cp "$bak_file" "$db_file"
                if [ $? -eq 0 ]; then
                    log "INFO" "数据库文件恢复成功"
                    # 设置文件权限
                    sudo chmod 644 "$db_file"
                else
                    log "ERROR" "数据库文件恢复失败"
                fi
                # 清理备份目录
                sudo rm -f "$bak_file"
                log "INFO" "已清理备份目录: $bak_file"
            else
                log "WARN" "备份的数据库文件 $bak_file 不存在，无法恢复"
            fi
        fi
    else
        log "INFO" "目录不存在: $COSTRICT_DATA_DIR"
    fi
}


# -------------------------- Main Logic --------------------------
main() {
    log "INFO" "卸载脚本启动，日志文件: $LOG_FILE"
    
    # 解析命令行参数
    parse_arguments "$@"
    load_install_env
    # 确认卸载
    confirm_uninstall
    
    # 停止 Docker 服务
    if ! stop_docker_services; then
        log "WARN" "停止 Docker 服务出现问题，但继续卸载"
    fi
    
    # 注销系统服务
    if ! unregister_services; then
        log "WARN" "注销服务出现问题，但继续卸载"
    fi
    
    remove_data_dir
    remove_backend_dir
    
    log "INFO" "系统卸载完成！"
    log "INFO" "已清理内容："
    log "INFO" "  - Docker 服务已停止"
    log "INFO" "  - 系统服务已注销"
    log "INFO" "  - 系统安装目录已删除: $COSTRICT_BACKEND_DIR"
    if [ "$KEEP_DATA" = false ]; then
        if [ "$KEEP_DB" = true ]; then
            log "INFO" "  - 数据存储目录已删除（已保留 costrict-admin.db）: $COSTRICT_DATA_DIR"
            log "INFO" "  - 数据库文件已恢复到: ${COSTRICT_DATA_DIR}/data/costrict-admin/costrict-admin.db"
        else
            log "INFO" "  - 数据存储目录已删除: $COSTRICT_DATA_DIR"
        fi
    else
        log "INFO" "  - 数据存储目录已保留: $COSTRICT_DATA_DIR"
    fi
}

main "$@"
