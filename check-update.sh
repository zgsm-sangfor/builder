#!/bin/bash

# check-update.sh - 检测components或depends目录中包的版本和内容变化，更新包版本
#
# 功能：
# - 遍历components或depends目录中的JSON配置文件（由-t/--build-type选项指定）
# - 计算包path所指目录的CHECKSUM和文件数
# - 比较当前版本和checksum与latest.json中的记录
# - 根据变化情况输出提示或更新latest.json
# --update: 当checksum变化时自动更新版本号(递增包的patch版本号)

set -e

# 默认参数值
UPDATE_VERSION=false
VERBOSE=false
PACKAGES=""
BUILD_TYPE="component"
USE_LOCAL_MODE=false

# 配置文件路径（将在参数解析后根据BUILD_TYPE设置）
JSONS_DIR=""
LATEST_FIELD_NAME=""
LATEST_JSON="latest.json"

# 打印帮助信息的函数
print_usage() {
    echo "Usage: check-update.sh [-u|--update] [-p|--packages PACKAGE1,PACKAGE2,...] [-t|--build-type TYPE] [--local] [-h|--help] [-v|--verbose]"
    echo "Options:"
    echo "  -t, --build-type      Build type: dependency or component (default: component)"
    echo "  -p, --packages        Only check specified packages (comma-separated list)"
    echo "  -u, --update          Update package version when checksum changes"
    echo "  --local               Use local mode: check by local directory checksum (default: check by GitHub tag for docker type)"
    echo "  -v, --verbose         Show checksum calculation details for each file"
    echo "  -h, --help            Show this help message"
}

log() {
    local level=$1
    local message=$2
    echo -e "[${level}] ${message}" >&2
}

# 检查模块是否被启用
# 参数: $1 - JSON文件路径
# 返回值: 0=启用, 1=禁用
is_module_enabled() {
    local package_file="$1"
    
    # 检查enabled字段，如果不存在则默认为启用(true)
    # 使用 jq 的布尔逻辑：当 enabled 不存在或不为 false/字符串"false" 时返回真
    local is_enabled=$(jq -r 'if .enabled == false or .enabled == "false" then "false" else "true" end' "$package_file" 2>/dev/null)
    
    # 如果enabled字段的值为false（布尔值或字符串），则禁用
    if [ "$is_enabled" = "false" ]; then
        return 1
    fi
    
    return 0
}

prompt_verbose() {
    if [ "$VERBOSE" = true ]; then
        local message=$1
        echo -e "${message}" >&2
    fi
}

prompt() {
    local message=$1
    echo -e "${message}" >&2
}
# 从文件列表计算CHECKSUM（通用函数）
# 输入：通过参数传递的文件列表（可变参数）
# 输出格式：第一行checksum，第二行文件数
calculate_checksum_from_file_list() {
    # 如果没有传参，返回空
    if [ $# -eq 0 ]; then
        prompt_verbose "no any files"
        echo ""
        echo "0"
        return
    fi
    
    # 统计文件数
    local file_count=$#
    # 计算checksum
    local sha256_output=$(printf "%s\n" "$@" | xargs sha256sum 2>/dev/null | sort)
    local checksum=$(echo "$sha256_output" | sha256sum | awk '{print $1}')
    
    # 如果开启了verbose模式，输出每个文件的checksum
    prompt_verbose "$sha256_output"
    
    # 输出两行：checksum, file_count
    echo "$checksum"
    echo "$file_count"
}

# 计算目录的CHECKSUM（用于exec、zip类型）
# 输出格式：第一行checksum，第二行文件数
calculate_directory_checksum() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        prompt_verbose "$dir is not a directory"
        echo ""
        echo "0"
        return
    fi
    
    # 使用find获取文件列表并缓存在数组中
    local file_list=()
    while IFS= read -r -d '' file; do
        file_list+=("$file")
    done < <(find "$dir" -type f -print0 2>/dev/null)
    
    # 调用通用函数计算checksum
    calculate_checksum_from_file_list "${file_list[@]}"
}

