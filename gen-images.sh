#!/usr/bin/env bash
# 按当前组件开关和服务定义生成镜像列表，不修改配置，不需要 Docker。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$SCRIPT_DIR" "$@" <<'PY'
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(sys.argv.pop(1))
parser = argparse.ArgumentParser(description="仅输出已启用服务实际引用的镜像，每行一个，排序去重。依赖 Python 3、PyYAML。")
parser.add_argument("-s", "--source", type=Path, default=root / "configures/common", help="服务配置目录（默认：脚本目录/configures/common）")
parser.add_argument("-c", "--components", type=Path, default=root / "components", help="组件定义目录（默认：脚本目录/components）")
parser.add_argument("--check", action="store_true", help="调用 Docker 检查镜像是否已存在，并输出安装脚本相同格式的状态")
args = parser.parse_args()

try:
    import yaml
except ImportError:
    sys.exit("错误：缺少 PyYAML，请安装 python3-yaml 或执行 python3 -m pip install PyYAML")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read_images(path):
    # 仅解析赋值，不 source/eval 配置，避免执行其中的命令。
    values = {}
    if not path.is_file():
        return values
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)", line)
        if not match:
            raise ValueError(f"{path}:{number}: 无效的环境变量赋值")
        key, value = match.groups()
        if value.startswith(('"', "'")):
            quoted = re.fullmatch(r"(['\"])(.*?)\1\s*(?:#.*)?", value)
            if not quoted:
                raise ValueError(f"{path}:{number}: 无效的引号")
            value = quoted.group(2)
        else:
            value = re.split(r"\s+#", value, maxsplit=1)[0].strip()
        values[key] = value
    return values


def resolve_image(expression, values):
    def replace(match):
        key, operator, default = match.groups()
        value = values.get(key)
        if (operator == ":-" and not value) or (operator == "-" and value is None):
            return default
        if value is None:
            raise ValueError(f"镜像变量 {key} 未在 image.env 中定义")
        return value

    result = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:-|-)([^}]*))?\}", replace, expression)
    if not result or "$" in result or re.search(r"\s", result):
        raise ValueError(f"无法解析镜像：{expression!r}")
    return result


try:
    for directory in (args.source, args.components):
        if not directory.is_dir():
            raise ValueError(f"目录不存在：{directory}")
    images = set()
    for services_file in sorted(args.source.glob("*/services.json")):
        component_file = args.components / f"{services_file.parent.name}.json"
        # 与 gen-backend-spec.sh 一致：仅显式 false 禁用，缺省启用。
        if component_file.is_file() and read_json(component_file).get("enabled") is False:
            continue
        definition = read_json(services_file)
        component = definition.get("component_name")
        if not component or definition.get("enabled") is False:
            continue
        for service in definition["services"]:
            if service.get("enabled") is False:
                continue
            name = service["service_name"]
            directory = args.source / (service.get("component_name") or component)
            compose_file = directory / f"{name}.yml"
            compose = yaml.safe_load(compose_file.read_text(encoding="utf-8-sig"))
            expression = compose["services"][name]["image"]
            images.add(resolve_image(expression, read_images(directory / "image.env")))
    # 全部解析成功后再输出，避免出错时留下不完整列表。
    image_list = sorted(images)
    if not args.check:
        for image in image_list:
            print(image)
    else:
        docker = shutil.which("docker")
        if docker is None:
            raise RuntimeError("未找到 docker 命令；请安装 Docker，或不使用 --check 仅生成镜像列表")
        missing = 0
        for image in image_list:
            result = subprocess.run(
                [docker, "image", "inspect", image],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode == 0:
                print(f"[存在] ({image})")
            else:
                print(f"[缺失] ({image})")
                missing += 1
        if missing:
            print(f"检查完成，共有 {missing} 个镜像缺失")
            sys.exit(1)
        print("所有镜像已存在")
except (OSError, RuntimeError, ValueError, KeyError, TypeError, yaml.YAMLError) as error:
    sys.exit(f"错误：{error}")
PY
