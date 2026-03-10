#!/bin/bash
# update-manifest.sh
# 该脚本以 costrict-manifest.json 为模板，补全组件版本信息，输出到 configures/costrict-system/manifest.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/costrict-manifest.json"
OUTPUT_FILE="$SCRIPT_DIR/configures/common/costrict-system/manifest.json"
BUILDS_DIR="$SCRIPT_DIR/builds"

# 构建新的 components 数组
components="["
first=true

# 获取所有组件名称
component_names=$(jq -r '.components[].name' "$TEMPLATE_FILE")

for name in $component_names; do
    build_file="$BUILDS_DIR/$name.json"
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
        components+="{\"name\":\"$name\",\"version\":\"$version\"}"
    else
        components+="{\"name\":\"$name\"}"
    fi
done

components+="]"

# 读取原始 manifest 并替换 components 数组
jq --argjson components "$components" '.components = $components' "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Manifest already created: $OUTPUT_FILE"
