#!/bin/bash

# 备份costrict后端系统
#
# 功能：备份整个costrict后端系统，包括docker compose环境、数据目录和Docker镜像
#
# 使用方法：
#   ./backup.sh [OPTIONS]
#   或
#   bash backup.sh --output /path/to/output
#
# 支持的选项：
#   --output      备份输出目录，备份文件将保存在此目录下
#                 默认值: ./backup_YYYY-MM-DD_HH-MM-SS
#
# 备份步骤：
#   1. 从安装环境配置文件加载 COSTRICT_BACKEND_DIR 和 COSTRICT_DATA_DIR
#   2. 调用 $COSTRICT_BACKEND_DIR/run.sh stop 停止docker compose服务
#   3. 调用 service costrict-daemon stop 停止costrict-daemon服务
#   4. 拷贝目录 $COSTRICT_BACKEND_DIR 的所有内容到 $output/backend 下
#   5. 拷贝目录 $COSTRICT_DATA_DIR 的所有内容到 $output/data 下
#   6. 调用 $COSTRICT_BACKEND_DIR/scripts/save-images.sh 将Docker镜像备份到 $output/images 下
#
# 输出结构：
#   $output/
#   ├── backend/          # 后端docker compose环境备份
#   ├── data/             # costrict数据目录备份
#   └── images/           # Docker镜像备份（tar文件）
#
# 示例：
#   # 使用默认设置进行备份
#   ./backup.sh
#
#   # 指定输出目录
#   ./backup.sh --output /mnt/backup/costrict_backup_2024
#
# 注意事项：
#   - 本脚本需要root权限执行，因为涉及服务停止和系统目录复制
#   - 备份前会停止相关服务，请确保在低峰期执行
#   - 确保输出目录有足够的磁盘空间（通常需要数GB到数十GB）
#   - 备份过程可能需要较长时间，取决于数据量和镜像大小
#   - 备份完成后可以通过restore.sh脚本将系统恢复到备份时的状态
#
# 依赖脚本：
#   - $COSTRICT_BACKEND_DIR/run.sh: 用于停止/启动docker compose服务
#   - $COSTRICT_BACKEND_DIR/scripts/save-images.sh: 用于备份Docker镜像
#
#
################################################################################

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
用法: $0 [选项]

选项:
    --output <path>    输出目录，默认为 ./backup_YYYY-MM-DD_HH-MM-SS
    -f, --force        跳过确认提示，默认为 false
    -h, --help         显示帮助信息

示例:
    $0                                          # 使用默认设置备份
    $0 --output /mnt/backup/costrict_2024        # 指定输出目录
    $0 --force                                   # 跳过确认提示

说明:
    本脚本用于备份costrict后端系统，包括：
    - docker compose环境
    - costrict数据目录
    - Docker镜像

    后端目录和数据目录通过安装环境配置文件自动加载。

    备份完成后可通过 restore.sh 脚本恢复。

EOF
}

# -------------------------- Constants Definition --------------------------
declare -r DEFAULT_OUTPUT_DIR="./backup_$(date +%Y-%m-%d_%H-%M-%S)"

parse_arguments() {
    # 默认值
    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
    SKIP_CONFIRM=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output)
                OUTPUT_DIR="$2"
                shift 2
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

    log "INFO" "后端目录: $COSTRICT_BACKEND_DIR"
    log "INFO" "数据目录: $COSTRICT_DATA_DIR"
    log "INFO" "输出目录: $OUTPUT_DIR"
}

check_root_permission() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "本脚本需要root权限执行"
        return 1
    fi
    log "INFO" "Root权限检查通过"
    return 0
}

