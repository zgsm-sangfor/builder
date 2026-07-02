#!/bin/bash

#
# 功能：
#   build-depends.sh为指定的模块(package)构建依赖内容（镜像拉取 或 可执行程序编译），并推送到指定环境。
#
#   对于type为"exec"的依赖包，build-depends.sh负责编译多平台二进制可执行程序，
#   编译结果输出到 packages/{name}/{os}/{arch}/{version}/ 目录，
#   后续由 build-components.sh 对编译结果进行签名打包。
#
#   对于type为"docker"或"github"的依赖包，构建/拉取docker镜像，
#   构建成功后会在 images/{packageName}/versions.json 中记录版本信息，
#   并将构建好的镜像导出为tar文件保存到 images/{packageName}/ 目录下。
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
#   github类型示例：
#     {
#        "name": "costrict-model-proxy",
#        "type": "github",
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
#   - type: 依赖类型，"exec"为编译多平台二进制程序，"github"为从镜像仓库拉取，"docker"为本地构建docker镜像，"frontend"为构建前端静态资源（构建阶段与docker一致，但不涉及docker镜像的保存/推送）
#   - path: 源码目录路径（用于git clone目标目录；workdir默认值）
#   - remote: git仓库地址（在path目录不存在时用于clone）
#   - description: 模块描述
#
#   exec类型专用字段：
#   - platforms: 目标平台列表，每项包含os和arch（必填）
#   - build.command: 编译命令（可选，支持{{.version}}/{{.os}}/{{.arch}}/{{.output}}模板变量；默认使用python ./build.py）
#   - build.workdir: 执行编译命令的工作目录（可选，默认值为.path）
#
#   github/docker类型专用字段：
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
#   推送目标环境的相关参数，由.env中的环境变量(DH_ENV_NAMES, DH_ENV_URLS, DH_ENV_USERS, DH_ENV_PASSWORDS)定义。
#
# 选项说明：
#   --push [<ENV>]      推送镜像。如果参数为空或包含"def"，则推送到docker hub；
#                       否则上传到指定环境（沿用upload选项逻辑）。每种环境由四个参数指定：
#                       名字(name), URL(url), 用户名(user)，密码(password)
#                       上传方式是，使用docker login登录（使用环境相关参数），然后docker push推送
#                       注意：仅对github/docker类型生效，exec类型跳过此步骤
#

source ./.env

usage() {
    echo "Usage: build-depends.sh [OPTIONS] [ACTIONS]"
    echo "Options:"
    echo "  -p, --packages <PACKAGES>    Package list (comma-separated, e.g., \"pkg1\", \"pkg1,pkg2,pkg3\")"
    echo "  -h, --help                   Help information"
    echo "Actions:"
    echo "  --build                      Need build depends"
    echo "  --update                     Update component information using the built dependencies"
    echo "  --push [<ENV>]               Push depends. If ENV is empty or contains 'def', push to docker hub;"
    echo "                               otherwise upload to specified environments (comma-separated env list)"
    echo "                               Supported envs: names from .env DH_ENV_NAMES array (${DH_ENV_NAMES[*]})"
    echo "                               Keywords: def (${DH_ENV_NAMES[0]}), all (${DH_ENV_NAMES[*]})"
    echo "                               Examples: \"--push\", \"--push def\", \"--push test,prod\", \"--push all\", \"--push test,all\""
    exit 1
}

# 写入或更新 build.json 构建状态文件
# 参数:
#   $1: type - "dependency" 或 "component"
#   $2: package_name - 包名
#   $3: version - 版本号
#   $4: field - 时间戳字段 ("build", "update", "push", "upload")
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
                    push: (if $field == "push" then $time else "" end),
                    upload: (if $field == "upload" then $time else "" end)
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
    
    # 检查enabled字段，如果不存在则默认为启用(true)
    # 使用 jq 的布尔逻辑：当 enabled 不存在或不为 false/字符串"false" 时返回真
    local is_enabled=$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$json_file" 2>/dev/null)
    
    # 如果enabled字段的值为false（布尔值或字符串），则禁用
    if [ "$is_enabled" = "false" ]; then
        return 1
    fi
    
    return 0
}

