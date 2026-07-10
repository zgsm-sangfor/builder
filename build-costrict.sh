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
#   --update    检测 dependency 包变更并自动递增版本号（Step 1），默认不执行
#   --build <target>       指定要构建的依赖包列表（Step 2），传给 build-depends.sh 的 --packages 选项
#                          target 为逗号分隔的包名列表（如 "casdoor,chat-rag"），或下列值之一：
#                            all  - 构建所有 enabled 依赖
#                            auto - 自动检测需要构建的依赖（默认行为，通过 check-build.sh 检测）
#   --push <ENV>           作为 --build 的子动作，指定镜像推送的环境，会传给 build-depends.sh
#                          构建镜像始终执行，此选项只控制是否推送。
#                          ENV 必须指定；支持逗号分隔的环境列表或关键字：
#                          关键字：docker（推送到 docker hub）
#                            hub（推送到 docker hub + DH_ENV_NAMES 中的所有环境）
#                            nfs（推送到 NFS_ENV_NAMES 中的所有环境）
#                            all（推送到 docker hub + DH_ENV_NAMES + NFS_ENV_NAMES 中的所有环境）
#                          环境名：具体环境名称（需在 DH_ENV_NAMES 或 NFS_ENV_NAMES 中存在）
#                          示例：--push docker, --push hub, --push nfs, --push test,prod,
#                                --push all, --push test,hub
#   --pack <target>        指定要打包的组件包列表（Step 6），传给 build-components.sh 的 --packages 选项
#                          target 为逗号分隔的包名列表（如 "firmware,costrict-system"），或下列值之一：
#                            all  - 构建所有组件包
#                            auto - 自动检测需要构建的组件包（默认行为，通过 check-build.sh 检测）
#   --upload <env>         作为 --pack 的子动作，指定包上传的环境，会传给 build-components.sh

