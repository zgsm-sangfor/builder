#!/bin/bash
# gen-backend-spec.sh
# 1. 扫描 components 目录下所有模块定义 JSON，筛选出 enabled 且 subsystem=backend 的模块，
#    提取 name→component_name, display_name, description, dependences，
#    覆盖 costrict-backend-spec.json 中的 components 字段。
# 2. 扫描 configures/common/*/services.json，聚合所有模块的 services 定义，
#    覆盖 costrict-backend-spec.json 中的 services 字段。
# 3. 输出到 configures/common/backend/system-spec.json，其它字段保持不变。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/costrict-backend-spec.json"
OUTPUT_FILE="$SCRIPT_DIR/configures/common/backend/system-spec.json"
COMPONENTS_DIR="$SCRIPT_DIR/components"
SERVICES_DIR="$SCRIPT_DIR/configures/common"

# ============================================================
# 第一部分：构建 components 数组
# ============================================================
components="["
first=true

for comp_file in "$COMPONENTS_DIR"/*.json; do
    # 检查 enabled 字段，若显式为 false 则跳过该模块
    # 注意：不能用 jq 的 // 运算符，因为 false 在 jq 中也是 falsy
    enabled=$(jq -r 'if .enabled == false then "false" else "true" end' "$comp_file")
    if [ "$enabled" = "false" ]; then
        continue
    fi

    # 检查 subsystem 字段，只保留 backend
    subsystem=$(jq -r '.subsystem // empty' "$comp_file")
    if [ "$subsystem" != "backend" ]; then
        continue
    fi

    # 提取 name（作为 component_name）、display_name、description
    name=$(jq -r '.name // empty' "$comp_file")
    display_name=$(jq -r '.display_name // empty' "$comp_file")
    description=$(jq -r '.description // empty' "$comp_file")

    # 缺少 name 字段的模块跳过
    if [ -z "$name" ]; then
        continue
    fi

    if [ "$first" = true ]; then
        first=false
    else
        components+=","
    fi

    # 提取 dependences（可选，使用 -c 获取紧凑 JSON）
    dependences=$(jq -c '.dependences // empty' "$comp_file")

    # 构建组件 JSON 对象
    if [ -n "$dependences" ]; then
        component_obj=$(jq -n \
            --arg component_name "$name" \
            --arg display_name "$display_name" \
            --arg description "$description" \
            --argjson dependences "$dependences" \
            '{component_name: $component_name, display_name: $display_name, description: $description, dependences: $dependences}')
    else
        component_obj=$(jq -n \
            --arg component_name "$name" \
            --arg display_name "$display_name" \
            --arg description "$description" \
            '{component_name: $component_name, display_name: $display_name, description: $description}')
    fi

    components+="$component_obj"
done

components+="]"

# ============================================================
# 第二部分：从各模块 services.json 聚合 services 数组
# 只读取 enabled 不为 false 的模块
# ============================================================
services_json="["
first_svc=true

for svc_file in "$SERVICES_DIR"/*/services.json; do
    [ -f "$svc_file" ] || continue

    # 获取模块目录名，查找对应的 component JSON 并检查 enabled 字段
    module_dir=$(basename "$(dirname "$svc_file")")
    comp_json="$COMPONENTS_DIR/${module_dir}.json"

    if [ -f "$comp_json" ]; then
        enabled=$(jq -r 'if .enabled == false then "false" else "true" end' "$comp_json")
        if [ "$enabled" = "false" ]; then
            continue
        fi
    fi

    # 读取外层的 component_name
    comp_name=$(jq -r '.component_name // empty' "$svc_file")
    if [ -z "$comp_name" ]; then
        continue
    fi

    # 逐个提取 service 对象，补回 component_name 字段
    while IFS= read -r svc_obj; do
        [ -z "$svc_obj" ] && continue

        if [ "$first_svc" = true ]; then
            first_svc=false
        else
            services_json+=","
        fi

        # 将 component_name 注入到每个 service 对象中
        svc_with_comp=$(echo "$svc_obj" | jq -c --arg cn "$comp_name" '{component_name: $cn} + .')
        services_json+="$svc_with_comp"
    done < <(jq -c '.services[]' "$svc_file")
done

services_json+="]"

# ============================================================
# 输出：替换 components 和 services 字段
# ============================================================
jq --argjson components "$components" --argjson services "$services_json" \
    '.components = $components | .services = $services' \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "Successfully created backend spec: $OUTPUT_FILE"
echo "  components: $(echo "$components" | jq 'length') 个"
echo "  services:   $(echo "$services_json" | jq 'length') 个"