enable_push() {
    NEED_PUSH=true
    local input="$1"
    
    # 如果参数为空，则推送到 docker hub
    if [ -z "$input" ]; then
        PUSH_TO_DOCKER_HUB=true
        return
    fi
    
    # 支持逗号分隔的多个环境
    IFS=',' read -ra env_list <<< "$input"
    
    UPLOAD_TARGETS=()
    for env_item in "${env_list[@]}"; do
        # 去除前后空格
        env_item=$(echo "$env_item" | xargs)
        
        case "$env_item" in
            def)
                # def 表示推送到 docker hub
                PUSH_TO_DOCKER_HUB=true
                ;;
            all)
                # all 指向DH_ENV_NAMES中的所有环境
                UPLOAD_TARGETS+=("${DH_ENV_NAMES[@]}")
                ;;
            *)
                # 其他环境名称直接存储
                UPLOAD_TARGETS+=("$env_item")
                ;;
        esac
    done
}

# 默认参数值
NEED_BUILD=false
NEED_PUSH=false
NEED_UPDATE=false
PUSH_TO_DOCKER_HUB=false
UPLOAD_TARGETS=()
PACKAGES=""

# Parse command line options
# 注意: --push:: 表示push选项有可选参数（双冒号表示可选）
args=$(getopt -o hp: --long help,packages:,build,push::,update -n 'build-depends.sh' -- "$@")
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
        -h|--help) usage; exit 0;;
        --) shift; break;;
        *) usage;;
    esac
done

# Function to render template using go text/template syntax
# 参数: $1 - template string, $2 - json file path, $3 - workdir (optional)
# Function to render template using go text/template syntax (用于github/docker类型的docker命令)
# 参数: $1 - template string, $2 - json file path, $3 - workdir (optional)
render_template() {
    local template="$1"
    local json_file="$2"
    local workdir="$3"
    
    # 使用jq将JSON转换为可以被go template使用的格式
    # 这里简化处理：直接替换{{.field}}为对应的JSON值
    local result="$template"
    
    # 获取JSON中的所有字段（排除command和tag）
    local name=$(jq -r '.name // empty' "$json_file")
    local version=$(jq -r '.version // empty' "$json_file")
    local path=$(jq -r '.path // empty' "$json_file")
    local description=$(jq -r '.description // empty' "$json_file")
    local repo=$(jq -r '.repo // empty' "$json_file")
    
    # 替换 {{.name}} 格式（不带空格）
    result="${result//\{\{.name\}\}/$name}"
    result="${result//\{\{.version\}\}/$version}"
    result="${result//\{\{.path\}\}/$path}"
    result="${result//\{\{.description\}\}/$description}"
    result="${result//\{\{.repo\}\}/$repo}"
    result="${result//\{\{.workdir\}\}/$workdir}"
    
    echo "$result"
}

# Function to render build command template (用于exec类型二进制编译)
# 支持 {{.version}}, {{.os}}, {{.arch}}, {{.output}} 模板变量
# 参数: $1 - template string, $2 - version, $3 - os, $4 - arch, $5 - output
render_build_template() {
    local template="$1"
    local version="$2"
    local os="$3"
    local arch="$4"
    local output="$5"
    
    local result="$template"
    result="${result//\{\{.version\}\}/$version}"
    result="${result//\{\{.os\}\}/$os}"
    result="${result//\{\{.arch\}\}/$arch}"
    result="${result//\{\{.output\}\}/$output}"
    
    echo "$result"
}