source ./.env

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "构建 CoStrict 系统包"
    echo ""
    echo "选项:"
    echo "  --update              检测 dependency 包变更并自动递增版本号（Step 1）"
    echo "                        默认不执行 Step 1，仅当指定此选项时才执行"
    echo "  --build <target>      指定要构建的依赖包（Step 2）"
    echo "                        target 为逗号分隔的包名列表（如 \"casdoor,chat-rag\"），或："
    echo "                          all  - 构建所有 enabled 依赖"
    echo "                          auto - 自动检测需要构建的依赖"
    echo "                        无此选项，则无需构建依赖包"
    echo "    --push <ENV>        作为 --build 的子动作，推送镜像到指定环境 (会传递给 build-depends.sh)"
    echo "                        构建镜像始终执行，此选项只控制是否推送"
    echo "                        ENV 必须指定；支持逗号分隔的环境列表或关键字："
    echo "                        docker    - 推送到 docker hub"
    echo "                        hub       - 推送到 docker hub + DH_ENV_NAMES(${DH_ENV_NAMES[*]})"
    echo "                        nfs       - 推送到 NFS_ENV_NAMES(${NFS_ENV_NAMES[*]})"
    echo "                        all       - 推送到所有环境（docker + DH_ENV_NAMES(${DH_ENV_NAMES[*]})"
    echo "                                                          + NFS_ENV_NAMES(${NFS_ENV_NAMES[*]})）"
    echo "                        <custom>  - 具体环境名称，可选范围：DH_ENV_NAMES(${DH_ENV_NAMES[*]})"
    echo "                                                          或 NFS_ENV_NAMES(${NFS_ENV_NAMES[*]})"
    echo "                        Examples: \"--push docker\", \"--push hub\", \"--push nfs\","
    echo "                                  \"--push test,prod\", \"--push all\", \"--push test,hub\""
    echo "    --local             作为 --build 的子选项，将 --local 传递给"
    echo "                        check-update.sh（Step 1）和 build-depends.sh（Step 2），"
    echo "                        使它们仅使用本地已存在的项目信息，不尝试从远程拉取"
    echo "  --pack <target>       指定要打包的组件包（Step 6）"
    echo "                        target 为逗号分隔的包名列表（如 \"firmware,costrict-system\"），或："
    echo "                          all  - 构建所有组件包"
    echo "                          auto - 自动检测需要构建的组件包"
    echo "                        无此选项，则无需构建组件包"
    echo "    --upload <env>      作为 --pack 的子动作，指定包上传的环境 (会传递给 build-components.sh)"
    echo "  --help, -h            显示此帮助信息"
    echo ""
    echo "执行步骤:"
    echo "  1. (仅 --update) 检测 dependency 包变更并自动递增版本号"
    echo "  2. 检查尚未构建的 dependency 包（构建物包括 Docker 镜像、前端页面包、可执行程序等），若有则调用 build-depends.sh 构建（可选推送镜像）"
    echo "     (若指定 --build <target>，则按指定目标构建：all=全部, auto=自动检测, 或指定包名列表)"
    echo "  3. 调用 gen-backend-spec.sh 生成 backend/system-spec.json"
    echo "  4. 检测 component 包变更并自动递增版本号"
    echo "  5. 调用 gen-manifest.sh 生成系统清单，并重新检查 costrict-system 版本"
    echo "  6. 检查尚未打包的 component 包，若有则调用 build-components.sh 构建、打包并索引"
    echo "     (若指定 --pack <target>，则按指定目标打包：all=全部, auto=自动检测, 或指定包名列表)"
    echo ""
    echo "示例:"
    echo "  $0                                    # 构建镜像（不推送），然后构建包"
    echo "  $0 --update                           # 先检测 dependency 变更并递增版本，再构建镜像和包"
    echo "  $0 --build all                        # 跳过检查，构建所有依赖"
    echo "  $0 --build casdoor,chat-rag           # 构建指定的依赖包"
    echo "  $0 --build auto --push docker         # 构建镜像并推送到 docker hub"
    echo "  $0 --build auto --push hub            # 构建镜像并推送到 docker hub + DH 环境"
    echo "  $0 --build auto --push nfs            # 构建镜像并推送到 NFS 环境"
    echo "  $0 --build auto --push test,prod      # 构建镜像并推送到 test 和 prod 环境"
    echo "  $0 --build auto --push all            # 构建镜像并推送到所有环境"
    echo "  $0 --pack all                         # 跳过检查，重新打包所有组件"
    echo "  $0 --pack firmware,costrict-system    # 打包指定的组件"
    echo "  $0 --pack auto --upload prod          # 构建包并上传到 prod 环境"
    echo ""
}

# 解析参数
UPLOAD_ENV=""
PUSH_ENV=""
NEED_UPDATE=false
NEED_LOCAL=false
BUILD_TARGET=""
PACK_TARGET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH_ENV="$2"
            shift 2
            ;;
        --upload)
            UPLOAD_ENV="$2"
            shift 2
            ;;
        --update)
            NEED_UPDATE=true
            shift
            ;;
        --build)
            BUILD_TARGET="$2"
            shift 2
            ;;
        --pack)
            PACK_TARGET="$2"
            shift 2
            ;;
        --local)
            NEED_LOCAL=true
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

PUSH_OPT=""
if [ -n "$PUSH_ENV" ]; then
    PUSH_OPT="--push $PUSH_ENV"
fi

LOCAL_OPT=""
if [ "$NEED_LOCAL" = true ]; then
    LOCAL_OPT="--local"
fi

UPLOAD_OPT=""
if [ -n "$UPLOAD_ENV" ]; then
    PUSH_OPT="--upload $UPLOAD_ENV"
fi

# Step 1: 仅当 --update 为 true 时，调用check-update.sh自动递增dependency包的版本号
if [ "$NEED_UPDATE" = true ]; then
    echo "----------------------------------------------------------------"
    echo "Step 1: Detecting dependency changes and auto-incrementing versions..."
    echo "----------------------------------------------------------------"
    ./check-update.sh --update --build-type dependency $LOCAL_OPT
