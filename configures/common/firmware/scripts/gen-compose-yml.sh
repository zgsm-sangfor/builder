#!/bin/bash

# gen-compose-yml.sh - 从指定源文件中提取内容，并生成服务配置，替换其中的标记，输出到目标文件
# 
# 使用方法:
#   ./gen-compose-yml.sh -i <源文件> -o <目标文件>
#
# 示例:
#   ./gen-compose-yml.sh -i sample.env -o output.env
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] [${level}] ${message}"
}

gen_services() {
    local lead_size=$1
    local indent_size=$2
    local spec_file=$3
    
    # 检查规格定义文件是否存在
    if [[ ! -f "$spec_file" ]]; then
        log "ERROR" "服务规格定义文件不存在: $spec_file"
        return 1
    fi
    
    # 使用jq获取services数组元素个数
    local services_count=$(jq -r '.services | length' "$spec_file")
    
    if [[ -z "$services_count" ]] || [[ "$services_count" -eq 0 ]]; then
        log "ERROR" "无法从 $spec_file 中读取服务列表或服务列表为空"
        return 1
    fi
    
    # 计算缩进
    local lead=""
    local indent=""
    for ((i=0; i<lead_size; i++)); do
        lead+=" "
    done
    for ((i=0; i<indent_size; i++)); do
        indent+=" "
    done
    
    # 逐元素处理services数组
    local result=""
    for ((i=0; i<services_count; i++)); do
        # 获取第i个元素的service_name
        local service_name=$(jq -r ".services[$i].service_name" "$spec_file")
        
        if [[ -z "$service_name" ]]; then
            log "WARN" "第 $((i+1)) 个服务缺少 service_name，跳过"
            continue
        fi
        
        # 获取第i个元素的component_name，如果未设置则置为service_name
        local component_name=$(jq -r ".services[$i].component_name // empty" "$spec_file")
        if [[ -z "$component_name" ]]; then
            component_name="$service_name"
        fi
        
        # 根据lead, indent, service_name, component_name构建服务定义
        result+="${lead}${service_name}:\n"
        result+="${lead}${indent}extends:\n"
        result+="${lead}${indent}${indent}file: ./${component_name}/${component_name}.yml\n"
        result+="${lead}${indent}${indent}service: ${service_name}\n"
        
        # 检查是否有dependencies字段
        local has_dependencies=$(jq -r ".services[$i].dependencies // empty" "$spec_file")
        if [[ -n "$has_dependencies" ]] && [[ "$has_dependencies" != "null" ]]; then
            # 获取dependencies数组长度
            local deps_count=$(jq -r ".services[$i].dependencies | length" "$spec_file")
            if [[ "$deps_count" -gt 0 ]]; then
                result+="${lead}${indent}depends_on:\n"
                for ((j=0; j<deps_count; j++)); do
                    local dep_service=$(jq -r ".services[$i].dependencies[$j].service" "$spec_file")
                    local dep_condition=$(jq -r ".services[$i].dependencies[$j].condition" "$spec_file")
                    if [[ -n "$dep_service" ]] && [[ -n "$dep_condition" ]]; then
                        result+="${lead}${indent}${indent}${dep_service}:\n"
                        result+="${lead}${indent}${indent}${indent}condition: ${dep_condition}\n"
                    fi
                done
            fi
        fi
        
        result+="\n"
    done
    
    echo -e "$result"
}

# 替换文件中的密钥标记
replace_in_file() {
    local source_file=$1
    local target_file=$2
    local spec_file=$3
    
    if [[ ! -f "$source_file" ]]; then
        log "ERROR" "源文件不存在: $source_file"
        return 1
    fi
    
    log "INFO" "开始处理源文件: $source_file"
    
    # 清空目标文件（如果存在）
    > "$target_file"
    
    # 逐行处理文件
    local line_num=0
    local replaced_count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        local new_line="$line"
        
        # 查找行中的所有标记（不去重）- 更灵活的正则表达式
        while [[ "$new_line" =~ \{\{([a-zA-Z0-9_]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)\}\} ]]; do
            local match="${BASH_REMATCH[0]}"
            local func="${BASH_REMATCH[1]}"
            local lead_size="${BASH_REMATCH[2]}"
            local indent_size="${BASH_REMATCH[3]}"
            
            local func_lower=$(echo "$func" | tr '[:upper:]' '[:lower:]')
            local result=""
            case "$func_lower" in
                gen_services)
                    result=$(gen_services "$lead_size" "$indent_size" "$spec_file")
                    ;;
                *)
                    log "ERROR" "未知的生成函数: $func"
                    return 1
                    ;;
            esac
            
            if [[ -z "$result" ]]; then
                log "ERROR" "生成文本失败: $func $lead_size $indent_size"
                return 1
            fi
            
            log "INFO" "第 $((line_num + 1)) 行: 替换标记 $match 为 ${func} 密钥 (${#result} 字符)"
            
            # 替换该行中的第一个匹配标记
            new_line="${new_line//$match/$result}"
            replaced_count=$((replaced_count + 1))
        done
        
        # 写入处理后的行
        echo "$new_line" >> "$target_file"
        line_num=$((line_num + 1))
        
    done < "$source_file"
    
    if [[ $replaced_count -eq 0 ]]; then
        log "INFO" "文件中未找到替换标记"
    else
        log "INFO" "已替换 $replaced_count 个标记"
    fi
    
    log "INFO" "文本替换完成，结果已写入: $target_file"
    return 0
}

