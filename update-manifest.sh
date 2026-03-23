#!/bin/bash
# update-manifest.sh
# 该脚本以 costrict-manifest.json 为模板，补全组件版本信息，输出到 configures/costrict-system/manifest.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/costrict-manifest.json"
OUTPUT_FILE="$SCRIPT_DIR/configures/common/costrict-system/manifest.json"
COMPONENTS_DIR="$SCRIPT_DIR/components"

# 构建新的 components 数组
components="["
first=true

# 遍历 components 数组的索引
component_count=$(jq -r '.components | length' "$TEMPLATE_FILE")
for ((i=0; i<component_count; i++)); do
    # 获取当前组件的完整对象（所有字段）
    component_obj=$(jq -c ".components[$i]" "$TEMPLATE_FILE")
    name=$(echo "$component_obj" | jq -r '.name')
    
    build_file="$COMPONENTS_DIR/$name.json"
    if [ -f "$build_file" ]; then
        version=$(jq -r '.version // empty' "$build_file")
    else
        version=""
    fi
    
    if [ "$first" = true ]; then
        first=false
    else
        components+=","
    fi
    
    if [ -n "$version" ]; then
        # 保留所有原有字段，添加 version 字段
        component_with_version=$(echo "$component_obj" | jq --arg version "$version" '. + {"version": $version}')
    else
        component_with_version="$component_obj"
    fi
    
    components+="$component_with_version"
done

components+="]"

# 读取原始 manifest 并替换 components 数组
jq --argjson components "$components" '.components = $components' "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Successfully created manifest: $OUTPUT_FILE"
