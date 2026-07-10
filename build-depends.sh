#!/bin/bash

#
# 功能：
#   build-depends.sh为指定的模块(package)构建依赖内容（镜像拉取 或 可执行程序编译），并推送到指定环境。
#
#   对于type为"exec"的依赖包，build-depends.sh负责编译多平台二进制可执行程序，
#   编译结果输出到 packages/{name}/{os}/{arch}/{version}/ 目录，
#   后续由 build-components.sh 对编译结果进行签名打包。
#
#   对于type为"docker"的依赖包，构建/拉取docker镜像，
#   构建成功后将镜像导出为tar文件保存到 images/{packageName}/ 目录下。
#
#   对于type为"frontend"的依赖包，构建阶段行为与"docker"一致（本地clone源码并执行build命令），
#   但构建产物为前端静态资源，不涉及docker镜像的保存和推送操作。
#
#   待构建的内容，由depends/{package}.json进行定义，该文件内容如下所示：
#
#   exec类型示例（编译多平台二进制可执行程序）：
#     {
#        "name": "costrict-admin",
#        "type": "exec",
#        "remote": "git@github.com:zgsm-sangfor/costrict-admin.git",
#        "path": "../costrict-admin",
#        "platforms": [
#          { "os": "linux", "arch": "amd64" },
#          { "os": "windows", "arch": "amd64" }
#        ],
#        "build": {
#          "workdir": "../costrict-admin/utility"
#        },
#        "version": "1.0.133",
#        "description": "Utilities for backend management of Costrict"
#      }
#
#   docker类型示例（拉取镜像）：
#     {
#        "name": "costrict-model-proxy",
#        "type": "docker",
#        "version": "1.0.1",
#        "remote": "git@github.com:zgsm-sangfor/costrict-model-proxy.git",
#        "repo": "zgsm",
#        "tag": "v{{.version}}",
#        "path": "../zgsm-ai/costrict-model-proxy",
#        "pull": {
#          "workdir": ".",
#          "command": "docker pull {{.repo}}/{{.name}}:v{{.version}}"
#        },
#        "update": {
#          "workdir": "./configures/common/costrict-model-proxy",
#          "command": "echo IMAGE_COSTRICT_MODEL_PROXY={{.repo}}/{{.name}}:v{{.version}} > ./image.env"
#        }
#      }
#
#   字段说明：
#   - name: 模块名
#   - version: 模块的版本
#   - type: 依赖类型，"exec"为编译多平台二进制程序，"docker"为构建或拉取docker镜像（既支持本地docker build，也支持从镜像仓库docker pull），"frontend"为构建前端静态资源（构建阶段与docker一致，但不涉及docker镜像的保存/推送）
#   - path: 源码目录路径（用于git clone目标目录；workdir默认值）
#   - remote: git仓库地址（在path目录不存在时用于clone）
#   - description: 模块描述
#
#   exec类型专用字段：
#   - platforms: 目标平台列表，每项包含os和arch（必填）
#   - build.command: 编译命令（可选，支持{{.version}}/{{.os}}/{{.arch}}/{{.output}}模板变量；默认使用python ./build.py）
#   - build.workdir: 执行编译命令的工作目录（可选，默认值为.path）
#
#   docker类型专用字段：
#   - repo: 镜像在docker hub中的仓库名（必填）
#   - tag: 镜像的标签（可选，默认值为'{{.version}}'）
#   - build.command: 构建镜像的命令
#   - build.workdir: 执行构建命令的工作目录（可选，默认值为.path）
#   - pull.command: 拉取镜像的命令
#   - pull.workdir: 执行拉取命令的工作目录（可选，默认值为.path）
#
#   组件更新字段（所有类型共用）：
#   - update.workdir: 更新组件时的工作目录
#   - update.command: 更新组件的命令
#
#   推送目标环境的相关参数，由.env中的环境变量(DH_ENV_NAMES, DH_ENV_URLS, DH_ENV_USERS, DH_ENV_PASSWORDS)
#   以及NFS_ENV_NAMES, NFS_ENV_URLS, NFS_ENV_USERS, NFS_ENV_PASSWORDS定义。
#
# 选项说明：
#   --push [<ENV>]      推送镜像。支持逗号分隔的多个环境名称或以下关键字：
#                         docker - 推送到 docker hub
#                         hub    - 推送到 docker hub + DH_ENV_NAMES 中的所有环境
#                         nfs    - 推送到 NFS_ENV_NAMES 中的所有环境
#                         all    - 推送到所有环境（docker + DH_ENV_NAMES + NFS_ENV_NAMES）
#                        其他值  - 作为具体环境名称，需在 DH_ENV_NAMES 或 NFS_ENV_NAMES 中存在
#                       每种环境由四个参数指定：
#                       名字(name), URL(url), 用户名(user)，密码(password)
#                       上传方式是，使用docker login登录（使用环境相关参数），然后docker push推送
#                       注意：仅对docker类型生效，exec/frontend类型跳过此步骤
#