else
    echo "----------------------------------------------------------------"
    echo "--update not set, skipping Step 1 (dependency version auto-increment)..."
    echo "----------------------------------------------------------------"
fi

# Step 2: 构建依赖包
# 若 --build 未指定（BUILD_TARGET 为空），跳过依赖包构建
# 若 --build all，跳过 check-build.sh，直接构建所有 enabled 依赖
# 若 --build 指定了包名列表，跳过 check-build.sh，直接构建指定包
# 若 --build auto，先调用 check-build.sh 获取尚未构建的依赖包列表，再按需构建
if [ -z "$BUILD_TARGET" ]; then
    echo "----------------------------------------------------------------"
    echo "--build not set, skipping Step 2 (dependency package build)..."
    echo "----------------------------------------------------------------"
elif [ "$BUILD_TARGET" = "all" ]; then
    echo "----------------------------------------------------------------"
    echo "Step 2: Building all enabled dependency packages (Docker images, frontend pages, executables, etc.)..."
    echo "----------------------------------------------------------------"
    ./build-depends.sh --build --update $PUSH_OPT $LOCAL_OPT
elif [ "$BUILD_TARGET" = "auto" ]; then
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
        ./build-depends.sh --build --update $PUSH_OPT $LOCAL_OPT --packages $need_build_packages
    else
        echo "No 'dependency' packages need building, skipping..."
    fi
else
    echo "----------------------------------------------------------------"
    echo "Step 2: Building specified dependency packages: $BUILD_TARGET ..."
    echo "----------------------------------------------------------------"
    ./build-depends.sh --build --update $PUSH_OPT $LOCAL_OPT --packages $BUILD_TARGET
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

# Step 6: 打包组件包
# 若 --pack 未指定（PACK_TARGET 为空），跳过组件包打包
# 若 --pack all，跳过 check-build.sh，直接构建所有组件包
# 若 --pack 指定了包名列表，跳过 check-build.sh，直接打包指定组件
# 若 --pack auto，先调用 check-build.sh 获取尚未打包的组件包列表，再按需打包
if [ -z "$PACK_TARGET" ]; then
    echo "----------------------------------------------------------------"
    echo "--pack not set, skipping Step 6 (component package build)..."
    echo "----------------------------------------------------------------"
elif [ "$PACK_TARGET" = "all" ]; then
    echo "----------------------------------------------------------------"
    echo "Step 6: Building all component packages (clean/build/pack/index)..."
    echo "----------------------------------------------------------------"
    ./build-components.sh --clean --build --pack --index $UPLOAD_OPT
elif [ "$PACK_TARGET" = "auto" ]; then
    echo "----------------------------------------------------------------"
    echo "Step 6: Checking and building component packages (clean/build/pack/index)..."
    echo "----------------------------------------------------------------"
    # check-build.sh 以未打包包的数量作为退出码，当存在未打包包时返回非0，
    # 此处使用 '|| true' 防止 set -e 中断脚本执行
    need_pack_packages=$(./check-build.sh --build-type component || true)
    echo "Need build 'component' packages: $need_pack_packages"

    if [ -n "$need_pack_packages" ]; then
        echo "----------------------------------------------------------------"
        echo "Building packages..."
        echo "----------------------------------------------------------------"
        ./build-components.sh --packages "$need_pack_packages" --clean --build --pack --index $UPLOAD_OPT
    else
        echo "No 'component' packages need building, skipping..."
    fi
else
    echo "----------------------------------------------------------------"
    echo "Step 6: Building specified component packages: $PACK_TARGET ..."
    echo "----------------------------------------------------------------"
    ./build-components.sh --packages "$PACK_TARGET" --clean --build --pack --index $UPLOAD_OPT
fi

echo "Build costrict completed!"
