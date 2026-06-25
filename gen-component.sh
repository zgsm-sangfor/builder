#!/bin/bash

#
# 功能：
#   gen-component.sh 创建一个可被 build-components.sh 构建的组件模块定义。
#
#   它会一次性生成：
#     1. 组件定义文件  components/<NAME>.json
#     2. 组件源目录结构与待构建元件（exec: build.py；conf: 配置文件；zip: 打包目录）
#     3. 组件说明文档  README.md
#
#   只需提供 --name 一个必填参数，其余字段（type/path/version/platforms 等）会根据
#   type 自动推导出合理的默认值，最大程度减少必选项。
#
#   组件定义 JSON 字段（对应 build-components.sh 的读取逻辑）：
#     - name       : 包名（必填）
#     - type       : exec(可执行程序) / conf(配置文件) / zip(目录打包)，默认 zip
#     - path       : 源目录（exec 默认 ./sources/<NAME>，conf/zip 默认 ./configures）
#     - version    : 版本号（默认 1.0.0）
#     - platforms  : 支持平台数组，格式见 --platforms（exec 默认 linux/amd64,windows/amd64；
#                    conf/zip 默认 common，即不输出该字段，由 build-components.sh 视为公共包）
#     - target     : 仅 conf 类型，要打包的目标文件名（默认 <NAME>.json）
#     - filename   : 打包后在组件中的安装路径（conf 默认 config/<target>；其余默认不输出）
#     - description: 描述（默认根据 name 生成）
#     - enabled    : 是否启用，--disabled 时输出 false
#
#   不同 type 的构建方式（build-components.sh）：
#     - exec: 进入 path 执行 `python ./build.py --software <v> --os <os> --arch <arch> --output <out>`
#     - conf: 复制 path/<os>/<arch>/<target>（不存在则 path/common/<target>）到产物目录
#     - zip : 将 path/<os>/<arch>/<NAME>（不存在则 path/common/<NAME>）整目录打成 zip
#
# 选项说明：
#   --name <NAME>                  组件名（必填）。决定输出文件名 components/<NAME>.json
#   --type <TYPE>                  组件类型：zip（默认）/ conf / exec
#   --path <PATH>                  源目录（默认按 type 推导）
#   --version <VERSION>            版本号（默认：1.0.0）
#   --platforms <SPEC>             平台规格，逗号分隔的 os/arch（如 linux/amd64,windows/amd64），
#                                  或 common（默认按 type 推导）
#   --target <TARGET>              conf 类型的目标文件名（默认：<NAME>.json）
#   --filename <FILENAME>          打包安装路径（conf 默认：config/<target>）
#   --service <SERVICES>           逗号分隔的服务名列表；
#                                    为 configures/common/<NAME>/services.json 生成服务定义
#   --description <DESC>           描述信息（默认按 name 生成）
#   --disabled                     将 enabled 置为 false
#   --no-scaffold                  不创建源目录骨架与待构建元件，仅生成 JSON
#   --force                        覆盖已存在的定义文件或元件
#   -h, --help                     帮助信息
#
# 用法示例：
#   # 最简方式：生成一个 zip 组件（自动在 ./configures/common/my-pkg/ 下创建骨架）
#   ./gen-component.sh --name my-pkg
#
#   # 生成一个 conf 配置组件（自动在 ./configures/common/ 下创建占位配置）
#   ./gen-component.sh --name my-config --type conf
#
#   # 生成一个 exec 可执行组件（自动创建 ./sources/my-app/build.py）
#   ./gen-component.sh --name my-app --type exec
#
#   # 指定多平台与版本
#   ./gen-component.sh --name my-app --version 2.1.0 --platforms linux/amd64,linux/arm64,darwin/arm64
#
#   # 生成 zip 组件并附带服务列表
#   ./gen-component.sh --name my-module --service "svc-a,svc-b,svc-c"
#

set -e