source ./.env

# 将脚本所在目录加入 PATH，以便直接调用同目录下的其他脚本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$SCRIPT_DIR:$PATH"

usage() {
    echo "Usage: build-depends.sh [OPTIONS] [ACTIONS]"
    echo "Options:"
    echo "  -p, --packages <PACKAGES>    Package list (comma-separated, e.g., \"pkg1\", \"pkg1,pkg2,pkg3\")"
    echo "  --local                      Use local build mode (read build commands from .build instead of .pull)"
    echo "  -h, --help                   Help information"
    echo "Actions:"
    echo "  --build                      Need build depends"
    echo "  --update                     Update component information using the built dependencies"
    echo "  --push <ENV>                 Push depends. ENV must be specified; comma-separated env list or keywords:"
    echo "                               docker    - push to docker hub"
    echo "                               hub       - push to docker hub + DH_ENV_NAMES(${DH_ENV_NAMES[*]})"
    echo "                               nfs       - push to NFS_ENV_NAMES(${NFS_ENV_NAMES[*]})"
    echo "                               all       - push to docker hub + DH_ENV_NAMES(${DH_ENV_NAMES[*]})"
    echo "                                                          + NFS_ENV_NAMES(${NFS_ENV_NAMES[*]})"
    echo "                               <custom>  - specific environment name, selectable from DH_ENV_NAMES(${DH_ENV_NAMES[*]})"
    echo "                                                          or NFS_ENV_NAMES(${NFS_ENV_NAMES[*]})"
    echo "                               Examples: \"--push docker\", \"--push hub\", \"--push nfs\","
    echo "                                         \"--push test,prod\", \"--push all\", \"--push test,hub\""
    exit 1
}

# 写入或更新 build.json 构建状态文件
# 参数:
#   $1: type - "dependency" 或 "component"
#   $2: package_name - 包名
#   $3: version - 版本号
#   $4: field - 时间戳字段 ("build", "update", "push")
write_build_json() {
    local type="$1"
    local package_name="$2"
    local version="$3"
    local field="$4"

    local build_dir="builds/${type}/${package_name}/${version}"
    local build_file="${build_dir}/build.json"
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")

    mkdir -p "$build_dir"

    if [ -f "$build_file" ]; then
        # 更新现有文件：设置指定时间戳字段
        local tmp_file=$(mktemp)
        jq --arg time "$current_time" --arg field "$field" \
            '.timestamp[$field] = $time' "$build_file" > "$tmp_file" && mv "$tmp_file" "$build_file"
    else
        # 创建新文件，仅设置当前字段的时间戳，其余字段为空
        jq -n --arg pkg "$package_name" --arg ver "$version" --arg time "$current_time" --arg field "$field" \
            '{
                package: $pkg,
                version: $ver,
                timestamp: {
                    build: (if $field == "build" then $time else "" end),
                    update: (if $field == "update" then $time else "" end),
                    push: (if $field == "push" then $time else "" end)
                }
            }' > "$build_file"
    fi

    echo "Build status saved to $build_file (${field}=${current_time})"
}

# 检查模块是否被启用
# 参数: $1 - JSON文件路径
# 返回值: 0=启用, 1=禁用
is_module_enabled() {
    local json_file="$1"
    
    # 检查enabled字段，如果不存在或者不为false/"false", 则默认为启用(true)
    local is_enabled=$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$json_file" 2>/dev/null)
    if [ "$is_enabled" = "false" ]; then
        return 1
    fi
    return 0
}