# Function to build exec-type binary for multiple platforms (编译多平台二进制可执行程序)
# 将 build-components.sh 中的 build_app 逻辑迁移至此，build-components.sh 仅负责签名打包
# 参数: $1 - package_name, $2 - version, $3 - source_dir, $4 - platforms_json, $5 - package_config_file
build_exec_binary() {
    local package_name="$1"
    local version="$2"
    local source_dir="$3"
    local platforms_json="$4"
    local package_config_file="$5"

    # 获取当前路径的绝对路径
    local current_dir=$(pwd)
    
    # 从配置文件中读取 exec 类型专用字段
    local package_remote=$(jq -r ".remote // empty" "$package_config_file")
    local build_workdir=$(jq -r ".build.workdir // empty" "$package_config_file")
    local build_command=$(jq -r ".build.command // empty" "$package_config_file")

    # 检查源路径是否存在，不存在则尝试从remote克隆
    if [ ! -d "$source_dir" ]; then
        if [ -n "$package_remote" ] && [ "$package_remote" != "null" ] && [ "$package_remote" != "" ]; then
            echo "Directory '$source_dir' not found, cloning from $package_remote ..."
            mkdir -p "$(dirname "$source_dir")"
            git clone "$package_remote" "$source_dir"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to clone from $package_remote"
                exit 1
            fi
            echo "Successfully cloned to '$source_dir'"
        else
            echo "Error: Source directory $source_dir does not exist!"
            exit 1
        fi
    fi

    # 解析platforms数组
    local platform_count=$(echo "$platforms_json" | jq 'length')

    # 确定工作目录：build.workdir 存在则使用，否则使用 path 指定的目录
    local work_dir="$source_dir"
    if [ -n "$build_workdir" ] && [ "$build_workdir" != "null" ] && [ "$build_workdir" != "" ]; then
        work_dir="$build_workdir"
    fi

    echo "Starting multi-platform build for package: $package_name, version: $version"
    echo "Source directory: $source_dir"
    echo "Work directory: $work_dir"
    echo "Building for $platform_count platform(s): $platforms_json"

    # 遍历每个平台
    local i
    for ((i=0; i<platform_count; i++)); do
        local os=$(echo "$platforms_json" | jq -r ".[$i].os")
        local arch=$(echo "$platforms_json" | jq -r ".[$i].arch")
        
        echo "==== Building $package_name for $os/$arch ===="
        
        # 创建输出目录: packages/{name}/{os}/{arch}/{version}/
        local output_dir="$current_dir/packages/$package_name/$os/$arch/$version"
        mkdir -p "$output_dir"
        
        # 设置输出文件名
        local output_file="$package_name"
        if [ "$os" = "windows" ]; then
            output_file="$output_file.exe"
        fi
        
        # 完整输出路径
        local output_target="$output_dir/$output_file"
        
        echo "Output target: $output_target"
        
        # 执行构建：优先使用自定义构建命令，否则使用默认的 build.py
        if [ -n "$build_command" ] && [ "$build_command" != "null" ] && [ "$build_command" != "" ]; then
            # 使用自定义构建命令，支持 {{.version}} {{.os}} {{.arch}} {{.output}} 模板
            local rendered_cmd=$(render_build_template "$build_command" "$version" "$os" "$arch" "$output_target")
            echo "Executing custom build command: $rendered_cmd"
            (cd "$work_dir" && bash -c "$rendered_cmd")
        else
            # 使用默认构建方式
            echo "Executing default build: python ./build.py --software $version --os $os --arch $arch --output $output_target"
            (cd "$work_dir" && python ./build.py --software "$version" --os "$os" --arch "$arch" --output "$output_target")
        fi
        if [ $? -ne 0 ]; then
            echo "Build failed for $package_name on $os/$arch"
            exit 1
        fi
        echo ""
    done
    
    echo "All apps built successfully for package: $package_name"
}