usage() {
    echo "Usage: gen-component.sh [OPTIONS]"
    echo "Create a component module definition (components/<NAME>.json) for build-components.sh,"
    echo "along with its source directory skeleton and build artifacts."
    echo ""
    echo "Required:"
    echo "  --name <NAME>                  Component name (also defines output filename)"
    echo ""
    echo "Optional (auto-derived when omitted):"
    echo "  --type <TYPE>                  Component type: zip (default) / conf / exec"
    echo "  --path <PATH>                  Source directory (auto-derived by type)"
    echo "  --version <VERSION>            Version string (default: 1.0.0)"
    echo "  --platforms <SPEC>             Platforms: comma-separated os/arch (e.g. linux/amd64,windows/amd64)"
    echo "                                  or 'common'. Default: by type (exec=linux/amd64,windows/amd64;"
    echo "                                  conf/zip=common)"
    echo "  --target <TARGET>              Target filename for conf type (default: <NAME>.json)"
    echo "  --filename <FILENAME>          Install path in package (conf default: config/<target>)"
    echo "  --service <SERVICES>           Comma-separated service names; generates"
    echo "                                  configures/common/<NAME>/services.json"
    echo "  --description <DESC>           Description"
    echo "  --disabled                     Set enabled to false"
    echo "  --no-scaffold                  Only generate the JSON, skip directory skeleton"
    echo "  --force                        Overwrite existing files"
    echo "  -h, --help                     Show this help"
    echo ""
    echo "Examples:"
    echo "  ./gen-component.sh --name my-pkg"
    echo "  ./gen-component.sh --name my-config --type conf"
    echo "  ./gen-component.sh --name my-app --type exec"
    echo "  ./gen-component.sh --name my-module --service \"svc-a,svc-b,svc-c\""
    exit 1
}

# 检查 jq 工具是否可用
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq command not found! Please install jq to generate JSON files."
    exit 1
fi

# 默认参数
NAME=""
TYPE="zip"
PATH_VALUE=""
VERSION="1.0.0"
PLATFORMS=""
TARGET=""
FILENAME=""
DESCRIPTION=""
ENABLED=""          # 空=不输出 enabled 字段；"false"=输出 enabled:false
NO_SCAFFOLD=false
SERVICES=""
FORCE=false

# 解析命令行参数
while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME="$2"; shift 2;;
        --type) TYPE="$2"; shift 2;;
        --path) PATH_VALUE="$2"; shift 2;;
        --version) VERSION="$2"; shift 2;;
        --platforms) PLATFORMS="$2"; shift 2;;
        --target) TARGET="$2"; shift 2;;
        --filename) FILENAME="$2"; shift 2;;
        --description) DESCRIPTION="$2"; shift 2;;
        --disabled) ENABLED="false"; shift;;
        --no-scaffold) NO_SCAFFOLD=true; shift;;
        --service) SERVICES="$2"; shift 2;;
        --force) FORCE=true; shift;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown option: $1"; echo ""; usage;;
    esac
done

# 校验必填参数
if [ -z "$NAME" ]; then
    echo "Error: --name is required"
    echo ""
    usage
fi

# 校验 type 取值
if [ "$TYPE" != "exec" ] && [ "$TYPE" != "conf" ] && [ "$TYPE" != "zip" ]; then
    echo "Error: --type must be 'exec', 'conf' or 'zip' (got: $TYPE)"
    echo ""
    usage
fi

# ---- 根据类型推导默认值 ----

# 源目录默认值
if [ -z "$PATH_VALUE" ]; then
    case "$TYPE" in
        exec) PATH_VALUE="./sources/${NAME}";;
        conf|zip) PATH_VALUE="./configures";;
    esac
fi

# 平台默认值
if [ -z "$PLATFORMS" ]; then
    case "$TYPE" in
        exec) PLATFORMS="linux/amd64,windows/amd64";;
        conf|zip) PLATFORMS="common";;
    esac
fi

# conf 类型的 target 与 filename 默认值
if [ "$TYPE" = "conf" ]; then
    if [ -z "$TARGET" ]; then
        TARGET="${NAME}.json"
    fi
    if [ -z "$FILENAME" ]; then
        FILENAME="config/${TARGET}"
    fi
fi

# 描述默认值
if [ -z "$DESCRIPTION" ]; then
    case "$TYPE" in
        exec) DESCRIPTION="${NAME} executable component";;
        conf) DESCRIPTION="${NAME} configuration file";;
        zip)  DESCRIPTION="${NAME} package component";;
    esac
fi

# ---- 组装组件定义 JSON ----
# 策略：
#   1. 先在 shell 中预构建复杂值（platforms 数组）的 JSON 片段；
#   2. 简单字符串字段用 --arg 传入，在 jq 过滤器中用 select 剔除空值；
#   3. 非字符串字段（数组/布尔）用 --argjson 传入，null 值会被 with_entries 剔除。

# 预构建 platforms JSON 片段（数组或 null）
if [ -n "$PLATFORMS" ] && [ "$PLATFORMS" != "common" ]; then
    PLATFORMS_JSON=$(echo "$PLATFORMS" | jq -Rsc \
        'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(split("/") | {os:.[0], arch:.[1]})')
else
    PLATFORMS_JSON="null"
fi

