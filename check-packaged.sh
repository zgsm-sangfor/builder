#!/bin/bash
#
# check-packaged.sh - 检测components目录中模块定义JSON文件中的版本是否已经打包输出到packages目录
#
# 功能：
# - 遍历components目录中的JSON配置文件
# - 读取包版本和平台信息
# - 检查packages目录下对应包各平台的版本目录是否存在且包含实际文件
# - 输出尚未打包的模块列表

set -e

# 默认参数值
VERBOSE=false
PACKAGES=""

# 打印帮助信息的函数
print_usage() {
    echo "Usage: check-packaged.sh [-p|--packages PACKAGE1,PACKAGE2,...] [-h|--help] [-v|--verbose]"
    echo "Options:"
    echo "  -p, --packages        Only check specified packages (comma-separated list)"
    echo "  -v, --verbose         Show detailed check information for each platform"
    echo "  -h, --help            Show this help message"
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

# 检查单个包是否已打包
# 参数:
#   $1: json_file - JSON 配置文件路径
# 返回值: 0=已打包, 1=未打包
process_package() {
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
        log "NOT_PACKAGED" "Package '$package_name' version $package_version missing on: ${missing_platforms[*]}"
        return 1
    fi
}

# 主函数
main() {
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
            if ! process_package "$json_file"; then
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
}

# Parse command line options
args=$(getopt -o hp:v --long help,packages:,verbose -n 'check-packaged.sh' -- "$@")
[ $? -ne 0 ] && print_usage && exit 1

eval set -- "$args"

while true; do
    case "$1" in
        -p|--packages) PACKAGES="$2"; shift 2;;
        -v|--verbose) VERBOSE=true; shift;;
        -h|--help) print_usage; exit 0;;
        --) shift; break;;
        *) print_usage; exit 1;;
    esac
done

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

main
