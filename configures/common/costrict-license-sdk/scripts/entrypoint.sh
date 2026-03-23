#!/bin/bash
set -e

# 创建日志目录
mkdir -p /var/log/sf_license

# 信号处理函数
shutdown() {
    echo "正在停止所有服务..."
    kill -TERM $MAIN_PID $RESTAPI_PID $PROXY_PID 2>/dev/null || true
    wait $MAIN_PID $RESTAPI_PID $PROXY_PID 2>/dev/null || true
    exit 0
}

trap shutdown SIGTERM SIGINT SIGQUIT

echo "启动 sf_license 主进程..."
/usr/local/platos/app/sf_license/bin/sf_license_env /usr/local/platos/app/sf_license/bin/sf_license --app &
MAIN_PID=$!
echo "主进程 PID: $MAIN_PID"

echo "启动 sf_license_restapi 进程..."
/usr/local/platos/app/sf_license/bin/sf_license_env_lua /usr/local/platos/app/sf_license/bin/sf_license_rest.lua &
RESTAPI_PID=$!
echo "RESTAPI 进程 PID: $RESTAPI_PID"

echo "启动反向代理，侦听 10000 端口，转发至 10003 端口..."
socat TCP-LISTEN:10000,fork,reuseaddr TCP:127.0.0.1:10003 &
PROXY_PID=$!
echo "反向代理进程 PID: $PROXY_PID"

# 等待任意进程退出
wait -n $MAIN_PID $RESTAPI_PID $PROXY_PID
EXIT_CODE=$?

echo "有进程退出，退出码: $EXIT_CODE"
exit $EXIT_CODE