enable_push() {
    local input="$1"
    
    # 如果参数为空，则不推送
    if [ -z "$input" ]; then
        return
    fi
    
    NEED_PUSH=true
    
    # 支持逗号分隔的多个环境
    IFS=',' read -ra env_list <<< "$input"
    
    PUSH_TARGETS=()
    for env_item in "${env_list[@]}"; do
        # 去除前后空格
        env_item=$(echo "$env_item" | xargs)
        
        case "$env_item" in
            all)
                # all 指向DH_ENV_NAMES和NFS_ENV_NAMES中的所有环境
                PUSH_TARGETS+=("docker")
                PUSH_TARGETS+=("${DH_ENV_NAMES[@]}")
                PUSH_TARGETS+=("${NFS_ENV_NAMES[@]}")
                ;;
            hub)
                PUSH_TARGETS+=("docker")
                PUSH_TARGETS+=("${DH_ENV_NAMES[@]}")
                ;;
            nfs)
                PUSH_TARGETS+=("${NFS_ENV_NAMES[@]}")
                ;;
            *)
                # 其他环境名称直接存储
                PUSH_TARGETS+=("$env_item")
                ;;
        esac
    done
}

# 默认参数值
NEED_BUILD=false
NEED_PUSH=false
NEED_UPDATE=false
USE_LOCAL_MODE=false
PUSH_TARGETS=()
PACKAGES=""

# Parse command line options
# 注意: --push:: 表示push选项有可选参数（双冒号表示可选）
args=$(getopt -o hp: --long help,packages:,build,push::,update,local -n 'build-depends.sh' -- "$@")
[ $? -ne 0 ] && usage

eval set -- "$args"

while true; do
    case "$1" in
        -p|--packages) PACKAGES="$2"; shift 2;;
        --build) NEED_BUILD=true; shift;;
        --push)
            case "$2" in
                "") enable_push ""; shift 2;;
                *) enable_push "$2"; shift 2;;
            esac
            ;;
        --update) NEED_UPDATE=true; shift;;
        --local) USE_LOCAL_MODE=true; shift;;
        -h|--help) usage; exit 0;;
        --) shift; break;;
        *) usage;;
    esac
done

# Function to get value from JSON using jq expression
# 参数: $1 - json file path, $2 - jq expression (text extracted from {{}})
# 使用jq从json_file获取数据，只负责获取值，不做模板替换（模板替换由render_template_ex的循环负责）
get_expr_value() {
    local json_file="$1"
    local expr="$2"
    
    # 使用jq从json_file获取数据
    local value
    value=$(jq -r "$expr" "$json_file" 2>/dev/null)
    local rc=$?
    
    # 如果jq执行失败或值为null/empty，返回空字符串
    if [ $rc -ne 0 ] || [ "$value" = "null" ] || [ -z "$value" ]; then
        echo ""
        return
    fi
    
    echo "$value"
}

# Function to render template using jq expressions from JSON file
# 参数: $1 - template string, $2 - json file path, $3 - os, $4 - arch, $5 - output
# 使用循环不断扫描替换后的结果，如果还有{{}}表达式则继续替换，直到没有为止
# 如果表达式是 os/arch/output，直接替换为参数值；否则从 JSON 文件查询
render_template_ex() {
    local template="$1"
    local json_file="$2"
    local os="$3"
    local arch="$4"
    local output="$5"
    local result="$template"
    
    # 循环扫描替换，直到结果中没有{{}}标记为止
    while [[ "$result" == *"{{"*"}}"* ]]; do
        # 查找所有{{text}}标记
        local matches
        matches=$(echo "$result" | grep -o -E '\{\{[^}]+\}\}' 2>/dev/null | sort -u)
        
        if [ -z "$matches" ]; then
            break
        fi
        
        # 逐项替换
        while IFS= read -r match; do
            if [ -z "$match" ]; then
                continue
            fi
            # 提取{{和}}之间的文本作为jq表达式
            local expr="${match:2:${#match}-4}"
            # 如果表达式是 os/arch/output，直接使用参数值；否则从 JSON 文件查询
            local value
            case "$expr" in
                os)     value="$os" ;;
                arch)   value="$arch" ;;
                output) value="$output" ;;
                *)      value=$(get_expr_value "$json_file" "$expr") ;;
            esac
            # 替换模板中的标记
            result="${result//$match/$value}"
        done <<< "$matches"
    done
    
    echo "$result"
}

