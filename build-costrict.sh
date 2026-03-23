#!/bin/bash

set -e

#
# Step 1: 调用check-update.sh，使用--build-type dependency检查需要构建镜像的包，自动递增被更新模块的版本；
# Step 2: 如果Step 1有更新，调用build-depends.sh构建镜像包（可选推送），否则跳过；
# Step 3: 调用update-manifest.sh，更新costrict-system/manifest.json；
# Step 4: 调用check-update.sh，使用--build-type component检查需要构建组件的包，自动递增被更新模块的版本；
# Step 5: 如果Step 4有更新，调用build-components.sh构建包并上传到云环境（如果指定了--upload参数），否则跳过。
#

# build-costrict.sh支持以下可选参数：
#   --upload <env>  用于指定包上传的环境，该参数会传给build-components.sh
#   --push [env]    用于指定镜像推送的环境，该参数会传给build-depends.sh（构建镜像始终执行）

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 系统包"
    echo ""
    echo "选项:"
    echo "  --push [env]    推送镜像到指定环境 (会传递给 build-depends.sh)"
    echo "                  构建镜像始终执行，此选项只控制是否推送"
    echo "                  如果 env 为空或 'def'，推送到 docker hub"
    echo "                  否则推送到指定环境 (如 'test,prod' 或 'all')"
    echo "  --upload <env>  指定包上传的环境 (会传递给 build-components.sh)"
    echo "  --help, -h      显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. 调用 check-update.sh 检查 dependency 类型更新的包"
    echo "  2. 若Step1有更新，调用 build-depends.sh 构建镜像 (可选推送)，否则跳过"
    echo "  3. 调用 update-manifest.sh 更新 manifest"
    echo "  4. 调用 check-update.sh 检查 component 类型更新的包"
    echo "  5. 若Step4有更新，调用 build-components.sh 构建包并可选上传，否则跳过"
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

# Step 1: 调用check-update.sh，获取已经更新需要重新构建镜像的模块列表
echo "----------------------------------------------------------------"
echo "Step 1: Checking updates..."
echo "----------------------------------------------------------------"
updated_packages=$(./check-update.sh --update --build-type dependency)
echo "Updated 'dependency' packages: $updated_packages"

# Step 2: 调用build-depends.sh，构建镜像（如果Step 1有更新）
if [ -n "$updated_packages" ]; then
    echo "----------------------------------------------------------------"
    echo "Step 2: Building depends..."
    echo "----------------------------------------------------------------"
    if [ "$NEED_PUSH" = true ]; then
        ./build-depends.sh --build --update --push $PUSH_ENV --packages $updated_packages
    else
        ./build-depends.sh --build --update --packages $updated_packages
    fi
else
    echo "Step 2: No 'dependency' packages updated, skipping..."
fi

# Step 3: 调用check-update.sh，获取被更新的模块列表
echo "----------------------------------------------------------------"
echo "Step 3: Checking updates..."
echo "----------------------------------------------------------------"
updated_packages=$(./check-update.sh --update --build-type component)
echo "Updated 'component' packages: $updated_packages"

# Step 4: 调用update-manifest.sh
echo "----------------------------------------------------------------"
echo "Step 4: Updating manifest..."
echo "----------------------------------------------------------------"
./update-manifest.sh

# 检查costrict-system是否发生变更
if [[ ",$updated_packages," != *",costrict-system,"* ]]; then
    echo "----------------------------------------------------------------"
    echo "Checking costrict-system for updates..."
    echo "----------------------------------------------------------------"
    costrict_system_update=$(./check-update.sh -u -p costrict-system --build-type component)
    if [ -n "$costrict_system_update" ]; then
        echo "costrict-system has been updated, adding to updated_packages"
        if [ -n "$updated_packages" ]; then
            updated_packages="$updated_packages,costrict-system"
        else
            updated_packages="costrict-system"
        fi
        echo "Updated 'component' packages (including costrict-system): $updated_packages"
    else
        echo "costrict-system has not changed"
    fi
fi

# Step 5: 调用build-components.sh构建包（如果Step 4有更新）
if [ -n "$updated_packages" ]; then
    echo "----------------------------------------------------------------"
    echo "Step 5: Building packages..."
    echo "----------------------------------------------------------------"
    if [ -n "$UPLOAD_ENV" ]; then
        ./build-components.sh --packages "$updated_packages" --def --upload "$UPLOAD_ENV"
    else
        ./build-components.sh --packages "$updated_packages" --def
    fi
else
    echo "Step 5: No 'component' packages updated, skipping..."
fi

echo "Build costrict completed!"
