#!/bin/bash

. ./utils.sh

# 检查 .images.env 和 .images.list 是否存在，如果缺少则调用 gen-env-file.sh
if [ ! -f ".images.env" ] || [ ! -f ".images.list" ]; then
    log "INFO" "缺少镜像环境文件或镜像列表文件，开始生成..."
    bash scripts/gen-env-file.sh
else
    log "INFO" "镜像环境文件'.images.env'和镜像列表文件'.images.list'已存在，跳过生成"
fi

# 验证镜像是否存在
log "INFO" "验证镜像..."
bash scripts/verify-images.sh -f .images.list
status=$?

# 根据验证结果决定是否拉取镜像
if [ $status -eq 0 ]; then
    log "INFO" "所有镜像已存在，跳过拉取"
    exit 0
fi

# 依次判断三种镜像来源设置，按优先级采用对应的方式加载镜像
# 优先级1: COSTRICT_DOCKER_IMAGES - 从指定本地目录加载镜像文件
if [ -n "${COSTRICT_DOCKER_IMAGES}" ]; then
    log "INFO" "检测到 COSTRICT_DOCKER_IMAGES='${COSTRICT_DOCKER_IMAGES}'，从该路径加载镜像..."
    bash scripts/load-images.sh -l "${COSTRICT_DOCKER_IMAGES}"
    bash scripts/verify-images.sh -f .images.list
    exit $?
fi

# 优先级2: COSTRICT_DOCKER_URL - 从HTTP服务器下载镜像到./images目录，然后加载
if [ -n "${COSTRICT_DOCKER_URL}" ]; then
    log "INFO" "检测到 COSTRICT_DOCKER_URL='${COSTRICT_DOCKER_URL}'，从HTTP服务器下载镜像..."
    bash scripts/fetch-images.sh -b "${COSTRICT_DOCKER_URL}" -f .images.list -o ./images
    bash scripts/verify-images.sh -f .images.list
    exit $?
fi

# 优先级3: COSTRICT_DOCKER_HUB - 从Docker Hub/Harbor仓库拉取镜像
if [ -n "${COSTRICT_DOCKER_HUB}" ]; then
    log "INFO" "检测到 COSTRICT_DOCKER_HUB='${COSTRICT_DOCKER_HUB}'，从Docker仓库拉取镜像..."
    bash scripts/pull-images.sh --proxy "${COSTRICT_DOCKER_HUB}" -f .images.list
    bash scripts/verify-images.sh -f .images.list
    exit $?
fi

if [ -n "${COSTRICT_MIRROR}" ]; then
    log "INFO" "检测到 COSTRICT_MIRROR='${COSTRICT_MIRROR}'，从HTTP服务器下载镜像..."
    bash scripts/fetch-images.sh -b "${COSTRICT_MIRROR}/shenma-images" -f .images.list -o ./images
    bash scripts/verify-images.sh -f .images.list
    exit $?
fi

# 默认: 未设置任何镜像来源，从Docker仓库拉取
log "INFO" "未设置镜像来源变量，默认从Docker仓库拉取..."
bash scripts/pull-images.sh -f .images.list
bash scripts/verify-images.sh -f .images.list
exit $?