# 单平台构建（渲染并执行构建命令）
# 参数:
#   $1: package_file - JSON 配置文件路径
#   $2: depend_workdir - 构建工作目录
#   $3: depend_command - 构建命令模板（支持 {{.os}}/{{.arch}}/{{.output}} 等模板变量）
#   $4: os - 目标操作系统（如 linux, windows, darwin）
#   $5: arch - 目标架构（如 amd64, arm64）
#   $6: output_target - 输出文件完整路径
build_single_platform() {
    local package_file="$1"
    local depend_workdir="$2"
    local depend_command="$3"
    local os="$4"
    local arch="$5"
    local output_target="$6"
    
    local rendered_cmd=$(render_template_ex "$depend_command" "$package_file" "$os" "$arch" "$output_target")
    echo "Executing: $rendered_cmd"
    (cd "$depend_workdir" && bash -c "$rendered_cmd")
    return $?
}

# 通用依赖构建函数，支持所有类型（exec / docker / frontend）
# - exec: 编译多平台二进制可执行程序（默认命令: python ./build.py）
# - docker: 构建/拉取 docker 镜像，构建后导出为 tar
# - frontend: 构建前端静态资源（不涉及 docker 镜像导出）
# 参数: $1 - package, $2 - config_file, $3 - name, $4 - path, $5 - version, $6 - type
build_other_dependency() {
    local package="$1"
    local package_file="$2"
    local depend_name="$3"
    local depend_path="$4"
    local depend_version="$5"
    local depend_type="$6"
    
    # 根据类型获取命令和工作目录
    local depend_remote=$(jq -r ".remote // empty" "$package_file")
    local depend_command=""
    local depend_workdir=""
    
    if [ "$USE_LOCAL_MODE" = true ]; then
        # 本地构建模式：从.build读取本地构建命令（如 docker build）
        depend_command=$(jq -r ".build.command // empty" "$package_file")
        depend_workdir=$(jq -r ".build.workdir // empty" "$package_file")
    else
        # 默认模式：从.pull读取远程拉取命令（如 docker pull）
        depend_command=$(jq -r ".pull.command // empty" "$package_file")
        depend_workdir=$(jq -r ".pull.workdir // empty" "$package_file")
    fi
    # 工作目录默认值为.path
    if [ -z "$depend_workdir" ] || [ "$depend_workdir" = "null" ] || [ "$depend_workdir" = "" ]; then
        depend_workdir="$depend_path"
    fi
    
    if [ -z "$depend_command" ] || [ "$depend_command" = "null" ] || [ "$depend_command" = "" ]; then
        if [ "$depend_type" = "exec" ]; then
            # exec 类型默认使用 build.py 构建
            depend_command="python ./build.py --software {{.version}} --os {{.os}} --arch {{.arch}} --output {{.output}}"
            echo "Using default build command for exec type: $depend_command"
        else
            echo "Error: 'command' not found for dependency '${package}' (type=${depend_type}) in ${package_file}!"
            return 1
        fi
    fi
    # 确保源码存在（docker/frontend/exec 类型需要本地源码）
    if [ "$depend_type" = "frontend" ] || [ "$depend_type" = "docker" ] || [ "$depend_type" = "exec" ]; then
        if [ ! -d "$depend_path" ]; then
            if [ -z "$depend_remote" ] || [ "$depend_remote" = "null" ]; then
                echo "Error: Directory '$depend_path' does not exist and 'remote' field is not configured!"
                return 1
            fi
            echo "Directory '$depend_path' not found, cloning from $depend_remote ..."
            git clone "$depend_remote" "$depend_path"
            if [ $? -ne 0 ]; then
                echo "Error: git clone failed for $depend_remote"
                return 1
            fi
            echo "Successfully cloned to '$depend_path'"
        fi
    fi
    # 检查 platforms 字段：exec 类型必填，其他类型默认 linux/amd64
    local depend_platforms=$(jq -r ".platforms // empty" "$package_file")
    if [ -z "$depend_platforms" ] || [ "$depend_platforms" = "null" ] || [ "$depend_platforms" = "" ]; then
        if [ "$depend_type" = "exec" ]; then
            echo "Error: 'platforms' not found for exec package '${depend_name}' in ${package_file}!"
            return 1
        fi
        depend_platforms='[{"os":"linux","arch":"amd64"}]'
    fi
    
    # ============================================================
    # 分平台编译
    # ============================================================
    local current_dir=$(pwd)
    
    # 解析 platforms 数组
    local platform_count=$(echo "$depend_platforms" | jq 'length')
    echo "=============================================="
    echo "Processing dependency: $depend_name, type: $depend_type, version: $depend_version"
    echo "Path: $depend_path"
    echo "Workdir: $depend_workdir"
    echo "Building for $platform_count platform(s): $depend_platforms"
    echo "=============================================="
    
    local i
    for ((i=0; i<platform_count; i++)); do
        local os=$(echo "$depend_platforms" | jq -r ".[$i].os")
        local arch=$(echo "$depend_platforms" | jq -r ".[$i].arch")
        
        echo "==== Building $depend_name for $os/$arch ===="
        
        # 创建输出目录: packages/{name}/{os}/{arch}/{version}/
        local output_dir="$current_dir/packages/$depend_name/$os/$arch/$depend_version"
        mkdir -p "$output_dir"
        
        # 设置输出文件名
        local output_file="$depend_name"
        if [ "$os" = "windows" ]; then
            output_file="$output_file.exe"
        fi
        
        local output_target="$output_dir/$output_file"
        echo "Output target: $output_target"
        
        # 调用单平台构建函数
        build_single_platform "$package_file" "$depend_workdir" "$depend_command" "$os" "$arch" "$output_target"
        if [ $? -ne 0 ]; then
            echo "Error: Build failed for $depend_name on $os/$arch"
            return 1
        fi
        echo ""
    done
    
    echo "All platforms built successfully for dependency: $depend_name"
    # 构建/拉取成功后，导出docker镜像tar文件（docker/github类型；frontend类型跳过）
    save_docker_image "$package" || return 1
    return 0
}

