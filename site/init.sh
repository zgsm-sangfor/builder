#!/bin/bash

#
#   在本地启动一个nginx，构建一个可供下载包的站点
#   设置cloud地址为http://localhost即可通过该站点更新软件
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="$(pwd)"

# 如果 COSTRICT_LOCAL_STORAGE 未设置，则默认为脚本所在路径的上级目录
if [ -z "${COSTRICT_LOCAL_STORAGE:-}" ]; then
    COSTRICT_LOCAL_STORAGE="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
fi
export COSTRICT_LOCAL_STORAGE

# 将 COSTRICT_LOCAL_STORAGE 的值持久化到 /root/.costrict.mirror.env，
# 供其他脚本（如 firmware 安装流程）source 读取。
MIRROR_ENV_FILE="/root/.costrict.mirror.env"
echo "COSTRICT_LOCAL_STORAGE=${COSTRICT_LOCAL_STORAGE}" > "${MIRROR_ENV_FILE}"

"${SCRIPT_DIR}/install-os-firmware.sh"
"${SCRIPT_DIR}/start-nginx.sh"

