#!/bin/bash

set -e

#
# Step 1: 调用check-update.sh检测dependency包的变更并自动递增版本号；
# Step 2: 调用check-build.sh检查哪些dependency包当前版本尚未构建；
#         dependency包的构建物包括：Docker镜像、前端页面包、可执行程序等；
#         若有，调用build-depends.sh进行构建（可选推送镜像），否则跳过；
#         注意：build-depends.sh的--update操作可能修改component包的配置文件（如image.env），
#         因此component包的版本递增必须在此步骤之后执行；
# Step 3: 调用gen-backend-spec.sh生成backend/system-spec.json；
# Step 4: 调用check-update.sh检测component包的变更并自动递增版本号；
# Step 5: 调用gen-manifest.sh生成costrict-system/manifest.json；
#         gen-manifest.sh可能修改了costrict-system的内容，因此再次检查并递增其版本；
# Step 6: 调用check-build.sh检查哪些component包当前版本尚未打包；
#         若有，调用build-components.sh执行clean/build/pack/index流程（若指定--upload则上传至云环境），否则跳过。
#
# 说明：check-update.sh 只负责自动递增包的版本号，不再用于获取待构建的包列表；
#       待构建的包列表统一由 check-build.sh 获取。
#

# build-costrict.sh支持以下可选参数：
#   --push [env]           用于指定镜像推送的环境，该参数会传给build-depends.sh（构建镜像始终执行）
#   --upload <env>         用于指定包上传的环境，该参数会传给build-components.sh
#   --skip-dependency      跳过依赖处理（Step 1 和 Step 2），不处理 dependency 包
#   --update-dependency    检测 dependency 包变更并自动递增版本号（Step 1），默认不执行
#   --rebuild              重新构建所有 enabled 依赖（Step 2），跳过 check-build.sh 过滤，
#                          直接调用 build-depends.sh 不带 --packages 选项
#   --repack               重新打包所有组件（Step 6），跳过 check-build.sh 过滤，
#                          直接调用 build-components.sh 不带 --packages 选项

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 系统包"
    echo ""
    echo "选项:"
    echo "  --skip-dependency     跳过依赖处理（Step 1 和 Step 2），不处理 dependency 包"
    echo "  --update-dependency   检测 dependency 包变更并自动递增版本号（Step 1）"
    echo "                        默认不执行 Step 1，仅当指定此选项时才执行"
    echo "  --rebuild             重新构建所有依赖（Step 2）"
    echo "                        跳过 check-build.sh 过滤，直接调用 build-depends.sh 不带 --packages"
    echo "  --repack           重新打包所有组件（Step 6）"
    echo "                        跳过 check-build.sh 过滤，直接调用 build-components.sh 不带 --packages"
    echo "  --push [env]          推送镜像到指定环境 (会传递给 build-depends.sh)"
    echo "                        构建镜像始终执行，此选项只控制是否推送"
    echo "                        如果 env 为空或 'def'，推送到 docker hub"
    echo "                        否则推送到指定环境 (如 'test,prod' 或 'all')"
    echo "  --upload <env>        指定包上传的环境 (会传递给 build-components.sh)"
    echo "  --help, -h            显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. (仅 --update-dependency) 检测 dependency 包变更并自动递增版本号"
    echo "  2. 检查尚未构建的 dependency 包（构建物包括 Docker 镜像、前端页面包、可执行程序等），若有则调用 build-depends.sh 构建（可选推送镜像）"
    echo "     (若指定 --rebuild，则跳过检查，直接构建所有依赖)"
    echo "  3. 调用 gen-backend-spec.sh 生成 backend/system-spec.json"
    echo "  4. 检测 component 包变更并自动递增版本号"
    echo "  5. 调用 gen-manifest.sh 生成系统清单，并重新检查 costrict-system 版本"
    echo "  6. 检查尚未打包的 component 包，若有则调用 build-components.sh 构建、打包并索引"
    echo "     (若指定 --repack，则跳过检查，直接重新打包所有组件)"
    echo ""
    echo "示例:"
    echo "  $0                            # 构建镜像（不推送），然后构建包"
    echo "  $0 --update-dependency        # 先检测 dependency 变更并递增版本，再构建镜像和包"
    echo "  $0 --rebuild                  # 跳过检查，重新构建所有依赖"
    echo "  $0 --repack                # 跳过检查，重新打包所有组件"
    echo "  $0 --push                     # 构建镜像并推送到 docker hub"
    echo "  $0 --push test,prod           # 构建镜像并推送到 test 和 prod 环境"
    echo "  $0 --upload prod              # 构建包并上传到 prod 环境"
    echo ""
}

