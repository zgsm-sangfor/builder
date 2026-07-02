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

./install-os-firmware.sh
./start-nginx.sh