# 计算目录中Go相关文件的CHECKSUM（用于exec类型）
# 输出格式：第一行checksum，第二行文件数
calculate_go_directory_checksum() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        prompt_verbose "$dir is not a directory"
        echo ""
        echo "0"
        return
    fi
    
    # 使用find获取Go文件列表并缓存在数组中
    local file_list=()
    while IFS= read -r -d '' file; do
        file_list+=("$file")
    done < <(find "$dir" -type f \( -name "*.go" -o -name "*.mod" \) ! -path "*/.git/*" -print0 2>/dev/null)
    
    # 调用通用函数计算checksum
    calculate_checksum_from_file_list "${file_list[@]}"
}

# 计算前端项目目录的CHECKSUM
# 输出格式：第一行checksum，第二行文件数
# 参数：
#   $1: dir - 要扫描的目录
#   $2: package_file - JSON配置文件路径（用于读取excludes字段）
calculate_frontend_checksum() {
    local dir="$1"
    local package_file="$2"
    
    if [ ! -d "$dir" ]; then
        prompt_verbose "$dir is not a directory"
        echo ""
        echo "0"
        return
    fi
    
    # 默认排除的目录
    local exclude_patterns=("*/.git/*" "*/dist/*" "*/node_modules/*")
    # 构建find命令的排除表达式
    local find_exclude_args=("-path" "*/.git/*" "-o" "-path" "*/dist/*" "-o" "-path" "*/node_modules/*")
    
    # 从JSON文件中读取自定义excludes，并检查是否重复
    local exclude_count=$(jq -r '.excludes | length // 0' "$package_file" 2>/dev/null)
    for ((i=0; i<exclude_count; i++)); do
        local exclude=$(jq -r ".excludes[$i] // empty" "$package_file" 2>/dev/null)
        if [ -n "$exclude" ] && [ "$exclude" != "null" ]; then
            # 检查是否已经存在
            local duplicate=false
            for existing in "${exclude_patterns[@]}"; do
                if [ "$existing" = "$exclude" ]; then
                    duplicate=true
                    break
                fi
            done
            # 如果不存在重复，则添加
            if [ "$duplicate" = false ]; then
                exclude_patterns+=("$exclude")
                find_exclude_args+=("-o")
                find_exclude_args+=("-path")
                find_exclude_args+=("$exclude")
            fi
        fi
    done
    
    # 构建find命令的排除参数
    local find_exclude="! \\( ${find_exclude_args[*]} \\)"
    local find_include="\\( -name \"*.js\" -o -name \"*.vue\" -o -name \"*.html\" -o -name \"*.ts\" -o -name \"*.json\" \\)"
    
    # 使用find获取前端文件列表并缓存在数组中
    local file_list=()
    local find_cmd="find \"$dir\" -type f $find_include $find_exclude -print0"
    
    while IFS= read -r -d '' file; do
        file_list+=("$file")
    done < <(eval "$find_cmd" 2>/dev/null)
    
    # 调用通用函数计算checksum
    prompt_verbose "${find_cmd}"
    calculate_checksum_from_file_list "${file_list[@]}"
}

# 计算conf类型包的CHECKSUM（跨所有平台）
# 输出格式：第一行checksum，第二行文件数
calculate_conf_package_checksum() {
    local path="$1"
    local target="$2"
    
    local file_list=()
    
    # 定义平台列表
    local platforms=("darwin/amd64" "darwin/arm64" "linux/amd64" "linux/arm64" "windows/amd64" "windows/arm64" "common/common")
    
    # 收集所有平台的文件
    for platform in "${platforms[@]}"; do
        local file_path="$path/$platform/$target"
        if [ -f "$file_path" ]; then
            file_list+=("$file_path")
        fi
    done
    
    # 添加 common 目录的文件（如果存在）
    local common_file="$path/common/$target"
    if [ -f "$common_file" ]; then
        file_list+=("$common_file")
    fi

    # 调用通用函数计算checksum
    calculate_checksum_from_file_list "${file_list[@]}"
}

