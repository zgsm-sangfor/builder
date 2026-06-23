#!/bin/bash
# set -e

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

# 跟踪各进程退出状态
MAIN_EXITED=false
RESTAPI_EXITED=false
PROXY_EXITED=false

# 循环等待所有进程退出
while ! $MAIN_EXITED || ! $RESTAPI_EXITED || ! $PROXY_EXITED; do
    # 构建等待列表（只等待尚未退出的进程）
    WAIT_PIDS=""
    if ! $MAIN_EXITED; then
        WAIT_PIDS="$WAIT_PIDS $MAIN_PID"
    fi
    if ! $RESTAPI_EXITED; then
        WAIT_PIDS="$WAIT_PIDS $RESTAPI_PID"
    fi
    if ! $PROXY_EXITED; then
        WAIT_PIDS="$WAIT_PIDS $PROXY_PID"
    fi

    # 等待任意一个进程退出
    wait -n $WAIT_PIDS 2>/dev/null
    EXIT_CODE=$?

    # 检查并标记已退出的进程，每个退出进程打印说明
    if ! $MAIN_EXITED && ! kill -0 $MAIN_PID 2>/dev/null; then
        echo "主进程 (PID: $MAIN_PID) 已退出，退出码: $EXIT_CODE"
        MAIN_EXITED=true
    fi
    if ! $RESTAPI_EXITED && ! kill -0 $RESTAPI_PID 2>/dev/null; then
        echo "RESTAPI 进程 (PID: $RESTAPI_PID) 已退出，退出码: $EXIT_CODE"
        RESTAPI_EXITED=true
    fi
    if ! $PROXY_EXITED && ! kill -0 $PROXY_PID 2>/dev/null; then
        echo "反向代理进程 (PID: $PROXY_PID) 已退出，退出码: $EXIT_CODE"
        PROXY_EXITED=true
    fi
done

echo "所有进程已退出，entrypoint.sh 结束"
exit 0
