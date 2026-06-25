#!/bin/bash

set -e

#
# Step 1: 调用check-update.sh，自动递增dependency包的版本号；
# Step 2: 调用check-packaged.sh检查哪些依赖包当前版本还没构建，需要构建；
#         如果有，调用build-depends.sh构建镜像（可选推送），否则跳过；
#         注意：build-depends.sh的--update操作可能修改component包的配置文件（如image.env），
#         因此component包的版本递增必须在此步骤之后执行；
# Step 3: 调用check-update.sh，自动递增component包的版本号；
# Step 4: 调用gen-manifest.sh更新costrict-system/manifest.json，
#         调用gen-backend-spec.sh更新backend/system-spec.json；
#         gen-manifest.sh可能修改了costrict-system的内容，因此再次检查并递增其版本；
# Step 5: 调用check-packaged.sh检查哪些组件包当前版本还没打包，需要打包；
#         如果有，调用build-components.sh构建包并上传到云环境（如果指定了--upload参数），否则跳过。
#
# 说明：check-update.sh 只负责自动递增包的版本号，不再用于获取待构建的包列表；
#       待构建的包列表统一由 check-packaged.sh 获取。
#

# build-costrict.sh支持以下可选参数：
#   --upload <env>    用于指定包上传的环境，该参数会传给build-components.sh
#   --push [env]      用于指定镜像推送的环境，该参数会传给build-depends.sh（构建镜像始终执行）
#   --skip-depend     跳过依赖处理（Step 1 和 Step 2），不处理 dependency 包

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 系统包"
    echo ""
    echo "选项:"
    echo "  --push [env]      推送镜像到指定环境 (会传递给 build-depends.sh)"
    echo "                    构建镜像始终执行，此选项只控制是否推送"
    echo "                    如果 env 为空或 'def'，推送到 docker hub"
    echo "                    否则推送到指定环境 (如 'test,prod' 或 'all')"
    echo "  --upload <env>    指定包上传的环境 (会传递给 build-components.sh)"
    echo "  --skip-depend     跳过依赖处理（Step 1 和 Step 2），不处理 dependency 包"
    echo "  --help, -h        显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. 调用 check-update.sh 自动递增 dependency 包的版本号"
    echo "  2. 调用 check-packaged.sh 检查尚未构建的 dependency 包，若有则调用 build-depends.sh 构建"
    echo "  3. 调用 check-update.sh 自动递增 component 包的版本号"
    echo "  4. 调用 gen-manifest.sh 更新 manifest，调用 gen-backend-spec.sh 更新 backend spec，并重新检查 costrict-system 版本"
    echo "  5. 调用 check-packaged.sh 检查尚未打包的 component 包，若有则调用 build-components.sh 构建"
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
SKIP_DEPEND=false

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
        --skip-depend)
            SKIP_DEPEND=true
            shift
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
if [ "$SKIP_DEPEND" = true ]; then
    echo "----------------------------------------------------------------"
    echo "--skip-depend is set, skipping Step 1 and Step 2 (dependency processing)..."
    echo "----------------------------------------------------------------"
else
    # Step 1: 调用check-update.sh，自动递增dependency包的版本号
    echo "----------------------------------------------------------------"
    echo "Step 1: Updating dependency versions..."
    echo "----------------------------------------------------------------"
    ./check-update.sh --update --build-type dependency

    # Step 2: 调用check-packaged.sh，获取尚未构建的依赖包列表，然后构建
    echo "----------------------------------------------------------------"
    echo "Step 2: Checking packaged dependencies..."
    echo "----------------------------------------------------------------"
    # check-packaged.sh 以未构建包的数量作为退出码，当存在未构建包时返回非0，
    # 此处使用 '|| true' 防止 set -e 中断脚本执行
    need_build_packages=$(./check-packaged.sh --build-type dependency || true)
    echo "Need build 'dependency' packages: $need_build_packages"

    if [ -n "$need_build_packages" ]; then
        echo "----------------------------------------------------------------"
        echo "Building depends..."
        echo "----------------------------------------------------------------"
        if [ "$NEED_PUSH" = true ]; then
            ./build-depends.sh --build --update --push $PUSH_ENV --packages $need_build_packages
        else
            ./build-depends.sh --build --update --packages $need_build_packages
        fi
    else
        echo "No 'dependency' packages need building, skipping..."
    fi
fi

# Step 3: 调用check-update.sh，自动递增component包的版本号
# 注意：需要在build-depends.sh之后执行，因为其--update操作可能修改component包的配置文件
echo "----------------------------------------------------------------"
echo "Step 3: Updating component versions..."
echo "----------------------------------------------------------------"
./gen-backend-spec.sh
./check-update.sh --update --build-type component

# Step 4: 调用gen-manifest.sh，更新costrict-system/manifest.json
echo "----------------------------------------------------------------"
echo "Step 4: Updating system manifest & backend specific..."
echo "----------------------------------------------------------------"
./gen-manifest.sh

# gen-manifest.sh 可能修改了costrict-system的内容，重新检查并递增其版本
echo "----------------------------------------------------------------"
echo "Checking costrict-system for updates..."
echo "----------------------------------------------------------------"
./check-update.sh --update --build-type component -p costrict-system

# Step 5: 调用check-packaged.sh，获取尚未打包的组件包列表，然后构建
echo "----------------------------------------------------------------"
echo "Step 5: Checking packaged components..."
echo "----------------------------------------------------------------"
# check-packaged.sh 以未打包包的数量作为退出码，当存在未打包包时返回非0，
# 此处使用 '|| true' 防止 set -e 中断脚本执行
need_pack_packages=$(./check-packaged.sh --build-type component || true)
echo "Need build 'component' packages: $need_pack_packages"

if [ -n "$need_pack_packages" ]; then
    echo "----------------------------------------------------------------"
    echo "Building packages..."
    echo "----------------------------------------------------------------"
    if [ -n "$UPLOAD_ENV" ]; then
        ./build-components.sh --packages "$need_pack_packages" --clean --build --pack --index --upload "$UPLOAD_ENV"
    else
        ./build-components.sh --packages "$need_pack_packages" --clean --build --pack --index
    fi
else
    echo "No 'component' packages need building, skipping..."
fi

echo "Build costrict completed!"
