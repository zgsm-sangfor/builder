#!/bin/bash

set -e

#
# install-mirror.sh - 安装离线镜像站点
#
# 将 mirror-site.tar 解压到脚本所在目录的 ../mirror-site 下，
# 然后进入该目录执行 init.sh 完成初始化。
#

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 源 tar 包路径（相对于脚本所在目录）
SOURCE_TAR="${SCRIPT_DIR}/mirror-site.tar"

# 目标解压目录（脚本所在目录的上级目录下的 mirror-site）
TARGET_DIR="${SCRIPT_DIR}/../mirror-site"

# 检查源文件是否存在
if [ ! -f "${SOURCE_TAR}" ]; then
    echo "错误: 找不到 ${SOURCE_TAR}" >&2
    exit 1
fi

# 创建目标目录（如不存在则创建）
mkdir -p "${TARGET_DIR}"

# 解压 tar 包到目标目录
echo "正在解压 ${SOURCE_TAR} 到 ${TARGET_DIR} ..."
tar -xf "${SOURCE_TAR}" -C "${TARGET_DIR}"

# 进入目标目录并执行 init.sh
cd "${TARGET_DIR}"

if [ ! -f "init.sh" ]; then
    echo "错误: 解压后未找到 init.sh" >&2
    exit 1
fi

echo "正在执行 init.sh ..."
bash init.sh

echo "镜像站点安装完成。"