# Function to build a docker/github/frontend-type dependency (docker 镜像拉取/构建 或 前端静态资源构建)
# 参数: $1 - package, $2 - config_file, $3 - name, $4 - path, $5 - version, $6 - type
build_other_dependency() {
    local package="$1"
    local depend_config_file="$2"
    local depend_name="$3"
    local depend_path="$4"
    local depend_version="$5"
    local depend_type="$6"
    
    local depend_remote=$(jq -r ".remote // empty" "$depend_config_file")
    
    # 根据类型获取命令和工作目录
    local depend_command=""
    local depend_workdir=""
    
    if [ "$depend_type" = "github" ]; then
        # github类型：从.pull.command获取命令，从.pull.workdir获取工作目录（默认值为.path）
        depend_command=$(jq -r ".pull.command // empty" "$depend_config_file")
        depend_workdir=$(jq -r ".pull.workdir // empty" "$depend_config_file")
    elif [ "$depend_type" = "frontend" ]; then
        # frontend类型：从.build.command获取命令，从.build.workdir获取工作目录（默认值为.path）
        depend_command=$(jq -r ".build.command // empty" "$depend_config_file")
        depend_workdir=$(jq -r ".build.workdir // empty" "$depend_config_file")
    else
        # docker类型：从.build.command获取命令，从.build.workdir获取工作目录（默认值为.path）
        depend_command=$(jq -r ".build.command // empty" "$depend_config_file")
        depend_workdir=$(jq -r ".build.workdir // empty" "$depend_config_file")
    fi
    # 工作目录默认值为.path
    if [ -z "$depend_workdir" ] || [ "$depend_workdir" = "null" ] || [ "$depend_workdir" = "" ]; then
        depend_workdir="$depend_path"
    fi
    
    if [ -z "$depend_command" ] || [ "$depend_command" = "null" ] || [ "$depend_command" = "" ]; then
        echo "Error: 'command' not found for dependency '${package}' (type=${depend_type}) in ${depend_config_file}!"
        return 1
    fi
    
    echo "=============================================="
    echo "Processing dependency: $depend_name, type: $depend_type, version: $depend_version"
    echo "Path: $depend_path"
    echo "Workdir: $depend_workdir"
    echo "=============================================="
    
    # 渲染命令模板
    local rendered_command=$(render_template "$depend_command" "$depend_config_file" "$depend_workdir")
    echo "Executing: $rendered_command"
    
    if [ "$depend_type" = "frontend" ] || [ "$depend_type" = "docker" ]; then
        # docker和frontend类型：需要本地代码，所以需要先检查源码目录是否存在，不存在则从remote克隆
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

    if [ "$depend_type" = "github" ]; then
        # github类型：镜像已由github action自动编译上传，仅需从镜像仓库拉取
        (cd "$depend_workdir" && bash -c "$rendered_command")
        if [ $? -ne 0 ]; then
            echo "Error: Pull failed for dependency $depend_name (type=$depend_type)"
            return 1
        fi
        echo "Successfully pulled image: $depend_name"
    elif [ "$depend_type" = "frontend" ]; then        
        # cd到工作目录后执行构建命令
        (cd "$depend_workdir" && bash -c "$rendered_command")
        if [ $? -ne 0 ]; then
            echo "Error: Build failed for frontend dependency $depend_name (type=$depend_type)"
            return 1
        fi
        echo "Successfully built frontend: $depend_name"
    else
        # cd到工作目录后执行构建命令
        (cd "$depend_workdir" && bash -c "$rendered_command")
        if [ $? -ne 0 ]; then
            echo "Error: Build failed for docker dependency $depend_name (type=$depend_type)"
            return 1
        fi
        echo "Successfully built image: $depend_name"
    fi
    return 0
}