# 计算zip类型包的CHECKSUM（跨所有平台）
# 输出格式：第一行checksum，第二行文件数
calculate_zip_package_checksum() {
    local path="$1"
    local package_name="$2"
    
    local file_list=()
    
    # 定义平台列表
    local platforms=("darwin/amd64" "darwin/arm64" "linux/amd64" "linux/arm64" "windows/amd64" "windows/arm64" "common/common")
    
    # 收集所有平台的文件
    for platform in "${platforms[@]}"; do
        local dir_path="$path/$platform/$package_name"
        if [ -d "$dir_path" ]; then
            while IFS= read -r -d '' file; do
                file_list+=("$file")
            done < <(find "$dir_path" -type f -print0 2>/dev/null)
        fi
    done
    
    # 添加 common 目录中的包目录（如果存在）
    local common_dir="$path/common/$package_name"
    if [ -d "$common_dir" ]; then
        while IFS= read -r -d '' file; do
            file_list+=("$file")
        done < <(find "$common_dir" -type f -print0 2>/dev/null)
    fi
    
    # 调用通用函数计算checksum
    calculate_checksum_from_file_list "${file_list[@]}"
}

# 从github获取远程仓库tag中的版本信息
# 从GitHub仓库获取最新的semver版本tag
# 参数: $1 - JSON配置文件路径, $2 - 包名
# 输出格式：第一行最新版本号（去掉v前缀），第二行checksum（最新tag）
fetch_github_latest() {
    local package_file="$1"
    local package_name="$2"
    
    local package_remote=$(jq -r ".remote // empty" "$package_file")
    local package_path=$(jq -r ".path // empty" "$package_file")
    
    # 检查remote字段
    if [ -z "$package_remote" ] || [ "$package_remote" = "null" ]; then
        log "ERROR" "No remote URL found for github package '$package_name'"
        echo ""
        echo ""
        return 1
    fi
    
    # 检查path字段
    if [ -z "$package_path" ] || [ "$package_path" = "null" ]; then
        log "ERROR" "No local path found for github package '$package_name'"
        echo ""
        echo ""
        return 1
    fi
    
    # 如果本地仓库不存在，从remote clone
    if [ ! -d "$package_path/.git" ]; then
        # 如果目录存在但不是git仓库，先删除
        if [ -d "$package_path" ]; then
            log "WARN" "Path '$package_path' exists but is not a git repository, removing..."
            rm -rf "$package_path"
        fi
        # 确保父目录存在
        mkdir -p "$(dirname "$package_path")"
        log "INFO" "Cloning repository from $package_remote to $package_path..."
        git clone "$package_remote" "$package_path"
    fi
    
    # 更新tag信息
    (cd "$package_path" && git fetch --tags --force origin 2>/dev/null) || true
    
    # 获取最新semver tag（参考get-github-latest.sh逻辑）
    local latest_tag=$(cd "$package_path" && git tag -l | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | while read -r tag; do
        local ver=$(echo "$tag" | sed 's/^v//')
        printf '%s %s\n' "$ver" "$tag"
    done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | awk '{print $2}')
    
    if [ -z "$latest_tag" ]; then
        log "ERROR" "No valid semver tag found in repository for package '$package_name'"
        echo ""
        echo ""
        return 1
    fi
    
    # 获取最新版本号（去掉v前缀）
    local latest_version=$(echo "$latest_tag" | sed 's/^v//')
    
    echo "$latest_version"
    echo "$latest_tag"
}