build_dependency() {
    local package="$1"
    local package_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$package_file" ]; then
        echo "Error: configuration file $package_file does not exist!"
        return 1
    fi
    
    # 从depends目录的对应JSON文件中获取配置
    local depend_name=$(jq -r ".name // empty" "$package_file")
    local depend_path=$(jq -r ".path // empty" "$package_file")
    local depend_version=$(jq -r ".version // empty" "$package_file")
    local depend_type=$(jq -r ".type // empty" "$package_file")
    
    if [ -z "$depend_name" ] || [ "$depend_name" = "null" ] || [ "$depend_name" = "" ]; then
        echo "Error: 'name' not found for package '${package}' in ${package_file}!"
        return 1
    fi
    
    if [ -z "$depend_version" ] || [ "$depend_version" = "null" ] || [ "$depend_version" = "" ]; then
        echo "Error: 'version' not found for package '${package}' in ${package_file}!"
        return 1
    fi
    
    if [ -z "$depend_path" ] || [ "$depend_path" = "null" ] || [ "$depend_path" = "" ]; then
        echo "Error: 'path' not found for package '${package}' in ${package_file}!"
        return 1
    fi
    # 统一委托给 build_other_dependency（支持 exec / docker / frontend 所有类型）
    build_other_dependency "$package" "$package_file" "$depend_name" "$depend_path" "$depend_version" "$depend_type"
    return $?
}

# 对 docker 类型的依赖包导出镜像tar文件；
# 对 exec/frontend 类型跳过（不涉及 docker 镜像）。
# 参数: $1 - package name
save_docker_image() {
    local package="$1"
    local package_file="depends/${package}.json"
    
    # 获取依赖类型
    local depend_type=$(jq -r ".type // empty" "$package_file")
    
    # exec / frontend 类型：无需导出docker镜像
    if [ "$depend_type" = "exec" ] || [ "$depend_type" = "frontend" ]; then
        local depend_name=$(jq -r ".name // empty" "$package_file")
        echo "Skipping image export for ${depend_type}-type package '${depend_name}' (no docker image to export)"
        return 0
    fi

    # 以下仅处理 docker 类型
    local depend_name=$(jq -r ".name // empty" "$package_file")
    local depend_version=$(jq -r ".version // empty" "$package_file")
    local depend_repo=$(jq -r ".repo // empty" "$package_file")
    local depend_tag=$(jq -r ".tag // empty" "$package_file")
    
    # tag字段为可选的，默认值为 '{{.version}}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{.version}}"
    fi

    # 创建输出目录
    local image_dir="images/${depend_name}"
    mkdir -p "$image_dir"
    
    local image_full_name=$(render_template_ex "${depend_repo}/${depend_name}:${depend_tag}" "$package_file")
    local tar_file=$(render_template_ex "${depend_name}-${depend_tag}.tar" "$package_file")
    
    echo "=============================================="
    echo "Exporting image: $image_full_name"
    echo "=============================================="
    
    # 导出镜像为tar文件
    echo "Saving image to ${image_dir}/${tar_file}..."
    docker save -o "${image_dir}/${tar_file}" "$image_full_name"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to export image $image_full_name"
        return 1
    fi
    
    echo "Successfully exported image to ${image_dir}/${tar_file}"
    return 0
}