RESULT=$(jq -n \
    --arg name "$NAME" \
    --arg type "$TYPE" \
    --arg path "$PATH_VALUE" \
    --arg version "$VERSION" \
    --argjson platforms "$PLATFORMS_JSON" \
    --arg target "$TARGET" \
    --arg filename "$FILENAME" \
    --arg enabled "$ENABLED" \
    --arg description "$DESCRIPTION" \
    '{
        name: $name,
        type: $type,
        path: $path,
        version: $version,
        platforms: $platforms,
        target: (if $target != "" and $type == "conf" then $target else null end),
        filename: (if $filename != "" then $filename else null end),
        enabled: (if $enabled == "false" then false else null end),
        description: ($description | if . != "" then . else null end)
    } | with_entries(select(.value != null))')

# ---- 写入组件定义文件 ----
COMPONENTS_DIR="components"
mkdir -p "$COMPONENTS_DIR"

OUTPUT_FILE="${COMPONENTS_DIR}/${NAME}.json"

if [ -f "$OUTPUT_FILE" ] && [ "$FORCE" != true ]; then
    echo "Error: Component definition already exists: $OUTPUT_FILE"
    echo "Use --force to overwrite."
    exit 1
fi

echo "$RESULT" > "$OUTPUT_FILE"
echo "Created component definition: $OUTPUT_FILE"

# ---- 创建源目录骨架与待构建元件 ----
# 写入文件辅助函数：若文件已存在且未 --force，则跳过
write_file() {
    local file="$1"
    local content="$2"
    if [ -f "$file" ] && [ "$FORCE" != true ]; then
        echo "  Skip existing: $file (use --force to overwrite)"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$content" > "$file"
    echo "  Created: $file"
}