# 计算多目录组合的CHECKSUM
# 参数：
#   $1: type - 包类型（exec 或 frontend）
#   $2: path - 主目录路径（git仓库路径，sources不存在时作为checksum目标）
#   $3: package_file - JSON配置文件路径
# 输出格式：第一行checksum，第二行文件数
calculate_multi_directory() {
    local type="$1"
    local path="$2"
    local package_file="$3"

    # 确定需要计算checksum的目录列表：
    # - sources 字段存在且非空时，使用 sources 数组中的所有路径
    # - sources 字段不存在或为空时，使用 path 字段的值
    local dirs_to_check=()
    local sources_count=$(jq -r '.sources | length // 0' "$package_file" 2>/dev/null)

    if [ "$sources_count" -gt 0 ]; then
        for ((i=0; i<sources_count; i++)); do
            local source_dir=$(jq -r ".sources[$i] // empty" "$package_file")
            if [ -n "$source_dir" ] && [ "$source_dir" != "null" ]; then
                dirs_to_check+=("$source_dir")
            fi
        done
    else
        dirs_to_check+=("$path")
    fi

    # 检查主目录（git仓库路径）是否存在，如果不存在则从remote克隆
    # 无论sources是否存在，都需要确保path仓库已克隆（sources通常是path的子目录）
    if [ ! -d "$path" ]; then
        local remote=$(jq -r ".remote // empty" "$package_file" 2>/dev/null)
        if [ -z "$remote" ] || [ "$remote" = "null" ] || [ "$remote" = "" ]; then
            log "ERROR" "Path '$path' does not exist and no remote URL configured in $(basename "$package_file")"
            return 1
        fi
        log "INFO" "Path '$path' does not exist, cloning from $remote ..."
        mkdir -p "$(dirname "$path")"
        git clone "$remote" "$path"
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to clone repository from $remote to $path"
            return 1
        fi
    fi

    # 对目标目录列表逐个计算checksum并合并
    local combined_checksum=""
    local combined_file_count=0
    local first=true

    for dir in "${dirs_to_check[@]}"; do
        prompt_verbose "Processing checksum directory: $dir"

        local result=""
        if [ "$type" = "exec" ]; then
            result=$(calculate_go_directory_checksum "$dir")
        elif [ "$type" = "docker" ]; then
            result=$(calculate_directory_checksum "$dir")
        else
            result=$(calculate_frontend_checksum "$dir" "$package_file")
        fi

        local dir_checksum=$(echo "$result" | head -n1)
        local dir_count=$(echo "$result" | tail -n1)

        if [ -n "$dir_checksum" ]; then
            if [ "$first" = true ]; then
                combined_checksum="$dir_checksum"
                first=false
            else
                combined_checksum=$(echo "${combined_checksum}${dir_checksum}" | sha256sum | awk '{print $1}')
            fi
            combined_file_count=$((combined_file_count + dir_count))
        fi
    done

    echo "$combined_checksum"
    echo "$combined_file_count"
}

# 递增包的patch版本号
# 第一个参数为需要修改的文件路径
increment_patch_version() {
    local package_file="$1"
    local current_version="$2"

    # 自动递增 patch 版本号
    local MAJOR=$(echo "$current_version" | cut -d'.' -f1)
    local MINOR=$(echo "$current_version" | cut -d'.' -f2)
    local PATCH=$(echo "$current_version" | cut -d'.' -f3)
    local NEW_PATCH=$((PATCH + 1))
    local NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

    # 使用 jq 更新指定JSON文件的版本号
    jq "(.version) |= \"$NEW_VERSION\"" "$package_file" > "$package_file.tmp"
    mv "$package_file.tmp" "$package_file"
    
    echo "$NEW_VERSION"
}

# 检查github类型包：从远程仓库获取最新tag来确定版本
# 参数:
#   $1: package_file - JSON 配置文件路径
#   $2: package_name - 包名
#   $3: package_version - 当前版本号
# 返回值: 0=已修改, 1=未修改
check_github_latest() {
    local package_file="$1"
    local package_name="$2"
    local package_version="$3"
    
    local result=$(fetch_github_latest "$package_file" "$package_name")
    local latest_version=$(echo "$result" | head -n1)
    local new_checksum=$(echo "$result" | tail -n1)
    
    # 如果与JSON中的版本不一致，更新JSON中的版本号
    if [ -n "$latest_version" ] && [ "$latest_version" != "$package_version" ]; then
        log "MODIFIED" "GitHub tag version changed for '$package_name': $package_version -> $latest_version"
        if [ "$UPDATE_VERSION" = true ]; then
            jq "(.version) |= \"$latest_version\"" "$package_file" > "$package_file.tmp"
            mv "$package_file.tmp" "$package_file"
            # 更新latest.json
            jq ".${LATEST_FIELD_NAME}[\"$package_name\"] = {\"version\": \"$latest_version\", \"checksum\": \"$new_checksum\", \"file_count\": 0}" "$LATEST_JSON" > "$LATEST_JSON.tmp"
            mv "$LATEST_JSON.tmp" "$LATEST_JSON"
        fi
        return 0
    fi
    return 1
}

