#!/bin/bash
# set -e

# 信号处理函数
shutdown() {
    echo "正在停止所有服务..."
    kill -TERM $MAIN_PID $RESTAPI_PID  2>/dev/null || true
    wait $MAIN_PID $RESTAPI_PID 2>/dev/null || true
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

# 跟踪各进程退出状态
MAIN_EXITED=false
RESTAPI_EXITED=false
LAST_EXIT_CODE=0

# 循环等待所有进程退出
while ! $MAIN_EXITED || ! $RESTAPI_EXITED ; do
    # 构建等待列表（只等待尚未退出的进程）
    WAIT_PIDS=""
    if ! $MAIN_EXITED; then
        WAIT_PIDS="$WAIT_PIDS $MAIN_PID"
    fi
    if ! $RESTAPI_EXITED; then
        WAIT_PIDS="$WAIT_PIDS $RESTAPI_PID"
    fi

    # 等待任意一个进程退出
    wait -n $WAIT_PIDS 2>/dev/null

    # 检查并标记已退出的进程，每个退出进程用 wait $PID 获取真实退出码
    if ! $MAIN_EXITED && ! kill -0 $MAIN_PID 2>/dev/null; then
        wait $MAIN_PID 2>/dev/null
        MAIN_EXIT_CODE=$?
        echo "主进程 (PID: $MAIN_PID) 已退出，退出码: $MAIN_EXIT_CODE"
        MAIN_EXITED=true
        LAST_EXIT_CODE=$MAIN_EXIT_CODE
    fi
    if ! $RESTAPI_EXITED && ! kill -0 $RESTAPI_PID 2>/dev/null; then
        wait $RESTAPI_PID 2>/dev/null
        RESTAPI_EXIT_CODE=$?
        echo "RESTAPI 进程 (PID: $RESTAPI_PID) 已退出，退出码: $RESTAPI_EXIT_CODE"
        RESTAPI_EXITED=true
        LAST_EXIT_CODE=$RESTAPI_EXIT_CODE
    fi
done

echo "所有进程已退出，startup.sh 结束"
exit $LAST_EXIT_CODE