if [ "$NO_SCAFFOLD" != true ]; then
    echo ""
    echo "Scaffolding source directory & build artifacts..."

    case "$TYPE" in
        exec)
            # exec 类型：在 path 下创建 build.py 与 README.md
            # build.py 需接受 --software/--os/--arch/--output 参数（build_app 的调用约定）
            BUILD_PY=$(cat <<EOF
#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
${NAME} 组件构建脚本

build-components.sh（type=exec）会以如下方式调用本脚本：
    python ./build.py --software <version> --os <os> --arch <arch> --output <output_target>

最终构建产物必须输出到 --output 指定的路径。
请在下方 TODO 处替换为实际的编译/构建逻辑。
"""
import argparse
import os
import shutil
import sys


def main():
    parser = argparse.ArgumentParser(description="Build ${NAME} component")
    parser.add_argument("--software", required=True, help="version string")
    parser.add_argument("--os", required=True, dest="target_os", help="target os")
    parser.add_argument("--arch", required=True, help="target arch")
    parser.add_argument("--output", required=True, help="output file path")
    args = parser.parse_args()

    print("Building ${NAME} %s for %s/%s" % (args.software, args.target_os, args.arch))
    print("Output:", args.output)

    out_dir = os.path.dirname(args.output)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    # TODO: 在此处实现实际的构建逻辑，并将产物写入 args.output。
    #       例如：shutil.copy("your-binary", args.output)
    # 占位实现：写入一个临时文件，便于验证构建流程可跑通。
    with open(args.output, "w") as f:
        f.write("${NAME} %s %s/%s\\n" % (args.software, args.target_os, args.arch))

    print("Build finished.")


if __name__ == "__main__":
    main()
EOF
)
            EXEC_README=$(cat <<EOF
# ${NAME}

${DESCRIPTION}

## 构建

本组件由 build-components.sh 以 exec 方式构建。在源目录执行：

\`\`\`bash
python ./build.py --software ${VERSION} --os linux --arch amd64 --output ./${NAME}
\`\`\`

build-components.sh 会针对 \`components/${NAME}.json\` 中声明的每个平台自动调用本脚本。

## 组件定义

详见 [\`components/${NAME}.json\`](../components/${NAME}.json)。
EOF
)
            write_file "${PATH_VALUE}/build.py" "$BUILD_PY"
            write_file "${PATH_VALUE}/README.md" "$EXEC_README"
            ;;

        conf)
            # conf 类型：在 path/common/<target>（及各平台目录）下创建占位配置文件
            # build_conf 查找顺序：path/<os>/<arch>/<target>，其次 path/common/<target>
            PLACEHOLDER_CONF=$(cat <<EOF
{
  "name": "${NAME}",
  "version": "${VERSION}",
  "description": "${DESCRIPTION}",
  "options": {}
}
EOF
)
            # common 公共配置
            write_file "${PATH_VALUE}/common/${TARGET}" "$PLACEHOLDER_CONF"

            # 若指定了具体平台，为每个平台创建占位文件（覆盖平台差异场景）
            if [ "$PLATFORMS" != "common" ]; then
                OLD_IFS="$IFS"
                IFS=','
                for pair in $PLATFORMS; do
                    IFS='/' read -r p_os p_arch <<< "$(echo "$pair" | xargs)"
                    [ -z "$p_os" ] && continue
                    write_file "${PATH_VALUE}/${p_os}/${p_arch}/${TARGET}" "$PLACEHOLDER_CONF"
                done
                IFS="$OLD_IFS"
            fi

            CONF_README=$(cat <<EOF
# ${NAME}

${DESCRIPTION}

## 说明

本组件由 build-components.sh 以 conf 方式打包。打包的目标文件为 \`${TARGET}\`，
安装路径为 \`${FILENAME}\`。

源文件查找顺序（由 build-components.sh 决定）：
1. \`${PATH_VALUE}/<os>/<arch>/${TARGET}\`（平台特定）
2. \`${PATH_VALUE}/common/${TARGET}\`（公共回退）

## 组件定义

详见 [\`components/${NAME}.json\`](../components/${NAME}.json)。
EOF
)
            write_file "${PATH_VALUE}/common/${NAME}.README.md" "$CONF_README"
            ;;

        zip)
            # zip 类型：在 path/common/<NAME>/（及各平台目录）下创建打包目录骨架
            # build_zip 查找顺序：path/<os>/<arch>/<NAME>，其次 path/common/<NAME>
            ZIP_README=$(cat <<EOF
# ${NAME}

${DESCRIPTION}

本目录的内容会被 build-components.sh 以 zip 方式整体打包为 \`${NAME}.zip\`。

如需针对不同平台提供不同内容，可在 \`${PATH_VALUE}/<os>/<arch>/${NAME}/\` 下放置
平台特定版本；未提供平台目录时，回退到本 common 目录。
EOF
)
            # 生成 IMAGE 环境变量名：IMAGE_ + NAME 转大写且 - 替换为 _
            IMAGE_VAR="IMAGE_$(echo "$NAME" | tr '[:lower:]-' '[:upper:]_')"

            # docker compose 服务 yml 模板，提取了各组件的共性部分
            ZIP_YML=$(cat <<EOF
services:
  ${NAME}:
    image: \${${IMAGE_VAR}}
    restart: always
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - \${COSTRICT_DATA_DIR}/backend/${NAME}/logs:/app/logs
    networks:
      - shenma
EOF
)
            write_file "${PATH_VALUE}/common/${NAME}/README.md" "$ZIP_README"
            write_file "${PATH_VALUE}/common/${NAME}/${NAME}.yml" "$ZIP_YML"

            # 若指定了具体平台，为每个平台创建目录骨架
            if [ "$PLATFORMS" != "common" ]; then
                OLD_IFS="$IFS"
                IFS=','
                for pair in $PLATFORMS; do
                    IFS='/' read -r p_os p_arch <<< "$(echo "$pair" | xargs)"
                    [ -z "$p_os" ] && continue
                    write_file "${PATH_VALUE}/${p_os}/${p_arch}/${NAME}/README.md" "$ZIP_README"
                    write_file "${PATH_VALUE}/${p_os}/${p_arch}/${NAME}/${NAME}.yml" "$ZIP_YML"
                done
                IFS="$OLD_IFS"
            fi
            ;;
    esac
fi

# ---- 生成 services.json（--service 选项） ----
if [ -n "$SERVICES" ]; then
    SERVICES_DIR="configures/common/${NAME}"
    SERVICES_FILE="${SERVICES_DIR}/services.json"

    if [ -f "$SERVICES_FILE" ] && [ "$FORCE" != true ]; then
        echo "Error: services.json already exists: $SERVICES_FILE"
        echo "Use --force to overwrite."
        exit 1
    fi

    # 将逗号分隔的服务名列表转为 JSON 数组
    SERVICES_JSON=$(echo "$SERVICES" | jq -Rsc \
        'split(",") | map(gsub("^\\s+|\\s+$";"")) | map({service_name: .})')

    jq -n \
        --arg component_name "$NAME" \
        --argjson services_arr "$SERVICES_JSON" \
        '{component_name: $component_name, services: $services_arr}' \
        > "$SERVICES_FILE"

    echo "Created services.json: $SERVICES_FILE"
fi

# ---- 输出结果 ----
echo ""
echo "Generated component definition:"
echo "----------------------------------------------"
cat "$OUTPUT_FILE"
echo "----------------------------------------------"
echo ""
echo "Source directory: ${PATH_VALUE}"
echo ""
echo "You can now build it with:"
echo "  ./build-components.sh -p ${NAME} --def"
echo "(--def = --build + --pack + --index)"