# 检查binary类型包的版本是否发生变化：version字段与depends/${componentName}.json中的version保持一致
# 参数:
#   $1: package_file - JSON 配置文件路径
#   $2: package_name - 包名
#   $3: package_version - 当前版本号
# 返回值: 0=已修改, 1=未修改
check_binary_modified() {
    local package_file="$1"
    local package_name="$2"
    local package_version="$3"
    
    local depends_file="depends/${package_name}.json"
    if [ ! -f "$depends_file" ]; then
        log "ERROR" "Depends file '$depends_file' not found for binary package '$package_name'"
        return 1
    fi
    local depends_version=$(jq -r ".version // empty" "$depends_file")
    if [ -z "$depends_version" ] || [ "$depends_version" = "null" ]; then
        log "ERROR" "No version found in depends file '$depends_file' for binary package '$package_name'"
        return 1
    fi

    # 如果版本不一致，同步为depends中的版本
    if [ "$package_version" != "$depends_version" ]; then
        log "MODIFIED" "Binary package '$package_name' version synced from depends: $package_version -> $depends_version"
        if [ "$UPDATE_VERSION" = true ]; then
            jq "(.version) |= \"$depends_version\"" "$package_file" > "$package_file.tmp"
            mv "$package_file.tmp" "$package_file"

            # 更新latest.json
            jq ".${LATEST_FIELD_NAME}[\"$package_name\"] = {\"version\": \"$depends_version\", \"checksum\": \"\", \"file_count\": 0}" "$LATEST_JSON" > "$LATEST_JSON.tmp"
            mv "$LATEST_JSON.tmp" "$LATEST_JSON"
        fi
        return 0
    fi
    return 1
}

