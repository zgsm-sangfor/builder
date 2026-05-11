#!/bin/bash

#
# 功能：
#   build-depends.sh为指定的模块(package)构建依赖内容(一般是镜像)，并推送到指定环境。
#
#   待构建的内容，由depends/{package}.json进行定义，该文件内容如下所示：
#
#     {
#        "name": "costrict-admin-backend",
#        "repo": "zgsm",
#        "version": "1.0.43",
#        "type": "exec",
#        "path": "../costrict-admin/backend",
#        "command": "docker build --build-arg VERSION={{ .version }} . -t {{ .repo }}/{{ .name }}:{{ .tag }}",
#        "tag": "{{ .version }}",
#        "component": {
#          "workdir": "./configures/common/costrict-admin-backend",
#          "command": "echo IMAGE_COSTRICT_ADMIN={{.repo}}/costrict-admin:v{{.version}} > ./image.env"
#        },
#        "enabled": false,
#        "description": "The back-end docker-service of costrict"
#      }
#
#   字段说明：
#   - name: 模块名
#   - repo: 镜像在docker hub中的仓库名（必填）
#   - version: 镜像的版本
#   - path: 构建镜像时的工作路径
#   - command: 构建镜像的命令
#   - tag: 镜像的标签（可选，默认值为'{{ .version }}'）
#   - description: 镜像描述
#
#   command和tag中定义的命令行，可以包含可变参数，可变参数采用go的text/template语法，变量'.'就是{package}.json根对象。
#   替换变量时，只使用depends/{package}.json中除command,tag之外的字段。
#
#   上述命令定义， 会被替换为: docker build --build-arg VERSION=1.0.43 . -t zgsm/costrict-admin-backend:1.0.43
#
#   推送目标环境的相关参数，由.env中的环境变量(DH_ENV_NAMES, DH_ENV_URLS, DH_ENV_USERS, DH_ENV_PASSWORDS)定义。
#
# 选项说明：
#   --push [<ENV>]      推送镜像。如果参数为空或包含"def"，则推送到docker hub；
#                       否则上传到指定环境（沿用upload选项逻辑）。每种环境由四个参数指定：
#                       名字(name), URL(url), 用户名(user)，密码(password)
#                       上传方式是，使用docker login登录（使用环境相关参数），然后docker push推送
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
# 参数: $1 - template string, $2 - json file path
render_template() {
    local template="$1"
    local json_file="$2"
    
    # 使用jq将JSON转换为可以被go template使用的格式
    # 这里简化处理：直接替换{{ .field }}为对应的JSON值
    local result="$template"
    
    # 获取JSON中的所有字段（排除command和tag）
    local name=$(jq -r '.name // empty' "$json_file")
    local version=$(jq -r '.version // empty' "$json_file")
    local path=$(jq -r '.path // empty' "$json_file")
    local description=$(jq -r '.description // empty' "$json_file")
    local repo=$(jq -r '.repo // empty' "$json_file")
    local workdir=$(jq -r '.component.workdir // empty' "$json_file")
   
   
    # 替换 {{.name}} 格式（不带空格）
    result="${result//\{\{.name\}\}/$name}"
    result="${result//\{\{.version\}\}/$version}"
    result="${result//\{\{.path\}\}/$path}"
    result="${result//\{\{.description\}\}/$description}"
    result="${result//\{\{.repo\}\}/$repo}"
    result="${result//\{\{.workdir\}\}/$workdir}"
    
    echo "$result"
}

