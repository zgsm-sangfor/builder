#!/bin/bash


log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

docker-compose() {
    if docker compose version >/dev/null 2>&1; then
        command docker compose "$@"
    else
        command docker-compose "$@"
    fi
}

gen_env_files() {
    log "INFO" "生成环境变量文件: .images.env,.images.list,.env..."
    
    if bash scripts/gen-env-file.sh; then
        log "INFO" "环境变量文件生成成功: .images.env,.images.list,.env"
        return 0
    else
        log "ERROR" "环境变量文件生成失败: .images.env,.images.list,.env"
        return 1
    fi
}

load_install_env() {
    local install_env_file="/root/.costrict.install.env"
    log "INFO" "读取安装环境配置: $install_env_file"
    if [[ -f "$install_env_file" ]]; then
        source "$install_env_file"
    fi
    if [[ -z "${COSTRICT_BACKEND_DIR}" ]]; then
        COSTRICT_BACKEND_DIR="/usr/local/costrict"
    fi
    if [[ -z "${COSTRICT_DATA_DIR}" ]]; then
        COSTRICT_DATA_DIR="$HOME/.costrict"
    fi
    if [[ -z "${COSTRICT_BACKEND_TYPE}" ]]; then
        COSTRICT_BACKEND_TYPE="compose"
    fi

    if [[ ! "$COSTRICT_BACKEND_DIR" = /* ]]; then
        log "ERROR" "系统安装目录必须是绝对路径: $COSTRICT_BACKEND_DIR"
        log "ERROR" "请使用绝对路径，例如: /usr/local/costrict"
        exit 1
    fi
    
    if [[ ! "$COSTRICT_DATA_DIR" = /* ]]; then
        log "ERROR" "数据存储目录必须是绝对路径: $COSTRICT_DATA_DIR"
        log "ERROR" "请使用绝对路径，例如: /data/costrict"
        exit 1
    fi
    
    log "INFO" "系统安装目录: $COSTRICT_BACKEND_DIR"
    log "INFO" "数据存储目录: $COSTRICT_DATA_DIR"
}
# 这个工具脚本不检查安装目录
# load_install_env
