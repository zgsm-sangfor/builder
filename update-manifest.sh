#!/bin/bash
# update-manifest.sh
# 该脚本以 costrict-manifest.json 为模板，补全组件版本信息，输出到 configures/costrict-system/manifest.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/costrict-manifest.json"
OUTPUT_FILE="$SCRIPT_DIR/configures/common/costrict-system/manifest.json"
COMPONENTS_DIR="$SCRIPT_DIR/components"

# 构建新的 components 数组，遍历 components 目录下的所有模块定义 JSON 文件
components="["
first=true

for build_file in "$COMPONENTS_DIR"/*.json; do
    # 检查 enabled 字段，若为 false 则跳过该模块（不存在 enabled 字段时视为启用）
    # 注意：不能用 jq 的 // 运算符，因为 false 在 jq 中也是 falsy，false // "true" 会返回 "true"
    enabled=$(jq -r 'if .enabled == false then "false" else "true" end' "$build_file")
    if [ "$enabled" = "false" ]; then
        continue
    fi

    # 从定义 JSON 文件中取出 name、subsystem、version 字段
    name=$(jq -r '.name // empty' "$build_file")
    subsystem=$(jq -r '.subsystem // empty' "$build_file")
    version=$(jq -r '.version // empty' "$build_file")

    # 缺少 name 或 subsystem 字段的模块跳过
    if [ -z "$name" ] || [ -z "$subsystem" ]; then
        continue
    fi

    if [ "$first" = true ]; then
        first=false
    else
        components+=","
    fi

    # 构建组件 JSON 对象
    if [ -n "$version" ]; then
        component_obj=$(jq -n --arg name "$name" --arg subsystem "$subsystem" --arg version "$version" \
            '{name: $name, subsystem: $subsystem, version: $version}')
    else
        component_obj=$(jq -n --arg name "$name" --arg subsystem "$subsystem" \
            '{name: $name, subsystem: $subsystem}')
    fi

    components+="$component_obj"
done

components+="]"

# 读取原始 manifest（保留 leadings 等字段），替换 components 数组
jq --argjson components "$components" '.components = $components' "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Successfully created manifest: $OUTPUT_FILE"