build_dependency() {
    local package="$1"
    local depend_config_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$depend_config_file" ]; then
        echo "Error: configuration file $depend_config_file does not exist!"
        return 1
    fi
    
    # 从depends目录的对应JSON文件中获取配置
    local depend_name=$(jq -r ".name // empty" "$depend_config_file")
    local depend_path=$(jq -r ".path // empty" "$depend_config_file")
    local depend_version=$(jq -r ".version // empty" "$depend_config_file")
    local depend_type=$(jq -r ".type // empty" "$depend_config_file")
    
    if [ -z "$depend_name" ] || [ "$depend_name" = "null" ] || [ "$depend_name" = "" ]; then
        echo "Error: 'name' not found for package '${package}' in ${depend_config_file}!"
        return 1
    fi
    
    if [ -z "$depend_version" ] || [ "$depend_version" = "null" ] || [ "$depend_version" = "" ]; then
        echo "Error: 'version' not found for package '${package}' in ${depend_config_file}!"
        return 1
    fi
    
    if [ -z "$depend_path" ] || [ "$depend_path" = "null" ] || [ "$depend_path" = "" ]; then
        echo "Error: 'path' not found for package '${package}' in ${depend_config_file}!"
        return 1
    fi
    # ============================================================
    # exec 类型：编译多平台二进制可执行程序
    # ============================================================
    if [ "$depend_type" = "exec" ]; then
        # platforms 字段对 exec 类型是必填的
        local depend_platforms=$(jq -r ".platforms // empty" "$depend_config_file")
        if [ -z "$depend_platforms" ] || [ "$depend_platforms" = "null" ] || [ "$depend_platforms" = "" ]; then
            echo "Error: 'platforms' not found for exec package '${package}' in ${depend_config_file}!"
            return 1
        fi
        
        # 计算source_dir
        local current_dir=$(pwd)
        local source_dir="$current_dir/$depend_path"
        
        echo "=============================================="
        echo "Building exec binary: $depend_name, version: $depend_version"
        echo "Path: $depend_path"
        echo "Platforms: $depend_platforms"
        echo "=============================================="
        
        build_exec_binary "${depend_name}" "${depend_version}" "${source_dir}" "${depend_platforms}" "${depend_config_file}"
        return $?
    fi
    # 其他类型（github / docker / frontend）：委托给 build_other_dependency
    build_other_dependency "$package" "$depend_config_file" "$depend_name" "$depend_path" "$depend_version" "$depend_type"
    return $?
}

# 对 docker/github 类型的依赖包记录版本信息到versions.json并导出镜像tar文件；
# 对 exec 类型跳过（编译结果由 build-components.sh 签名打包）。
# 参数: $1 - package name
save_dependency_version() {
    local package="$1"
    local depend_config_file="depends/${package}.json"
    
    # 获取依赖类型
    local depend_type=$(jq -r ".type // empty" "$depend_config_file")
    
    # exec / frontend 类型：无需导出docker镜像
    if [ "$depend_type" = "exec" ] || [ "$depend_type" = "frontend" ]; then
        local depend_name=$(jq -r ".name // empty" "$depend_config_file")
        echo "Skipping version save for ${depend_type}-type package '${depend_name}' (no docker image to export)"
        return 0
    fi

    # 以下仅处理 docker / github 类型
    local depend_name=$(jq -r ".name // empty" "$depend_config_file")
    local depend_version=$(jq -r ".version // empty" "$depend_config_file")
    local depend_repo=$(jq -r ".repo // empty" "$depend_config_file")
    local depend_tag=$(jq -r ".tag // empty" "$depend_config_file")
    
    # tag字段为可选的，默认值为 '{{.version}}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{.version}}"
    fi
    
    # 渲染tag模板
    local rendered_tag=$(render_template "$depend_tag" "$depend_config_file")
    
    # 创建输出目录
    local image_dir="images/${depend_name}"
    mkdir -p "$image_dir"
    
    # docker/github类型：导出镜像tar文件并检测平台架构
    local tar_file=""
    local platforms_json="[]"
    
    local image_full_name="${depend_repo}/${depend_name}:${rendered_tag}"
    
    echo "=============================================="
    echo "Exporting image: $image_full_name"
    echo "=============================================="
    
    # 导出镜像为tar文件
    tar_file="${depend_name}-${rendered_tag}.tar"
    echo "Saving image to ${image_dir}/${tar_file}..."
    docker save -o "${image_dir}/${tar_file}" "$image_full_name"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to export image $image_full_name"
        return 1
    fi
    
    echo "Successfully exported image to ${image_dir}/${tar_file}"
    
    # 检测镜像支持的平台架构
    local arch=$(docker image inspect --format='{{.Architecture}}' "$image_full_name" 2>/dev/null || echo "amd64")
    # 标准化架构名称
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
    esac
    platforms_json="[\"$arch\"]"
    
    # 更新或创建versions.json
    local versions_file="${image_dir}/versions.json"
    local tmp_file=$(mktemp)
    
    if [ -f "$versions_file" ]; then
        # 读取现有versions.json，更新latest和versions数组
        jq --arg ver "$depend_version" \
           --arg tag "$rendered_tag" \
           --arg file "$tar_file" \
           --argjson platforms "$platforms_json" \
           '
           .latest = $ver |
           if (.versions | any(.version == $ver)) then
               .versions = [.versions[] | if .version == $ver then {version: $ver, tag: $tag, file: $file, platforms: $platforms} else . end]
           else
               .versions += [{version: $ver, tag: $tag, file: $file, platforms: $platforms}]
           end
           ' "$versions_file" > "$tmp_file"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to update $versions_file"
            rm -f "$tmp_file"
            return 1
        fi
        mv "$tmp_file" "$versions_file"
    else
        # 创建新的versions.json
        jq -n --arg pkg "$depend_name" \
              --arg ver "$depend_version" \
              --arg tag "$rendered_tag" \
              --arg file "$tar_file" \
              --argjson platforms "$platforms_json" \
              '{
                  packageName: $pkg,
                  latest: $ver,
                  versions: [{version: $ver, tag: $tag, file: $file, platforms: $platforms}]
              }' > "$versions_file"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create $versions_file"
            return 1
        fi
    fi
    
    echo "Version info saved to $versions_file"
    return 0
}

