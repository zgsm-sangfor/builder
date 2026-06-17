#!/bin/bash
# ============================================================================
# 离线安装 docker / docker compose / jq
# ============================================================================
# 功能说明:
#   参照 configures/common/firmware/check.sh 的版本检测方法，依次检测
#   docker、docker compose、jq 三个命令是否已安装且版本满足要求：
#     - 命令未安装或版本过低时，使用随包提供的离线二进制进行安装；
#     - 命令已安装且版本满足要求时，跳过该命令的离线安装。
#
# 使用方式:
#   在存放离线包的目录中执行（脚本会自动定位同目录下的离线文件）。
#   注意: 需要 root 权限（写入 /usr/bin、注册 systemd 服务等）。
# ============================================================================

set -e
set -u
set -o pipefail 2>/dev/null || true

# -------------------------- 版本要求 --------------------------
BASE_URL="https://zgsm.sangfor.com"
MIN_DOCKER_VERSION="19.0"     # docker 最低版本
MIN_COMPOSE_VERSION="2.0.0"   # docker compose 最低版本
MIN_JQ_VERSION="1.5"          # jq 最低版本

# -------------------------- 运行目录（定位离线包） --------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$(pwd)"

# -------------------------- 日志 --------------------------
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

# -------------------------- 工具函数 --------------------------
# 获取命令版本号 (形如 x.y 或 x.y.z)；无法获取时返回空字符串。
# 参照 check.sh: 用 "<cmd> --version" 取首行并提取首个版本号。
get_version() {
    local cmd=$1
    local version_line
    version_line=$(eval "$cmd --version" 2>/dev/null | head -1 || true)
    if [ -n "$version_line" ]; then
        echo "$version_line" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true
    fi
}

# 版本比较: 当 $1 >= $2 时返回 0(true)，否则返回 1(false)。
# 支持两段或三段版本号 (不足位补 0)。
version_ge() {
    local v1=$1 v2=$2
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<< "$v1"
    IFS=. read -r b1 b2 b3 <<< "$v2"
    a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
    b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
    if [ "$a1" -gt "$b1" ]; then return 0; fi
    if [ "$a1" -lt "$b1" ]; then return 1; fi
    if [ "$a2" -gt "$b2" ]; then return 0; fi
    if [ "$a2" -lt "$b2" ]; then return 1; fi
    [ "$a3" -ge "$b3" ]
}

# -------------------------- 下载 --------------------------
# 从远端下载文件到当前目录，若本地已存在则跳过下载
download_file() {
    local file_name=$1
    local url="${BASE_URL}/costrict-static/linux/${URL_ARCH}/${file_name}"

    if [ -f "$SCRIPT_DIR/$file_name" ]; then
        log "INFO" "文件已存在，跳过下载: $file_name"
        return 0
    fi

    log "INFO" "正在下载: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$SCRIPT_DIR/$file_name" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$SCRIPT_DIR/$file_name" "$url"
    else
        log "ERROR" "未找到 curl 或 wget，无法下载文件"
        return 1
    fi
    log "INFO" "下载完成: $file_name"
}