check_prerequisites() {
    local missing_items=()
    
    # 检查backend目录
    if [[ ! -d "$COSTRICT_BACKEND_DIR" ]]; then
        missing_items+=("后端目录: $COSTRICT_BACKEND_DIR")
    fi
    
    # 检查数据目录
    if [[ ! -d "$COSTRICT_DATA_DIR" ]]; then
        missing_items+=("数据目录: $COSTRICT_DATA_DIR")
    fi
    
    # 检查必要脚本
    if [[ ! -f "$COSTRICT_BACKEND_DIR/run.sh" ]]; then
        missing_items+=("脚本: $COSTRICT_BACKEND_DIR/run.sh")
    fi
    
    if [[ ! -f "$COSTRICT_BACKEND_DIR/scripts/save-images.sh" ]]; then
        missing_items+=("脚本: $COSTRICT_BACKEND_DIR/scripts/save-images.sh")
    fi
    
    if [[ ${#missing_items[@]} -gt 0 ]]; then
        log "ERROR" "前置条件检查失败，以下项目缺失:"
        for item in "${missing_items[@]}"; do
            log "ERROR" "  - ${item}"
        done
        return 1
    fi
    
    log "INFO" "前置条件检查通过"
    return 0
}

confirm_backup() {
    if [ "$SKIP_CONFIRM" = true ]; then
        return 0
    fi
    
    log "WARN" "备份 CoStrict 系统需要先停止所有服务！"
    log "WARN" "继续备份将: "
    log "WARN" "  1. 停止所有相关 Docker Compose 运行的服务"
    log "WARN" "  2. 停止所有相关的系统服务，如costrict-daemon"
    
    echo ""
    read -p "确认继续备份吗？请输入 'yes' 继续: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "INFO" "备份操作已取消"
        exit 0
    fi
}

stop_docker_compose_services() {
    log "INFO" "停止docker compose服务..."
    if bash run.sh stop; then
        log "INFO" "docker compose服务已停止"
        return 0
    else
        log "ERROR" "docker compose服务停止失败"
        return 1
    fi
}

stop_costrict_daemon_service() {
    log "INFO" "停止costrict-daemon服务..."
    if service costrict-daemon status >/dev/null 2>&1; then
        if service costrict-daemon stop; then
            log "INFO" "costrict-daemon服务已停止"
        else
            log "WARN" "costrict-daemon服务停止失败"
        fi
    else
        log "INFO" "costrict-daemon服务未运行，跳过"
    fi
    return 0
}

init_output_directory() {
    # 检查输出目录是否不存在或为空
    if [[ -d "$OUTPUT_DIR" ]]; then
        local file_count
        file_count=$(find "$OUTPUT_DIR" -maxdepth 1 -mindepth 1 | wc -l)
        if [[ "$file_count" -gt 0 ]]; then
            log "ERROR" "输出目录已存在且不为空: $OUTPUT_DIR"
            exit 1
        fi
    fi

    # 创建输出目录
    if ! mkdir -p "$OUTPUT_DIR"; then
        log "ERROR" "输出目录创建失败: $OUTPUT_DIR"
        exit 1
    fi
    # 转为绝对路径（目录已存在，可直接cd进入）
    OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    
    log "INFO" "创建输出目录: $OUTPUT_DIR"
}

backup_backend_directory() {
    log "INFO" "备份backend目录..."
    log "INFO" "源目录: $COSTRICT_BACKEND_DIR"
    log "INFO" "目标目录: $OUTPUT_DIR/backend"
    
    if cp -rp "$COSTRICT_BACKEND_DIR" "$OUTPUT_DIR/backend"; then
        log "INFO" "backend目录备份完成"
        return 0
    else
        log "ERROR" "backend目录备份失败"
        return 1
    fi
    cp "$COSTRICT_BACKEND_DIR/.costrict.env" "$OUTPUT_DIR/backend/"
}

backup_data_directory() {
    log "INFO" "备份costrict数据目录..."
    log "INFO" "源目录: $COSTRICT_DATA_DIR"
    log "INFO" "目标目录: $OUTPUT_DIR/data"
    
    if cp -rp "$COSTRICT_DATA_DIR" "$OUTPUT_DIR/data"; then
        log "INFO" "数据目录备份完成"
        return 0
    else
        log "ERROR" "数据目录备份失败"
        return 1
    fi
}

backup_docker_images() {
    log "INFO" "备份Docker镜像..."
    local images_dir="$OUTPUT_DIR/images"
    
    # 清理并创建images目录
    if [[ -d "$images_dir" ]]; then
        rm -rf "$images_dir"
    fi
    mkdir -p "$images_dir"
    
    cd "$COSTRICT_BACKEND_DIR" || return 1
    if bash scripts/save-images.sh -f .images.list -s "$images_dir"; then
        log "INFO" "Docker镜像备份完成"
        return 0
    else
        log "ERROR" "Docker镜像备份失败"
        return 1
    fi
}

generate_manifest() {
    log "INFO" "生成备份清单..."
    cat > "$OUTPUT_DIR/MANIFEST.txt" <<EOF
Costrict后端系统备份清单
========================
备份时间: $(date)
备份服务器: $(hostname)
后端目录: $COSTRICT_BACKEND_DIR
数据目录: $COSTRICT_DATA_DIR

目录结构:
  backend/  - 后端目录的备份，包含后端docker compose的运行环境
  data/     - 数据目录的备份，包含各服务的持久化数据，比如下载包
  images/   - Docker镜像备份（tar文件）

恢复方法:
  # 假设已经把 $OUTPUT_DIR 目录内容完整拷贝到目标机器的  $OUTPUT_DIR 目录
  costrict-admin restore --source $OUTPUT_DIR

注意事项:
  - 恢复前确保满足系统和硬件要求
  - 版本兼容性: 备份和恢复的costrict版本应保持一致
  - 需要root权限执行恢复
EOF
    log "INFO" "备份清单已生成: $OUTPUT_DIR/MANIFEST.txt"
}

show_backup_summary() {
    log "INFO" "======================================"
    log "INFO" "备份完成！"
    log "INFO" "======================================"
    log "INFO" "备份位置: $OUTPUT_DIR"
    log "INFO" ""
    log "INFO" "目录大小:"
    du -sh "$OUTPUT_DIR"/* 2>/dev/null | while read -r line; do
        log "INFO" "  $line"
    done
    log "INFO" ""
    log "INFO" "后续操作:"
    log "INFO" "  可以将 $OUTPUT_DIR 目录传输到备份服务器"
    log "INFO" "  或者使用以下命令恢复: costrict-admin restore --source $OUTPUT_DIR"
    log "INFO" "======================================"
}

# -------------------------- Main Execution --------------------------
main() {
    log "INFO" "======================================"
    log "INFO" "开始备份 costrict 后端系统"
    log "INFO" "======================================"
    
    # 加载安装环境配置
    load_install_env
    # 解析参数
    parse_arguments "$@"
    confirm_backup
    # 检查root权限
    if ! check_root_permission; then
        exit 1
    fi
    
    # 检查前置条件
    if ! check_prerequisites; then
        exit 1
    fi

    init_output_directory

    cd "$COSTRICT_BACKEND_DIR" || return 1
    
    # 执行备份
    stop_docker_compose_services
    stop_costrict_daemon_service
    backup_backend_directory
    backup_data_directory
    backup_docker_images
    generate_manifest
    
    # 显示汇总信息
    show_backup_summary
    
    log "INFO" "备份流程全部完成"
}

main "$@"
exit 0