# 处理单个包
# 参数:
#   $1: package_file - JSON 配置文件路径
# 返回值: 0=已修改, 1=未修改
check_package_dirty() {
    local package_file="$1"
    local modified=false
    
    local package_name=$(basename "$package_file" .json)
    
    # 从JSON文件中读取包信息
    local package_version=$(jq -r ".version // empty" "$package_file")
    local package_path=$(jq -r ".path // empty" "$package_file")
    local package_type=$(jq -r ".type // empty" "$package_file")
    local package_target=$(jq -r ".target // empty" "$package_file")
    # 检查version字段是否存在
    if [ -z "$package_version" ] || [ "$package_version" = "null" ] || [ "$package_version" = "" ]; then
        log "WARN" "No version found for package '$package_name', skipping..."
        return 1
    fi
    
    # 检查path字段是否存在
    if [ -z "$package_path" ] || [ "$package_path" = "null" ] || [ "$package_path" = "" ]; then
        log "WARN" "No path found for package '$package_name', skipping..."
        return 1
    fi
    
    # 根据BUILD_TYPE和包类型计算CHECKSUM和文件数
    local new_checksum=""
    local new_file_count=0
    if [ "$BUILD_TYPE" = "dependency" ]; then
        # dependency: 类型为 exec / docker / frontend
        case "$package_type" in
            exec|frontend)
                # exec/frontend类型：扫描主目录及sources目录
                local result=$(calculate_multi_directory "$package_type" "$package_path" "$package_file")
                new_checksum=$(echo "$result" | head -n1)
                new_file_count=$(echo "$result" | tail -n1)
                ;;
            docker)
                # docker类型：根据USE_LOCAL_MODE选择检查方式
                if [ "$USE_LOCAL_MODE" = true ]; then
                    # 本地模式：通过本地目录checksum检测版本变化
                    local result=$(calculate_multi_directory "$package_type" "$package_path" "$package_file")
                    new_checksum=$(echo "$result" | head -n1)
                    new_file_count=$(echo "$result" | tail -n1)
                else
                    # 远程模式：通过GitHub tag检测版本变化
                    check_github_latest "$package_file" "$package_name" "$package_version"
                    return $?
                fi
                ;;
            *)
                log "ERROR" "Invalid dependency type '$package_type' for package '$package_name'. Valid types: exec, docker, frontend"
                return 1
                ;;
        esac
    elif [ "$BUILD_TYPE" = "component" ]; then
        # component: 类型为 binary / exec / conf / zip
        case "$package_type" in
            exec|binary)
                check_binary_modified "$package_file" "$package_name" "$package_version"
                return $?
                ;;
            conf)
                # conf类型：path、target跨所有平台查找文件
                if [ -z "$package_target" ] || [ "$package_target" = "null" ] || [ "$package_target" = "" ]; then
                    log "WARN" "No target found for conf package '$package_name', skipping..."
                    return 1
                fi
                local result=$(calculate_conf_package_checksum "$package_path" "$package_target")
                new_checksum=$(echo "$result" | head -n1)
                new_file_count=$(echo "$result" | tail -n1)
                ;;
            zip)
                # zip类型：跨所有平台查找目录
                local result=$(calculate_zip_package_checksum "$package_path" "$package_name")
                new_checksum=$(echo "$result" | head -n1)
                new_file_count=$(echo "$result" | tail -n1)
                ;;
            *)
                log "ERROR" "Invalid component type '$package_type' for package '$package_name'. Valid types: binary, conf, zip"
                return 1
                ;;
        esac
    fi
    
    if [ -z "$new_checksum" ]; then
        log "ERROR" "Failed to calculate checksum for package '$package_name' at path '$package_path'"
        return 1
    fi
    # 从latest.json中读取之前的版本和checksum
    local old_version=$(jq -r ".${LATEST_FIELD_NAME}[\"$package_name\"].version // \"null\"" "$LATEST_JSON")
    local old_checksum=$(jq -r ".${LATEST_FIELD_NAME}[\"$package_name\"].checksum // \"null\"" "$LATEST_JSON")
    
    # 比较 version=$package_version,files=$new_file_count
    if [ "$old_version" = "null" ]; then
        # 首次记录
        log "MODIFIED" "First time recording package '$package_name': version=$package_version, files=$new_file_count"
        if [ "$UPDATE_VERSION" = true ]; then
            jq ".${LATEST_FIELD_NAME}[\"$package_name\"] = {\"version\": \"$package_version\", \"checksum\": \"$new_checksum\", \"file_count\": $new_file_count}" "$LATEST_JSON" > "$LATEST_JSON.tmp"
            mv "$LATEST_JSON.tmp" "$LATEST_JSON"
        fi
        modified=true
    elif [ "$package_version" = "$old_version" ]; then
        # 版本号未变
        if [ "$new_checksum" = "$old_checksum" ]; then
            # 版本号和CHECKSUM都没变
            log "INFO" "No changes for package '$package_name': version=$package_version, files=$new_file_count"
        else
            # 版本号未变但CHECKSUM变了
            if [ "$UPDATE_VERSION" = true ]; then
                # 启用自动版本递增
                local new_version=$(increment_patch_version "$package_file" "$package_version")
                log "MODIFIED" "Update version for '$package_name': $package_version -> $new_version"
                
                # 更新latest.json
                jq ".${LATEST_FIELD_NAME}[\"$package_name\"] = {\"version\": \"$new_version\", \"checksum\": \"$new_checksum\", \"file_count\": $new_file_count}" "$LATEST_JSON" > "$LATEST_JSON.tmp"
                mv "$LATEST_JSON.tmp" "$LATEST_JSON"
                modified=true
            else
                # 未启用自动版本递增，仅记录
                log "MODIFIED" "Module '$package_name' has been modified (version=$package_version, files=$new_file_count, checksum changed)"
                modified=true
            fi
        fi
    else
        # 版本号变了
        if [ "$new_checksum" = "$old_checksum" ]; then
            # 版本号变了但CHECKSUM未变（这是不正常的，但也记录）
            log "MODIFIED" "Module '$package_name': checksum unchanged, version updated: $old_version -> $package_version"
        else
            # 版本号和CHECKSUM都变了
            log "MODIFIED" "Module '$package_name' version updated: $old_version -> $package_version"
        fi
        
        if [ "$UPDATE_VERSION" = true ]; then
            # 更新latest.json
            jq ".${LATEST_FIELD_NAME}[\"$package_name\"] = {\"version\": \"$package_version\", \"checksum\": \"$new_checksum\", \"file_count\": $new_file_count}" "$LATEST_JSON" > "$LATEST_JSON.tmp"
            mv "$LATEST_JSON.tmp" "$LATEST_JSON"
        fi
        modified=true
    fi
    
    if [ "$modified" = true ]; then
        # 返回 0 表示包被修改
        return 0
    else
        # 返回 1 表示包未修改
        return 1
    fi
}