# 根据依赖配置文件中'update'字段的定义，使用本次构建结果更新组件的信息
update_component() {
    local package="$1"
    local package_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$package_file" ]; then
        echo "Error: Image configuration file $package_file does not exist!"
        return 1
    fi
    
    # 检查update字段是否存在
    local has_update=$(jq -r 'has("update")' "$package_file")
    if [ "$has_update" != "true" ]; then
        echo "Skipping component update for ${package} (update field not found)..."
        return
    fi
    
    # 从配置文件中获取update.workdir和update.command
    local workdir=$(jq -r ".update.workdir // empty" "$package_file")
    local command=$(jq -r ".update.command // empty" "$package_file")
    
    # 获取package name用于显示
    local package_name=$(jq -r ".name // empty" "$package_file")
    
    # 检查workdir是否为空
    if [ -z "$workdir" ] || [ "$workdir" = "null" ] || [ "$workdir" = "" ]; then
        echo "Skipping component update for ${package} (update.workdir not found)..."
        return
    fi
    
    # 检查command是否为空
    if [ -z "$command" ] || [ "$command" = "null" ] || [ "$command" = "" ]; then
        echo "Skipping component update for ${package} (update.command not found)..."
        return
    fi
    
    echo "=============================================="
    echo "Updating component: $package_name"
    echo "Workdir: $workdir"
    echo "=============================================="
    
    # 渲染命令模板
    local rendered_command=$(render_template_ex "$command" "$package_file")
    echo "Executing: $rendered_command"
    
    # 执行命令（在指定的工作目录下）
    (cd "$workdir" && bash -c "$rendered_command")
    if [ $? -ne 0 ]; then
        echo "Error: Component update failed for $package_name"
        return 1
    fi
    
    echo "Successfully updated component: $package_name"
    return 0
}

# Function to push an image
push_image() {
    local package="$1"
    local package_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$package_file" ]; then
        echo "Error: Image configuration file $package_file does not exist!"
        return 1
    fi
    
    # 从depends目录的对应JSON文件中获取配置
    local depend_name=$(jq -r ".name // empty" "$package_file")
    local depend_version=$(jq -r ".version // empty" "$package_file")
    local depend_repo=$(jq -r ".repo // empty" "$package_file")
    local depend_tag=$(jq -r ".tag // empty" "$package_file")
    
    # tag字段为可选的，默认值为 '{{.version}}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{.version}}"
    fi
    
    if [ -z "$depend_name" ] || [ "$depend_name" = "null" ]; then
        echo "Error: 'name' not found for image '${package}' in ${package_file}!"
        return 1
    fi
    
    local depend_full_name=$(render_template_ex "${depend_repo}/${depend_name}:${depend_tag}" "$package_file")
    
    echo "=============================================="
    echo "Pushing image: $depend_full_name"
    echo "=============================================="
    
    docker push "$depend_full_name"
    if [ $? -ne 0 ]; then
        echo "Error: Push failed for image $depend_full_name"
        return 1
    fi
    
    echo "Successfully pushed image: $depend_full_name"
    return 0
}

upload_image() {
    local source_dir=$1
    local package=$2
    local ip=$3
    local port=$4
    local rootDir=$5

    local formalDir="${rootDir}/images"
    local uploadDir="${rootDir}/images-upload"

    local package_path="${source_dir}/${package}"

    echo rsync -avzP -e "ssh -p ${port}" ${package_path} "root@${ip}:${uploadDir}/"
    rsync -avzP -e "ssh -p ${port}" ${package_path} "root@${ip}:${uploadDir}/"

    ssh -p "${port}" "root@${ip}" <<EOF
        set -e
        echo "Transfer ${package} to formal directory..."
        if [ -d "${formalDir}/${package}" ]; then
            mv "${formalDir}/${package}" "${uploadDir}/${package}-tmp"
        fi
        mv "${uploadDir}/${package}" "${formalDir}/${package}"
        if [ -d "${uploadDir}/${package}-tmp" ]; then
            mv "${uploadDir}/${package}-tmp" "${uploadDir}/${package}"
        fi
EOF
}

