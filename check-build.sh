#!/bin/bash
#
# check-build.sh - 检测组件包或依赖包的版本是否已经构建/打包完成
#
# 功能：
# - 支持两种检测模式，通过 --build-type (-t) 选项切换：
#   1. component（默认）: 检测 components 目录中组件包的版本是否已构建
#   2. dependency: 检测 depends 目录中依赖包的指定版本是否已构建
# - 检测依据: builds/{type}/{packageName}/{version}/build.json 是否存在且 timestamp.build 非空
# - 输出尚未构建的模块列表
#
# 选项说明：
#   -t, --build-type TYPE  检测类型: 'component' 或 'dependency' (默认: component)
#   -p, --packages LIST    仅检测指定包（逗号分隔）
#   -v, --verbose          显示详细检测信息
#   -h, --help             显示帮助信息

set -e

# 默认参数值
VERBOSE=false
PACKAGES=""
BUILD_TYPE="component"
PACKAGES_DIR="components"

print_usage() {
    echo "Usage: check-build.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --build-type TYPE  Check type: 'component' or 'dependency' (default: component)"
    echo "                         component  - Check if component packages are packaged (from components/)"
    echo "                         dependency - Check if dependency packages are built (from depends/)"
    echo "  -p, --packages LIST    Only check specified packages (comma-separated list)"
    echo "  -v, --verbose          Show detailed check information"
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
is_module_enabled() {
    local package_file="$1"
    local is_enabled=$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$package_file" 2>/dev/null)
    if [ "$is_enabled" = "false" ]; then
        return 1
    fi
    return 0
}

# 根据 build.json 检查单个包是否已构建
# 参数:
#   $1: type      - "component" 或 "dependency"
#   $2: package_file - JSON 配置文件路径
#   $3: use_name  - 是否使用 JSON 中的 name 字段作为路径名（dependency=true, component=false）
# 返回值: 0=已构建, 1=未构建
check_package_build() {
    local type="$1"
    local package_file="$2"
    local use_name="${3:-false}"
    local package_name=$(basename "$package_file" .json)

    local version=$(jq -r ".version // empty" "$package_file")
    if [ -z "$version" ] || [ "$version" = "null" ] || [ "$version" = "" ]; then
        log "WARN" "No version found for '$package_name', skipping..."
        return 0
    fi

    # dependency 类型使用 JSON 中的 name 字段，fallback 到文件名
    local path_name="$package_name"
    if [ "$use_name" = "true" ]; then
        local json_name=$(jq -r ".name // empty" "$package_file")
        if [ -n "$json_name" ] && [ "$json_name" != "null" ] && [ "$json_name" != "" ]; then
            path_name="$json_name"
        fi
    fi

    prompt_verbose "Checking: $package_name, version: $version"

    local build_json="builds/${type}/${path_name}/${version}/build.json"
    if [ -f "$build_json" ]; then
        local build_time=$(jq -r '.timestamp.build // empty' "$build_json" 2>/dev/null)
        if [ -n "$build_time" ] && [ "$build_time" != "null" ] && [ "$build_time" != "" ]; then
            prompt_verbose "  OK: build.json found with build timestamp: $build_time"
            log "INFO" "$package_name v$version: built ($build_json)"
            return 0
        fi
    fi
    log "MISSING" "$package_name v$version: build.json not found or build timestamp empty"
    return 1
}

# 主检测函数
# 参数: $1 - type ("component" 或 "dependency")
main_check() {
    local type="$1"
    local label_singular="$type"
    local use_name="false"

    if [ "$type" = "dependency" ]; then
        label_singular="dependency"
        use_name="true"
    fi

    prompt "=============================================="
    prompt "Checking packaged status from ${PACKAGES_DIR}"
    prompt "=============================================="
    prompt ""

    local not_built=()
    local skipped=()
    local target_packages=()

    if [ -n "$PACKAGES" ]; then
        IFS=',' read -ra target_packages <<< "$PACKAGES"
        log "INFO" "Checking only specified packages: ${target_packages[*]}"
    fi

    local total=0
    local checked=0

    for package_file in "${PACKAGES_DIR}"/*.json; do
        [ -f "$package_file" ] || continue
        total=$((total + 1))

        local pkg=$(basename "$package_file" .json)

        if [ ${#target_packages[@]} -gt 0 ]; then
            # 指定了包列表，精确匹配
            local found=false
            for t in "${target_packages[@]}"; do
                if [ "$pkg" = "$t" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                continue
            fi
        else
            # 未指定包列表，跳过禁用的模块
            if ! is_module_enabled "$package_file"; then
                skipped+=("$pkg")
                continue
            fi
        fi

        checked=$((checked + 1))
        if ! check_package_build "$type" "$package_file" "$use_name"; then
            not_built+=("$pkg")
        fi
    done

    prompt "=============================================="
    if [ ${#not_built[@]} -gt 0 ]; then
        prompt ""
        prompt "Not built ${label_singular}s (${#not_built[@]}):"
        for p in "${not_built[@]}"; do
            prompt "  - $p"
        done
    else
        prompt "All checked ${label_singular}s are built."
    fi

    if [ ${#skipped[@]} -gt 0 ]; then
        prompt ""
        prompt "Disabled ${label_singular}s (${#skipped[@]}):"
        for p in "${skipped[@]}"; do
            prompt "  - $p"
        done
    fi

    prompt ""
    prompt "Total ${label_singular}s: $total, Checked: $checked"
    prompt "=============================================="

    # 输出未构建的包名到 stdout（逗号分隔）
    if [ ${#not_built[@]} -gt 0 ]; then
        (IFS=','; echo "${not_built[*]}")
    fi

    return ${#not_built[@]}
}

# ============================================================
#  主入口
# ============================================================

args=$(getopt -o hp:t:v --long help,packages:,build-type:,verbose -n 'check-build.sh' -- "$@")
[ $? -ne 0 ] && print_usage && exit 1

eval set -- "$args"

while true; do
    case "$1" in
        -p|--packages) PACKAGES="$2"; shift 2;;
        -t|--build-type)
            BUILD_TYPE="$2"
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

# 验证目录存在
if [ "$BUILD_TYPE" = "dependency" ]; then
    PACKAGES_DIR="depends"
fi
if [ ! -d "$PACKAGES_DIR" ]; then
    log "ERROR" "$PACKAGES_DIR directory not found!"
    exit 1
fi

if [ -z "$(ls -A ${PACKAGES_DIR}/*.json 2>/dev/null)" ]; then
    log "ERROR" "No JSON files found in $PACKAGES_DIR directory!"
    exit 1
fi

main_check "$BUILD_TYPE"