# Function to build an image
build_dependency() {
    local package="$1"
    local depend_config_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$depend_config_file" ]; then
        echo "Error: Image configuration file $depend_config_file does not exist!"
        return 1
    fi
    
    # 从depends目录的对应JSON文件中获取配置
    local depend_name=$(jq -r ".name // empty" "$depend_config_file")
    local depend_path=$(jq -r ".path // empty" "$depend_config_file")
    local depend_command=$(jq -r ".command // empty" "$depend_config_file")
    local depend_version=$(jq -r ".version // empty" "$depend_config_file")
    
    if [ -z "$depend_name" ] || [ "$depend_name" = "null" ] || [ "$depend_name" = "" ]; then
        echo "Error: 'name' not found for image '${package}' in ${depend_config_file}!"
        return 1
    fi
    
    if [ -z "$depend_path" ] || [ "$depend_path" = "null" ] || [ "$depend_path" = "" ]; then
        echo "Skipping build step for ${package}..."
        return
    fi
    
    if [ -z "$depend_command" ] || [ "$depend_command" = "null" ] || [ "$depend_command" = "" ]; then
        echo "Error: 'command' not found for image '${package}' in ${depend_config_file}!"
        return 1
    fi
    
    echo "=============================================="
    echo "Building image: $depend_name, version: $depend_version"
    echo "Path: $depend_path"
    echo "=============================================="
    
    # 渲染命令模板
    local rendered_command=$(render_template "$depend_command" "$depend_config_file")
    echo "Executing: $rendered_command"
    
    # 执行构建命令
    (cd "$depend_path" && bash -c "$rendered_command")
    if [ $? -ne 0 ]; then
        echo "Error: Build failed for image $depend_name"
        return 1
    fi
    
    echo "Successfully built image: $depend_name"
    return 0
}

# 根据依赖配置文件中'component'字段的定义，使用本次构建结果更新组件的信息
update_component() {
    local package="$1"
    local depend_config_file="depends/${package}.json"
    
    # 检查配置文件是否存在
    if [ ! -f "$depend_config_file" ]; then
        echo "Error: Image configuration file $depend_config_file does not exist!"
        return 1
    fi
    
    # 检查component字段是否存在
    local has_component=$(jq -r 'has("component")' "$depend_config_file")
    if [ "$has_component" != "true" ]; then
        echo "Skipping component update for ${package} (component field not found)..."
        return
    fi
    
    # 从配置文件中获取component.workdir和component.command
    local workdir=$(jq -r ".component.workdir // empty" "$depend_config_file")
    local command=$(jq -r ".component.command // empty" "$depend_config_file")
    
    # 获取package name用于显示
    local package_name=$(jq -r ".name // empty" "$depend_config_file")
    
    # 检查workdir是否为空
    if [ -z "$workdir" ] || [ "$workdir" = "null" ] || [ "$workdir" = "" ]; then
        echo "Skipping component update for ${package} (component.workdir not found)..."
        return
    fi
    
    # 检查command是否为空
    if [ -z "$command" ] || [ "$command" = "null" ] || [ "$command" = "" ]; then
        echo "Skipping component update for ${package} (component.command not found)..."
        return
    fi
    
    echo "=============================================="
    echo "Updating component: $package_name"
    echo "Workdir: $workdir"
    echo "=============================================="
    
    # 渲染命令模板
    local rendered_command=$(render_template "$command" "$depend_config_file")
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
    
    # tag字段为可选的，默认值为 '{{ .version }}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{ .version }}"
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
    
    # tag字段为可选的，默认值为 '{{ .version }}'
    if [ -z "$depend_tag" ] || [ "$depend_tag" = "null" ] || [ "$depend_tag" = "" ]; then
        depend_tag="{{ .version }}"
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

# Function to upload depends to multiple environments
upload_depends() {
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
        echo "Error: Image configuration file 'depends/${package_name}.json' does not exist!"
        exit 1
    fi
    
    if [ "$NEED_BUILD" = true ]; then
        echo "Building 'dependency' for ${package_name}..."
        build_dependency "${package_name}"
        if [ $? -ne 0 ]; then
            echo "Error: Build failed for ${package_name}"
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
        fi
    else
        echo "Skipping update step for ${package_name}..."
    fi
    
    if [ "$NEED_PUSH" = true ]; then
        # 如果 PUSH_TO_DOCKER_HUB 为 true，推送到 docker hub
        if [ "$PUSH_TO_DOCKER_HUB" = true ]; then
            echo "Pushing image to docker hub for ${package_name}..."
            push_image "${package_name}"
            if [ $? -ne 0 ]; then
                echo "Error: Push failed for ${package_name}"
                exit 1
            fi
        fi
        
        # 如果有指定的上传目标环境，上传到这些环境
        if [ ${#UPLOAD_TARGETS[@]} -gt 0 ]; then
            echo "Uploading image to specified environments: ${package_name}"
            upload_depends "${package_name}"
            if [ $? -ne 0 ]; then
                echo "Error: Upload failed for ${package_name}"
                exit 1
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

# 检查docker命令是否可用
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker command not found! Please install Docker."
    exit 1
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