upload_image_to_nfs() {
    local package="$1"
    local env_name="$2"
    
    # 验证环境名称是否在NFS_ENV_NAMES中
    local valid_env=false
    local env_index=-1
    local i=0
    for valid_name in "${NFS_ENV_NAMES[@]}"; do
        if [ "$env_name" = "$valid_name" ]; then
            valid_env=true
            env_index=$i
            break
        fi
        ((i++))
    done
    
    if [ "$valid_env" = false ]; then
        echo "Error: Invalid environment name '$env_name'. Available NFS environments: ${NFS_ENV_NAMES[*]}"
        return 1
    fi
    
    # 根据索引从数组中获取配置
    local host="${NFS_ENV_HOSTS[$env_index]}"
    local port="${NFS_ENV_PORTS[$env_index]}"
    local path="${NFS_ENV_PATHS[$env_index]}"
    
    echo "=============================================="
    echo "Upload image $package to NFS ${env_name} (${host}:${port}${path})..."
    echo "=============================================="
    upload_image "images" "${package}" "${host}" "${port}" "${path}"
}

# Function to upload image to environment
upload_image_to_dh() {
    local package="$1"
    local env_name="$2"
    
    # 验证环境名称是否在DH_ENV_NAMES中
    local valid_env=false
    local env_index=-1
    local i=0
    for valid_name in "${DH_ENV_NAMES[@]}"; do
        if [ "$env_name" = "$valid_name" ]; then
            valid_env=true
            env_index=$i
            break
        fi
        ((i++))
    done
    
    if [ "$valid_env" = false ]; then
        echo "Error: Invalid environment name '$env_name'. Available environments: ${DH_ENV_NAMES[*]}"
        return 1
    fi
    
    # 根据索引从数组中获取配置
    local env_url="${DH_ENV_URLS[$env_index]}"
    local env_user="${DH_ENV_USERS[$env_index]}"
    local env_password="${DH_ENV_PASSWORDS[$env_index]}"
    
    # 获取镜像信息
    local package_file="depends/${package}.json"
    local depend_name=$(jq -r ".name // empty" "$package_file")
    local depend_version=$(jq -r ".version // empty" "$package_file")
    local depend_repo=$(jq -r ".repo // empty" "$package_file")
    local depend_tag=$(jq -r ".tag // empty" "$package_file")
    
    # tag字段为可选的，默认值为 '{{.version}}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{.version}}"
    fi
    
    local depend_full_name=$(render_template_ex "${depend_repo}/${depend_name}:${depend_tag}" "$package_file")
    echo "=============================================="
    echo "Uploading image $depend_full_name to environment: $env_name ($env_url)"
    echo "=============================================="
    
    # 登录到镜像仓库
    echo "Logging in to $env_url..."
    echo "$env_password" | docker login "$env_url" --username "$env_user" --password-stdin
    if [ $? -ne 0 ]; then
        echo "Error: Login failed to $env_url"
        return 1
    fi
    
    # 推送镜像
    docker push "$depend_full_name"
    if [ $? -ne 0 ]; then
        echo "Error: Push failed for image $depend_full_name"
        docker logout "$env_url"
        return 1
    fi
    
    # 登出
    docker logout "$env_url"
    
    echo "Successfully uploaded image $depend_full_name to environment $env_name"
    return 0
}

# 检查元素是否在数组中
# 参数: $1 - 要查找的元素, $2 - 数组名（不含$和花括号）
is_in_array() {
    local element="$1"
    local array_name="$2[@]"
    local array=("${!array_name}")
    for item in "${array[@]}"; do
        if [ "$item" = "$element" ]; then
            return 0
        fi
    done
    return 1
}

# Function to upload images to multiple environments
push_image_to_remotes() {
    local package="$1"
    
    # 遍历PUSH_TARGETS数组中的每个环境名称
    for env_name in "${PUSH_TARGETS[@]}"; do
        if [ "$env_name" = "docker" ]; then
            push_image "$package"
        elif is_in_array "$env_name" DH_ENV_NAMES; then
            upload_image_to_dh "$package" "$env_name"
        elif is_in_array "$env_name" NFS_ENV_NAMES; then
            upload_image_to_nfs "$package" "$env_name"
        else
            echo "Warning: Unknown environment '$env_name', skipping..."
        fi
    done
}

