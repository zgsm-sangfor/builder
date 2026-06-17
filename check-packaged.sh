#!/bin/bash
#
# check-packaged.sh - 检测组件包或依赖包的版本是否已经构建/打包完成
#
# 功能：
# - 支持两种检测模式，通过 --build-type (-t) 选项切换：
#   1. component（默认）: 检测 components 目录中组件包的版本是否已打包到 packages 目录
#      - 遍历 components 目录中的 JSON 配置文件
#      - 读取包版本和平台信息
#      - 检查 packages 目录下对应包各平台的版本目录是否存在且包含实际文件
#   2. dependency: 检测 depends 目录中依赖包的指定版本是否已构建
#      - 遍历 depends 目录中的 JSON 配置文件
#      - 读取依赖包的目标版本信息
#      - 检查 images/{packageName}/versions.json 中是否记录了该版本
#      - 对于 exec 类型的依赖包，还会检查对应的镜像 tar 文件是否存在
# - 输出尚未构建/打包的模块列表

set -e

# 默认参数值
VERBOSE=false
PACKAGES=""
BUILD_TYPE="component"

# 打印帮助信息的函数
print_usage() {
    echo "Usage: check-packaged.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --build-type TYPE  Check type: 'component' or 'dependency' (default: component)"
    echo "                         component  - Check if component packages are packaged (from components/)"
    echo "                         dependency - Check if dependency packages are built (from depends/)"
    echo "  -p, --packages LIST    Only check specified packages (comma-separated list)"
    echo "  -v, --verbose          Show detailed check information for each platform"
    echo "  -h, --help             Show this help message"
}

log() {
    local level=$1
    local message=$2
    echo -e "[${level}] ${message}" >&2
}

prompt() {
    local message=$1
    echo -e "${message}" >&2
}

prompt_verbose() {
    if [ "$VERBOSE" = true ]; then
        local message=$1
        echo -e "${message}" >&2
    fi
}

# 检查模块是否被启用
# 参数: $1 - JSON文件路径
# 返回值: 0=启用, 1=禁用
is_module_enabled() {
    local json_file="$1"

    # 检查enabled字段，如果不存在则默认为启用(true)
    local is_enabled=$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$json_file" 2>/dev/null)

    # 如果enabled字段的值为false（布尔值或字符串），则禁用
    if [ "$is_enabled" = "false" ]; then
        return 1
    fi

    return 0
}

# ============================================================
#  组件包检测相关函数 (build-type=component)
# ============================================================