# 显示使用说明
usage() {
    echo "Usage: gen-compose-yml.sh [options]"
    echo "Generate docker-compose.yml from a template file"
    echo ""
    echo "Options:"
    echo "  -i, --input <SOURCE_FILE>   Input source file (required)"
    echo "  -o, --output <TARGET_FILE>  Output target file (required)"
    echo "  -s, --spec <SPEC_FILE>      Service specification file (default: system-spec.json)"
    echo "  -f                          Force overwrite existing target file"
    echo "  -h                          Show this help message"
    echo ""
    echo "Description:"
    echo ""
    echo "Supported marker formats:"
    echo "  {{gen_service <lead_size> <indent_size>}}   "
    echo ""
    echo "Examples:"
    echo "  # Generate docker-compose.yml from template"
    echo "  gen-compose-yml.sh -i sample.env -o output.env"
    echo "  gen-compose-yml.sh -i sample.env -o output.env -f"
    echo "  gen-compose-yml.sh -i sample.env -o output.env --spec my-spec.json"
    echo "  gen-compose-yml.sh --input sample.env --output output.env"
    echo ""
    echo "  Example markers in source file:"
    echo "    version: '3.8'"
    echo "    services:"
    echo "      {{gen_services 2 2}}"
    echo "    networks:"
    echo "      shenma:"
    echo "        driver: bridge"

}

# 默认值
SOURCE_FILE="docker-compose.yml.in"
TARGET_FILE="docker-compose.yml"
SPEC_FILE="system-spec.json"
FORCE=false

# 使用 getopt 解析参数
args=$(getopt -o i:o:s:fh --long input:,output:,spec:,force,help -n 'gen-compose-yml.sh' -- "$@")
[ $? -ne 0 ] && usage && exit 1

eval set -- "$args"

while true; do
    case "$1" in
        -i|--input) SOURCE_FILE="$2"; shift 2;;
        -o|--output) TARGET_FILE="$2"; shift 2;;
        -s|--spec) SPEC_FILE="$2"; shift 2;;
        -f|--force) FORCE=true; shift;;
        -h|--help) usage; exit 0;;
        --) shift; break;;
        *) usage; exit 1;;
    esac
done

# 检查源文件
if [[ ! -f "$SOURCE_FILE" ]]; then
    log "ERROR" "源文件不存在: $SOURCE_FILE"
    exit 1
fi

# 检查规格定义文件（如果指定的不是默认值，需要检查是否存在）
if [[ ! "$SPEC_FILE" == "system-spec.json" && ! -f "$SPEC_FILE" ]]; then
    log "ERROR" "服务规格定义文件不存在: $SPEC_FILE"
    exit 1
fi

# 输出使用的规格定义文件
log "INFO" "使用服务规格定义文件: $SPEC_FILE"

# 检查目标文件是否存在，如果已存在且未启用 force 选项则退出
if [[ -f "$TARGET_FILE" && "$FORCE" != "true" ]]; then
    log "ERROR" "目标文件已存在: $TARGET_FILE, 使用 -f 选项强制覆盖"
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

# 根据模板docker-compose.yml.in的定义，执行模板替换，填充服务列表，构建一个合法的docker-compose.yml文件
if replace_in_file "$SOURCE_FILE" "$TARGET_FILE" "$SPEC_FILE"; then
    log "INFO" "成功生成文件: $TARGET_FILE"
    exit 0
else
    log "ERROR" "生成 $TARGET_FILE 文件失败"
    exit 1
fi