# Function to process a single package
process_package() {
    local package_name=$1
    local package_file="depends/${package_name}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$package_file" ]; then
        echo "Error: configuration file 'depends/${package_name}.json' does not exist!"
        exit 1
    fi
    
    # 获取依赖类型，用于后续判断是否跳过 docker 相关操作
    local depend_type=$(jq -r ".type // empty" "$package_file")
    # 获取 name 和 version 字段，用于 write_build_json
    local depend_name=$(jq -r ".name // empty" "$package_file")
    local depend_version=$(jq -r ".version // empty" "$package_file")
    
    if [ "$NEED_BUILD" = true ]; then
        echo "Building 'dependency' for ${package_name}..."
        build_dependency "${package_name}"
        if [ $? -ne 0 ]; then
            echo "Error: Build failed for ${package_name}"
            exit 1
        fi
        
        # 写入 build.json 记录构建完成时间戳
        write_build_json "dependency" "${depend_name}" "${depend_version}" "build"
    else
        echo "Skipping build step for ${package_name}..."
    fi
    
    # 更新组件信息（仅当使用--update选项时）
    if [ "$NEED_UPDATE" = true ]; then
        echo "Updating component for ${package_name}..."
        update_component "${package_name}"
        if [ $? -ne 0 ]; then
            echo "Warning: Component update failed for ${package_name}"
            # 继续执行，不退出
        else
            # 写入 build.json 记录 update 完成时间戳
            write_build_json "dependency" "${depend_name}" "${depend_version}" "update"
        fi
    else
        echo "Skipping update step for ${package_name}..."
    fi
    
    # push 操作仅对 docker 类型生效，exec / frontend 类型跳过
    if [ "$depend_type" = "exec" ] || [ "$depend_type" = "frontend" ]; then
        echo "Skipping push step for ${depend_type}-type package '${package_name}' (no docker image to push)..."
    else
        # 如果有指定的上传目标环境，上传到这些环境
        if [ "$NEED_PUSH" = true ] && [ ${#PUSH_TARGETS[@]} -gt 0 ]; then
            echo "Pushing image to specified environments: ${package_name}"
            push_image_to_remotes "${package_name}"
            if [ $? -ne 0 ]; then
                echo "Error: Upload failed for ${package_name}"
                exit 1
            fi
            # 写入 build.json 记录 push 完成时间戳
            write_build_json "dependency" "${depend_name}" "${depend_version}" "push"
        else
            echo "Skipping push step for ${package_name}..."
        fi
    fi
}

# Function to process multiple packages
process_packages() {
    local packages=$1
    
    # 解析包列表（支持逗号分隔的包名）
    local package_list=()
    if [ -n "$packages" ]; then
        IFS=',' read -ra package_list <<< "$packages"
    fi
    
    # 如果包列表为空，从depends目录读取所有JSON文件
    if [ ${#package_list[@]} -eq 0 ]; then
        echo "No packages specified, reading from depends directory..."
        if [ -d "depends" ]; then
            for json_file in depends/*.json; do
                if [ -f "$json_file" ]; then
                    # 检查模块是否启用，如果禁用则跳过
                    if is_module_enabled "$json_file"; then
                        local package_name=$(basename "$json_file" .json)
                        package_list+=("$package_name")
                    fi
                fi
            done
        fi
    fi
    
    echo "Processing ${#package_list[@]} package(s): ${package_list[*]}"
    echo ""
    
    # 遍历每个包并处理
    for pkg in "${package_list[@]}"; do
        echo "=============================================="
        echo "Processing package: $pkg"
        echo "=============================================="
        process_package "$pkg"
        echo ""
    done
    
    echo "All packages processed successfully!"
}

# 检查docker命令是否可用（仅 docker 类型需要，exec / frontend 类型不需要）
if ! command -v docker >/dev/null 2>&1; then
    echo "Warning: docker command not found. Only exec-type and frontend-type packages can be built without Docker."
    echo "  For docker type packages, please install Docker."
fi

# 检查jq工具是否可用
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq command not found! Please install jq to parse JSON files."
    echo "Installation instructions:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  CentOS/RHEL: sudo yum install jq"
    echo "  macOS: brew install jq"
    echo "  Windows: Download from https://stedolan.github.io/jq/download/"
    exit 1
fi

# 检查depends目录是否存在
if [ ! -d "depends" ]; then
    echo "Error: 'depends' directory not found!"
    exit 1
fi

# 检查depends目录中是否有JSON文件
if [ -z "$(ls -A depends/*.json 2>/dev/null)" ]; then
    echo "Error: No JSON files found in depends directory!"
    exit 1
fi

# 根据参数决定处理方式
if [ -n "$PACKAGES" ]; then
    # 处理指定的包列表
    process_packages "$PACKAGES"
else
    process_packages ""
fi

echo "Build completed."
