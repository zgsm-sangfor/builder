#!/bin/bash

set -e

#
# Step 1: 读取costrict-manifest.json，获取costrict系统的模块列表(模块名为components数组成员对象的name字段)；
# Step 2: 调用build-images.sh，构建镜像（可选推送）；
# Step 3: 调用check-update.sh，以Step 1得到的模块列表作为参数(先转为逗号分隔的列表再传给check-update.sh),获得被更新的模块列表，自动递增被更新模块的版本；
# Step 4: 调用update-manifest.sh，更新costrict-system/manifest.json
# Step 5: 调用build-packages.sh，重新构建Step 3得到的模块列表，以及costrict-system,并上传到云环境。
#

# build-costrict.sh支持以下可选参数：
#   --upload <env>  用于指定包上传的环境，该参数会传给build-packages.sh
#   --push [env]    用于指定镜像推送的环境，该参数会传给build-images.sh（构建镜像始终执行）

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 系统包"
    echo ""
    echo "选项:"
    echo "  --push [env]    推送镜像到指定环境 (会传递给 build-images.sh)"
    echo "                  构建镜像始终执行，此选项只控制是否推送"
    echo "                  如果 env 为空或 'def'，推送到 docker hub"
    echo "                  否则推送到指定环境 (如 'test,prod' 或 'all')"
    echo "  --upload <env>  指定包上传的环境 (会传递给 build-packages.sh)"
    echo "  --help, -h      显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. 读取 costrict-manifest.json 获取组件列表"
    echo "  2. 调用 build-images.sh 构建镜像 (可选推送)"
    echo "  3. 调用 check-update.sh 检查更新的模块"
    echo "  4. 调用 update-manifest.sh 更新 manifest"
    echo "  5. 调用 build-packages.sh 构建包并可选上传"
    echo ""
    echo "示例:"
    echo "  $0                    # 构建镜像（不推送），然后构建包"
    echo "  $0 --push             # 构建镜像并推送到 docker hub"
    echo "  $0 --push test,prod   # 构建镜像并推送到 test 和 prod 环境"
    echo "  $0 --upload prod      # 构建包并上传到 prod 环境"
    echo ""
}

# 解析参数
UPLOAD_ENV=""
PUSH_ENV=""
NEED_PUSH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            NEED_PUSH=true
            # 检查下一个参数是否是选项（以-开头）或为空
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                PUSH_ENV="$2"
                shift 2
            else
                PUSH_ENV=""
                shift
            fi
            ;;
        --upload)
            UPLOAD_ENV="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Step 1: 读取costrict-manifest.json，获取组件列表
echo "----------------------------------------------------------------"
echo "Step 1: Reading costrict-manifest.json..."
echo "----------------------------------------------------------------"
component_list=$(jq -r '.components[].name' costrict-manifest.json | tr '\n' ',' | sed 's/,$//')
echo "Component list: $component_list"

# Step 2: 调用build-images.sh，构建镜像
echo "----------------------------------------------------------------"
echo "Step 2: Building images..."
echo "----------------------------------------------------------------"
if [ "$NEED_PUSH" = true ]; then
    ./build-images.sh --build --push $PUSH_ENV
else
    ./build-images.sh --build
fi

# Step 3: 调用check-update.sh，获取被更新的模块列表
echo "----------------------------------------------------------------"
echo "Step 3: Checking updates..."
echo "----------------------------------------------------------------"
updated_packages=$(./check-update.sh --update --packages "$component_list")
echo "Updated packages: $updated_packages"

# 如果没有更新的包，使用完整的组件列表
if [ -z "$updated_packages" ]; then
    echo "No packages updated, using full component list"
    build_packages="$component_list"
else
    build_packages="$updated_packages"
fi

# Step 4: 调用update-manifest.sh
echo "----------------------------------------------------------------"
echo "Step 4: Updating manifest..."
echo "----------------------------------------------------------------"
./update-manifest.sh

# Step 5: 调用build-packages.sh
echo "----------------------------------------------------------------"
echo "Step 5: Building packages..."
echo "----------------------------------------------------------------"
if [ -n "$UPLOAD_ENV" ]; then
    ./build-packages.sh --packages "$build_packages,costrict-system" --def --upload "$UPLOAD_ENV"
else
    ./build-packages.sh --packages "$build_packages,costrict-system" --def
fi

echo "Build costrict completed!"