# 解析参数
UPLOAD_ENV=""
PUSH_ENV=""
NEED_PUSH=false
SKIP_DEPENDENCY=false
UPDATE_DEPENDENCY=false
REBUILD_DEPENDENCY=false
REPACK_COMPONENTS=false

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
        --skip-dependency)
            SKIP_DEPENDENCY=true
            shift
            ;;
        --update-dependency)
            UPDATE_DEPENDENCY=true
            shift
            ;;
        --rebuild)
            REBUILD_DEPENDENCY=true
            shift
            ;;
        --repack)
            REPACK_COMPONENTS=true
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
if [ "$SKIP_DEPENDENCY" = true ]; then
    echo "----------------------------------------------------------------"
    echo "--skip-dependency is set, skipping Step 1 and Step 2 (dependency processing)..."
    echo "----------------------------------------------------------------"
else
    # Step 1: 仅当 --update-dependency 为 true 时，调用check-update.sh自动递增dependency包的版本号
    if [ "$UPDATE_DEPENDENCY" = true ]; then
        echo "----------------------------------------------------------------"
        echo "Step 1: Detecting dependency changes and auto-incrementing versions..."
        echo "----------------------------------------------------------------"
        ./check-update.sh --update --build-type dependency
    else
        echo "----------------------------------------------------------------"
        echo "--update-dependency not set, skipping Step 1 (dependency version auto-increment)..."
        echo "----------------------------------------------------------------"
    fi

    # Step 2: 构建依赖包
    # 若 --rebuild 为 true，跳过 check-build.sh，直接构建所有 enabled 依赖
    # 否则先调用 check-build.sh 获取尚未构建的依赖包列表，再按需构建
    if [ "$REBUILD_DEPENDENCY" = true ]; then
        echo "----------------------------------------------------------------"
        echo "Step 2: Rebuilding all enabled dependency packages (Docker images, frontend pages, executables, etc.)..."
        echo "----------------------------------------------------------------"
        if [ "$NEED_PUSH" = true ]; then
            ./build-depends.sh --build --update --push $PUSH_ENV
        else
            ./build-depends.sh --build --update
        fi
    else
        echo "----------------------------------------------------------------"
        echo "Step 2: Checking and building dependency packages (Docker images, frontend pages, executables, etc.)..."
        echo "----------------------------------------------------------------"
        # check-build.sh 以未构建包的数量作为退出码，当存在未构建包时返回非0，
        # 此处使用 '|| true' 防止 set -e 中断脚本执行
        need_build_packages=$(./check-build.sh --build-type dependency || true)
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
fi

# Step 3: 调用gen-backend-spec.sh，更新backend/system-spec.json
echo "----------------------------------------------------------------"
echo "Step 3: Generating backend system spec (backend/system-spec.json)..."
echo "----------------------------------------------------------------"
./gen-backend-spec.sh

# Step 4: 调用check-update.sh，自动递增component包的版本号
# 注意：需要在build-depends.sh之后执行，因为其--update操作可能修改component包的配置文件
echo "----------------------------------------------------------------"
echo "Step 4: Detecting component changes and auto-incrementing versions..."
echo "----------------------------------------------------------------"
./check-update.sh --update --build-type component

# Step 5: 调用gen-manifest.sh，更新costrict-system/manifest.json，更新costrict-system模块版本
echo "----------------------------------------------------------------"
echo "Step 5: Generating system manifest and re-checking costrict-system version..."
echo "----------------------------------------------------------------"
./gen-manifest.sh
# gen-manifest.sh 可能修改了costrict-system的内容，重新检查并递增其版本
./check-update.sh --update --build-type component -p costrict-system

# Step 6: 调用check-build.sh，获取尚未打包的组件包列表，然后构建
echo "----------------------------------------------------------------"
echo "Step 6: Checking and building component packages (clean/build/pack/index)..."
echo "----------------------------------------------------------------"
# check-build.sh 以未打包包的数量作为退出码，当存在未打包包时返回非0，
# 此处使用 '|| true' 防止 set -e 中断脚本执行
# 若 --repack 为 true，跳过 check-build.sh，直接重新打包所有组件
# 否则先调用 check-build.sh 获取尚未打包的组件包列表，再按需打包
if [ "$REPACK_COMPONENTS" = true ]; then
    echo "Step 6: Repackaging all component packages (clean/build/pack/index)..."
    echo "----------------------------------------------------------------"
    if [ -n "$UPLOAD_ENV" ]; then
        ./build-components.sh --clean --build --pack --index --upload "$UPLOAD_ENV"
    else
        ./build-components.sh --clean --build --pack --index
    fi
else
    # check-build.sh 以未打包包的数量作为退出码，当存在未打包包时返回非0，
    # 此处使用 '|| true' 防止 set -e 中断脚本执行
    need_pack_packages=$(./check-build.sh --build-type component || true)
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
fi

echo "Build costrict completed!"