# -------------------------- 安装: docker --------------------------
install_docker() {
    download_file "$DOCKER_TGZ" || return 1
    local tgz="$SCRIPT_DIR/$DOCKER_TGZ"
    log "INFO" "开始离线安装 docker (包: $tgz)..."
    [ -f "$tgz" ] || { log "ERROR" "docker 离线包不存在: $tgz"; return 1; }

    # 解压并转存
    tar -zxvf "$tgz" -C /tmp
    cp -f /tmp/docker/* /usr/bin/

    # 注册 docker systemd 服务
    cat > /etc/systemd/system/docker.service << 'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd --selinux-enabled=false --insecure-registry=127.0.0.1
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

    chmod 777 /etc/systemd/system/docker.service
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker

    log "INFO" "docker 安装完成，版本: $(docker -v 2>/dev/null)"
}

# -------------------------- 安装: docker compose --------------------------
install_compose() {
    download_file "$COMPOSE_BIN" || return 1
    local src="$SCRIPT_DIR/$COMPOSE_BIN"
    log "INFO" "开始离线安装 docker compose (二进制: $src)..."
    [ -f "$src" ] || { log "ERROR" "docker compose 离线二进制不存在: $src"; return 1; }

    # 安装为独立命令 docker-compose
    cp -f "$src" /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    # 软链接到 /usr/bin 以便全局可用
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    # 同时安装为 docker 插件，使 `docker compose` 子命令可用
    local cli_plugins_dir="${HOME}/.docker/cli-plugins"
    mkdir -p "$cli_plugins_dir"
    cp -f "$src" "$cli_plugins_dir/docker-compose"
    chmod +x "$cli_plugins_dir/docker-compose"

    log "INFO" "docker compose 安装完成，版本: $(docker-compose version 2>/dev/null | head -1)"
}

# -------------------------- 安装: jq --------------------------
install_jq() {
    download_file "$JQ_BIN" || return 1
    local src="$SCRIPT_DIR/$JQ_BIN"
    log "INFO" "开始离线安装 jq (二进制: $src)..."
    [ -f "$src" ] || { log "ERROR" "jq 离线二进制不存在: $src"; return 1; }

    cp -f "$src" /usr/bin/jq
    chmod +x /usr/bin/jq

    log "INFO" "jq 安装完成，版本: $(jq --version 2>/dev/null)"
}

# -------------------------- 主流程 --------------------------
main() {
    log "INFO" "开始离线环境检测与安装..."

    # root 权限检查
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "此脚本需要 root 权限运行，请使用 sudo 或 root 用户执行"
        exit 1
    fi

    # 根据系统架构选择对应的离线包文件名
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            URL_ARCH="amd64"
            DOCKER_TGZ="docker-20.10.24-x86-64.tgz"
            COMPOSE_BIN="docker-compose-linux-x86_64"
            JQ_BIN="jq-linux-amd64"
            ;;
        aarch64|arm64)
            URL_ARCH="arm64"
            DOCKER_TGZ="docker-20.10.24-aarch64.tgz"
            COMPOSE_BIN="docker-compose-linux-aarch64"
            JQ_BIN="jq-linux-arm64"
            ;;
        *)
            log "ERROR" "不支持的系统架构: $ARCH"
            exit 1
            ;;
    esac
    log "INFO" "当前架构: $ARCH"

    local install_failed=0

    # ======================== docker ========================
    local docker_version
    docker_version=$(get_version docker)
    if [ -z "$docker_version" ]; then
        log "WARN" "未检测到 docker 命令，将进行离线安装"
        install_docker || { log "ERROR" "docker 离线安装失败"; install_failed=1; }
    elif version_ge "$docker_version" "$MIN_DOCKER_VERSION"; then
        log "INFO" "docker 已安装 (版本 $docker_version >= $MIN_DOCKER_VERSION)，跳过离线安装"
    else
        log "WARN" "docker 版本过低 ($docker_version < $MIN_DOCKER_VERSION)，将进行离线安装"
        install_docker || { log "ERROR" "docker 离线安装失败"; install_failed=1; }
    fi

    # docker 服务状态检查（非致命）
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            log "INFO" "docker 服务运行正常"
        else
            log "WARN" "docker 已安装但服务未运行或无权限访问，请检查: systemctl status docker"
        fi
    fi

    # ======================== docker compose ========================
    # 优先检测插件形式 `docker compose`，其次检测独立命令 `docker-compose`
    local compose_version=""
    if docker compose version >/dev/null 2>&1; then
        compose_version=$(get_version "docker compose")
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_version=$(get_version docker-compose)
    fi

    if [ -z "$compose_version" ]; then
        log "WARN" "未检测到 docker compose 命令，将进行离线安装"
        install_compose || { log "ERROR" "docker compose 离线安装失败"; install_failed=1; }
    elif version_ge "$compose_version" "$MIN_COMPOSE_VERSION"; then
        log "INFO" "docker compose 已安装 (版本 $compose_version >= $MIN_COMPOSE_VERSION)，跳过离线安装"
    else
        log "WARN" "docker compose 版本过低 ($compose_version < $MIN_COMPOSE_VERSION)，将进行离线安装"
        install_compose || { log "ERROR" "docker compose 离线安装失败"; install_failed=1; }
    fi

    # ======================== jq ========================
    local jq_version
    jq_version=$(get_version jq)
    if [ -z "$jq_version" ]; then
        log "WARN" "未检测到 jq 命令，将进行离线安装"
        install_jq || { log "ERROR" "jq 离线安装失败"; install_failed=1; }
    elif version_ge "$jq_version" "$MIN_JQ_VERSION"; then
        log "INFO" "jq 已安装 (版本 $jq_version >= $MIN_JQ_VERSION)，跳过离线安装"
    else
        log "WARN" "jq 版本过低 ($jq_version < $MIN_JQ_VERSION)，将进行离线安装"
        install_jq || { log "ERROR" "jq 离线安装失败"; install_failed=1; }
    fi

    if [ "$install_failed" -eq 1 ]; then
        log "ERROR" "部分组件安装失败，请检查上述错误日志"
        exit 1
    fi
    log "INFO" "所有组件检测与安装完成"
}

main "$@"
