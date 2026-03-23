#!/bin/sh

log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

log "INFO" "生成镜像环境文件‘.images.env’和镜像列表文件‘.images.list’"
bash scripts/gen-env-file.sh

# 验证镜像是否存在
log "INFO" "验证镜像..."
bash scripts/verify-images.sh -f .images.list
status=$?

# 根据验证结果决定是否拉取镜像
if [ $status -eq 0 ]; then
    log "INFO" "所有镜像已存在，跳过拉取"
    exit 0
else
    log "INFO" "部分镜像不存在，开始拉取..."
    bash scripts/pull-images.sh -f .images.list
    bash scripts/verify-images.sh -f .images.list
    exit $?
fi