# 主函数
main() {
    prompt "=============================================="
    prompt "Checking package updates from $JSONS_DIR (type: $BUILD_TYPE)"
    prompt "=============================================="
    prompt ""
    
    # 遍历每个包
    local modified_packages=()
    local skip_packages=()
    local target_packages=()
    if [ -n "$PACKAGES" ]; then
        # 如果指定了packages选项，则将逗号分隔的字符串转换为数组
        IFS=',' read -ra target_packages <<< "$PACKAGES"
        log "INFO" "Checking only specified packages: ${target_packages[*]}"
    fi
    local package_count=0
    local checked_count=0
    for package_file in "$JSONS_DIR"/*.json; do
        [ -f "$package_file" ] || continue
        
        package_count=$((package_count + 1))

        local package_name=$(basename "$package_file" .json)
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
            if ! is_module_enabled "$package_file"; then
                # log "INFO" "Module '$package_name' is disabled, skipping..."
                skip_packages+=("$package_name")
                continue
            fi
        fi
        
        if [ "$should_process" = true ]; then
            checked_count=$((checked_count + 1))
            if check_package_dirty "$package_file"; then
                modified_packages+=("$package_name")
            fi
        fi
    done
    
    prompt "=============================================="
    if [ ${#modified_packages[@]} -gt 0 ]; then
        if [ "$UPDATE_VERSION" = true ]; then
            prompt "Check completed. $LATEST_JSON has been updated."
        else
            prompt "Check completed. Changes detected (no files updated, use --update to apply)."
        fi
        prompt ""
        prompt "Modified packages (${#modified_packages[@]}):"
        for pkg in "${modified_packages[@]}"; do
            prompt "  - $pkg"
        done
    else
        prompt "Check completed. No updates found."
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
    
    # 输出所有发生变化的包名到标准输出（以逗号分隔）
    if [ ${#modified_packages[@]} -gt 0 ]; then
        (IFS=','; echo "${modified_packages[*]}")
    fi
}

# Parse command line options
args=$(getopt -o uhp:vt: --long help,update,packages:,verbose,build-type:,local -n 'check-update.sh' -- "$@")
[ $? -ne 0 ] && print_usage && exit 1

eval set -- "$args"

while true; do
    case "$1" in
        -u|--update) UPDATE_VERSION=true; shift;;
        -p|--packages) PACKAGES="$2"; shift 2;;
        -t|--build-type)
            BUILD_TYPE="$2"
            if [ "$BUILD_TYPE" != "dependency" ] && [ "$BUILD_TYPE" != "component" ]; then
                log "ERROR" "Invalid build-type: $BUILD_TYPE (must be 'dependency' or 'component')"
                exit 1
            fi
            shift 2
            ;;
        --local) USE_LOCAL_MODE=true; shift;;
        -v|--verbose) VERBOSE=true; shift;;
        -h|--help) print_usage; exit 0;;
        --) shift; break;;
        *) print_usage; exit 1;;
    esac
done

# 根据BUILD_TYPE设置JSONS_DIR和LATEST_FIELD_NAME
case "$BUILD_TYPE" in
    dependency)
        JSONS_DIR="./depends"
        LATEST_FIELD_NAME="dependency"
        ;;
    component)
        JSONS_DIR="./components"
        LATEST_FIELD_NAME="component"
        ;;
esac

# 检查JSONS_DIR目录是否存在
if [ ! -d "$JSONS_DIR" ]; then
    log "ERROR" "$JSONS_DIR directory not found!"
    exit 1
fi

# 检查JSONS_DIR目录中是否有JSON文件
if [ -z "$(ls -A "$JSONS_DIR"/*.json 2>/dev/null)" ]; then
    log "ERROR" "No JSON files found in $JSONS_DIR directory!"
    exit 1
fi

# 初始化或读取latest.json
if [ ! -f "$LATEST_JSON" ]; then
    log "INFO" "$LATEST_JSON not found, creating new one..."
    echo "{}" > "$LATEST_JSON"
fi

main