# 检查单个组件包是否已打包
# 参数:
#   $1: json_file - JSON 配置文件路径
# 返回值: 0=已打包, 1=未打包
process_component_package() {
    local json_file="$1"
    local package_name=$(basename "$json_file" .json)

    # 从components目录的JSON文件中读取包信息
    local package_version=$(jq -r ".version // empty" "$json_file")
    local package_platforms=$(jq -r ".platforms // empty" "$json_file")

    # 检查version字段是否存在
    if [ -z "$package_version" ] || [ "$package_version" = "null" ] || [ "$package_version" = "" ]; then
        log "WARN" "No version found for package '$package_name', skipping..."
        return 0
    fi

    # 如果没有定义platforms，则使用common
    if [ -z "$package_platforms" ] || [ "$package_platforms" = "null" ] || [ "$package_platforms" = "" ]; then
        package_platforms='[{"os":"common","arch":"common"}]'
    fi

    local platform_count=$(echo "$package_platforms" | jq 'length')
    local all_packaged=true
    local missing_platforms=()

    prompt_verbose "Checking package: $package_name, version: $package_version, platforms: $platform_count"

    # 遍历每个平台检查版本目录
    local i
    for ((i=0; i<platform_count; i++)); do
        local os=$(echo "$package_platforms" | jq -r ".[$i].os")
        local arch=$(echo "$package_platforms" | jq -r ".[$i].arch")
        local version_dir="packages/${package_name}/${os}/${arch}/${package_version}"

        # 检查版本目录是否存在
        if [ ! -d "$version_dir" ]; then
            prompt_verbose "  Missing directory: ${version_dir}"
            all_packaged=false
            missing_platforms+=("${os}/${arch}")
            continue
        fi

        # 检查目录中是否有非package.json的实际文件（参考pack_dir_packages逻辑）
        local has_actual_file=false
        local file
        for file in "${version_dir}"/*; do
            [ -f "${file}" ] || continue
            [ "$(basename "${file}")" = "package.json" ] && continue
            has_actual_file=true
            break
        done

        if [ "$has_actual_file" = false ]; then
            prompt_verbose "  No actual file in: ${version_dir}"
            all_packaged=false
            missing_platforms+=("${os}/${arch}")
            continue
        fi

        prompt_verbose "  OK: ${os}/${arch}/${package_version}"
    done

    if [ "$all_packaged" = true ]; then
        log "INFO" "Package '$package_name' version $package_version is fully packaged"
        return 0
    else
        log "MISSING" "Package '$package_name' version $package_version missing on: ${missing_platforms[*]}"
        return 1
    fi
}

# 组件包检测主函数
main_component() {
    prompt "=============================================="
    prompt "Checking packaged status from components"
    prompt "=============================================="
    prompt ""

    local not_packaged_packages=()
    local skip_packages=()
    local target_packages=()

    if [ -n "$PACKAGES" ]; then
        # 如果指定了packages选项，则将逗号分隔的字符串转换为数组
        IFS=',' read -ra target_packages <<< "$PACKAGES"
        log "INFO" "Checking only specified packages: ${target_packages[*]}"
    fi

    local package_count=0
    local checked_count=0

    for json_file in "components"/*.json; do
        [ -f "$json_file" ] || continue

        package_count=$((package_count + 1))

        local package_name=$(basename "$json_file" .json)

        # 如果指定了packages选项，检查当前包是否在目标列表中
        local should_process=true
        if [ ${#target_packages[@]} -gt 0 ]; then
            should_process=false
            for target in "${target_packages[@]}"; do
                if [ "$package_name" = "$target" ]; then
                    should_process=true
                    break
                fi
            done
        else
            # 检查模块是否启用，如果禁用则跳过
            if ! is_module_enabled "$json_file"; then
                skip_packages+=("$package_name")
                continue
            fi
        fi

        if [ "$should_process" = true ]; then
            checked_count=$((checked_count + 1))
            if ! process_component_package "$json_file"; then
                not_packaged_packages+=("$package_name")
            fi
        fi
    done

    prompt "=============================================="
    if [ ${#not_packaged_packages[@]} -gt 0 ]; then
        prompt ""
        prompt "Not packaged packages (${#not_packaged_packages[@]}):"
        for pkg in "${not_packaged_packages[@]}"; do
            prompt "  - $pkg"
        done
    else
        prompt "All checked packages are fully packaged."
    fi

    if [ ${#skip_packages[@]} -gt 0 ]; then
        prompt ""
        prompt "Disabled packages (${#skip_packages[@]}):"
        for pkg in "${skip_packages[@]}"; do
            prompt "  - $pkg"
        done
    fi

    prompt ""
    prompt "Total packages: $package_count, Checked packages: $checked_count"
    prompt "=============================================="

    # 输出所有未打包的包名到标准输出（以逗号分隔）
    if [ ${#not_packaged_packages[@]} -gt 0 ]; then
        (IFS=','; echo "${not_packaged_packages[*]}")
    fi

    return ${#not_packaged_packages[@]}
}

# ============================================================
#  依赖包检测相关函数 (build-type=dependency)
# ============================================================

# 检查单个依赖包是否已构建
# 参数:
#   $1: json_file - depends 目录中的 JSON 配置文件路径
# 返回值: 0=已构建, 1=未构建
process_dependency_package() {
    local json_file="$1"
    local package_name=$(basename "$json_file" .json)

    # 从depends目录的JSON文件中读取依赖信息
    local depend_name=$(jq -r ".name // empty" "$json_file")
    local depend_version=$(jq -r ".version // empty" "$json_file")
    local depend_type=$(jq -r ".type // empty" "$json_file")

    # 使用name字段作为镜像目录名（如果存在），否则使用文件名
    if [ -z "$depend_name" ] || [ "$depend_name" = "null" ] || [ "$depend_name" = "" ]; then
        depend_name="$package_name"
    fi

    # 检查version字段是否存在
    if [ -z "$depend_version" ] || [ "$depend_version" = "null" ] || [ "$depend_version" = "" ]; then
        log "WARN" "No version found for dependency '$package_name', skipping..."
        return 0
    fi

    local versions_file="images/${depend_name}/versions.json"

    prompt_verbose "Checking dependency: $package_name ($depend_name), version: $depend_version, type: ${depend_type:-unknown}"

    # 检查versions.json文件是否存在
    if [ ! -f "$versions_file" ]; then
        log "MISSING" "Dependency '$package_name' version $depend_version: versions.json not found at $versions_file"
        return 1
    fi

    # 检查versions.json中是否存在目标版本
    local version_found=$(jq -r --arg ver "$depend_version" \
        '.versions | map(select(.version == $ver)) | length' "$versions_file" 2>/dev/null)

    if [ -z "$version_found" ] || [ "$version_found" = "null" ] || [ "$version_found" = "0" ]; then
        log "MISSING" "Dependency '$package_name' version $depend_version not found in versions.json"
        return 1
    fi

    # 对于exec类型的依赖包，进一步检查镜像tar文件是否存在
    if [ "$depend_type" = "exec" ]; then
        local tar_file=$(jq -r --arg ver "$depend_version" \
            '.versions | map(select(.version == $ver)) | .[0].file // empty' "$versions_file" 2>/dev/null)

        if [ -z "$tar_file" ] || [ "$tar_file" = "null" ] || [ "$tar_file" = "" ]; then
            log "MISSING" "Dependency '$package_name' version $depend_version: tar file not recorded in versions.json"
            return 1
        fi

        local tar_path="images/${depend_name}/${tar_file}"
        if [ ! -f "$tar_path" ]; then
            log "MISSING" "Dependency '$package_name' version $depend_version: tar file not found at $tar_path"
            return 1
        fi

        prompt_verbose "  OK: exec image file exists: $tar_path"
    fi

    # 检查latest字段是否指向目标版本
    local latest_version=$(jq -r '.latest // empty' "$versions_file" 2>/dev/null)
    if [ -n "$latest_version" ] && [ "$latest_version" != "$depend_version" ]; then
        prompt_verbose "  NOTE: latest is '$latest_version', target version is '$depend_version'"
    fi

    log "INFO" "Dependency '$package_name' version $depend_version is built"
    return 0
}

# 依赖包检测主函数
main_dependency() {
    prompt "=============================================="
    prompt "Checking build status from dependencies"
    prompt "=============================================="
    prompt ""

    local not_built_packages=()
    local skip_packages=()
    local target_packages=()

    if [ -n "$PACKAGES" ]; then
        # 如果指定了packages选项，则将逗号分隔的字符串转换为数组
        IFS=',' read -ra target_packages <<< "$PACKAGES"
        log "INFO" "Checking only specified dependencies: ${target_packages[*]}"
    fi

    local package_count=0
    local checked_count=0

    for json_file in "depends"/*.json; do
        [ -f "$json_file" ] || continue

        package_count=$((package_count + 1))

        local package_name=$(basename "$json_file" .json)

        # 如果指定了packages选项，检查当前包是否在目标列表中
        local should_process=true
        if [ ${#target_packages[@]} -gt 0 ]; then
            should_process=false
            for target in "${target_packages[@]}"; do
                if [ "$package_name" = "$target" ]; then
                    should_process=true
                    break
                fi
            done
        else
            # 检查模块是否启用，如果禁用则跳过
            if ! is_module_enabled "$json_file"; then
                skip_packages+=("$package_name")
                continue
            fi
        fi

        if [ "$should_process" = true ]; then
            checked_count=$((checked_count + 1))
            if ! process_dependency_package "$json_file"; then
                not_built_packages+=("$package_name")
            fi
        fi
    done

    prompt "=============================================="
    if [ ${#not_built_packages[@]} -gt 0 ]; then
        prompt ""
        prompt "Not built dependencies (${#not_built_packages[@]}):"
        for pkg in "${not_built_packages[@]}"; do
            prompt "  - $pkg"
        done
    else
        prompt "All checked dependencies are built."
    fi

    if [ ${#skip_packages[@]} -gt 0 ]; then
        prompt ""
        prompt "Disabled dependencies (${#skip_packages[@]}):"
        for pkg in "${skip_packages[@]}"; do
            prompt "  - $pkg"
        done
    fi

    prompt ""
    prompt "Total dependencies: $package_count, Checked dependencies: $checked_count"
    prompt "=============================================="

    # 输出所有未构建的包名到标准输出（以逗号分隔）
    if [ ${#not_built_packages[@]} -gt 0 ]; then
        (IFS=','; echo "${not_built_packages[*]}")
    fi

    return ${#not_built_packages[@]}
}

# ============================================================
#  主入口
# ============================================================

# Parse command line options
args=$(getopt -o hp:t:v --long help,packages:,build-type:,verbose -n 'check-packaged.sh' -- "$@")
[ $? -ne 0 ] && print_usage && exit 1

eval set -- "$args"

while true; do
    case "$1" in
        -p|--packages) PACKAGES="$2"; shift 2;;
        -t|--build-type)
            BUILD_TYPE="$2"
            # 验证 build-type 值
            if [ "$BUILD_TYPE" != "component" ] && [ "$BUILD_TYPE" != "dependency" ]; then
                log "ERROR" "Invalid build-type '$BUILD_TYPE'. Must be 'component' or 'dependency'."
                print_usage
                exit 1
            fi
            shift 2
            ;;
        -v|--verbose) VERBOSE=true; shift;;
        -h|--help) print_usage; exit 0;;
        --) shift; break;;
        *) print_usage; exit 1;;
    esac
done

if [ "$BUILD_TYPE" = "component" ]; then
    # 检查components目录是否存在
    if [ ! -d "components" ]; then
        log "ERROR" "components directory not found!"
        exit 1
    fi

    # 检查components目录中是否有JSON文件
    if [ -z "$(ls -A components/*.json 2>/dev/null)" ]; then
        log "ERROR" "No JSON files found in components directory!"
        exit 1
    fi

    main_component
else
    # 检查depends目录是否存在
    if [ ! -d "depends" ]; then
        log "ERROR" "depends directory not found!"
        exit 1
    fi

    # 检查depends目录中是否有JSON文件
    if [ -z "$(ls -A depends/*.json 2>/dev/null)" ]; then
        log "ERROR" "No JSON files found in depends directory!"
        exit 1
    fi

    main_dependency
fi