# 根据依赖配置文件中'update'字段的定义，使用本次构建结果更新组件的信息
update_component() {
    local package="$1"
    local depend_config_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$depend_config_file" ]; then
        echo "Error: Image configuration file $depend_config_file does not exist!"
        return 1
    fi
    
    # 检查update字段是否存在
    local has_update=$(jq -r 'has("update")' "$depend_config_file")
    if [ "$has_update" != "true" ]; then
        echo "Skipping component update for ${package} (update field not found)..."
        return
    fi
    
    # 从配置文件中获取update.workdir和update.command
    local workdir=$(jq -r ".update.workdir // empty" "$depend_config_file")
    local command=$(jq -r ".update.command // empty" "$depend_config_file")
    
    # 获取package name用于显示
    local package_name=$(jq -r ".name // empty" "$depend_config_file")
    
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
    local rendered_command=$(render_template "$command" "$depend_config_file" "$workdir")
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
    local depend_config_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$depend_config_file" ]; then
        echo "Error: Image configuration file $depend_config_file does not exist!"
        return 1
    fi
    
    # 从depends目录的对应JSON文件中获取配置
    local depend_name=$(jq -r ".name // empty" "$depend_config_file")
    local depend_version=$(jq -r ".version // empty" "$depend_config_file")
    local depend_repo=$(jq -r ".repo // empty" "$depend_config_file")
    local depend_tag=$(jq -r ".tag // empty" "$depend_config_file")
    
    # tag字段为可选的，默认值为 '{{.version}}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{.version}}"
    fi
    
    # 渲染tag模板
    local rendered_tag=$(render_template "$depend_tag" "$depend_config_file")
    
    if [ -z "$depend_name" ] || [ "$depend_name" = "null" ]; then
        echo "Error: 'name' not found for image '${package}' in ${depend_config_file}!"
        return 1
    fi
    
    local depend_full_name="${depend_repo}/${depend_name}:${rendered_tag}"
    
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

# Function to upload image to environment
upload_image() {
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
    local depend_config_file="depends/${package}.json"
    local depend_name=$(jq -r ".name // empty" "$depend_config_file")
    local depend_version=$(jq -r ".version // empty" "$depend_config_file")
    local depend_repo=$(jq -r ".repo // empty" "$depend_config_file")
    local depend_tag=$(jq -r ".tag // empty" "$depend_config_file")
    
    # tag字段为可选的，默认值为 '{{.version}}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{.version}}"
    fi
    
    # 渲染tag模板
    local rendered_tag=$(render_template "$depend_tag" "$depend_config_file")
    
    local depend_full_name="${depend_repo}/${depend_name}:${rendered_tag}"
    
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

# Function to upload images to multiple environments
upload_images() {
    local package="$1"
    
    # 遍历UPLOAD_TARGETS数组中的每个环境名称
    for env_name in "${UPLOAD_TARGETS[@]}"; do
        upload_image "$package" "$env_name"
    done
}

# Function to process a single package
process_package() {
    local package_name=$1
    local depend_config_file="depends/${package_name}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$depend_config_file" ]; then
        echo "Error: configuration file 'depends/${package_name}.json' does not exist!"
        exit 1
    fi
    
    # 获取依赖类型，用于后续判断是否跳过 docker 相关操作
    local depend_type=$(jq -r ".type // empty" "$depend_config_file")
    # 获取 name 和 version 字段，用于 write_build_json
    local depend_name=$(jq -r ".name // empty" "$depend_config_file")
    local depend_version=$(jq -r ".version // empty" "$depend_config_file")
    
    if [ "$NEED_BUILD" = true ]; then
        echo "Building 'dependency' for ${package_name}..."
        build_dependency "${package_name}"
        if [ $? -ne 0 ]; then
            echo "Error: Build failed for ${package_name}"
            exit 1
        fi
        
        # 写入 build.json 记录构建完成时间戳
        write_build_json "dependency" "${depend_name}" "${depend_version}" "build"
        
        # 构建成功后，保存版本信息（docker/github类型还会导出镜像tar文件；exec类型跳过）
        save_dependency_version "${package_name}"
        if [ $? -ne 0 ]; then
            echo "Error: Version save failed for ${package_name}"
            exit 1
        fi
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
    
    # push 操作仅对 docker/github 类型生效，exec / frontend 类型跳过
    if [ "$NEED_PUSH" = true ]; then
        if [ "$depend_type" = "exec" ] || [ "$depend_type" = "frontend" ]; then
            echo "Skipping push step for ${depend_type}-type package '${package_name}' (no docker image to push)..."
        else
            # 如果 PUSH_TO_DOCKER_HUB 为 true，推送到 docker hub
            if [ "$PUSH_TO_DOCKER_HUB" = true ]; then
                echo "Pushing image to docker hub for ${package_name}..."
                push_image "${package_name}"
                if [ $? -ne 0 ]; then
                    echo "Error: Push failed for ${package_name}"
                    exit 1
                fi
                # 写入 build.json 记录 push 完成时间戳
                write_build_json "dependency" "${depend_name}" "${depend_version}" "push"
            fi
            
            # 如果有指定的上传目标环境，上传到这些环境
            if [ ${#UPLOAD_TARGETS[@]} -gt 0 ]; then
                echo "Uploading image to specified environments: ${package_name}"
                upload_images "${package_name}"
                if [ $? -ne 0 ]; then
                    echo "Error: Upload failed for ${package_name}"
                    exit 1
                fi
                # 写入 build.json 记录 upload 完成时间戳
                write_build_json "dependency" "${depend_name}" "${depend_version}" "upload"
            fi
        fi
    else
        echo "Skipping push step for ${package_name}..."
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

# 检查docker命令是否可用（仅 github/docker 类型需要，exec / frontend 类型不需要）
if ! command -v docker >/dev/null 2>&1; then
    echo "Warning: docker command not found. Only exec-type and frontend-type packages can be built without Docker."
    echo "  For github/docker type packages, please install Docker."
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
    echo "Error: depends directory not found!"
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
