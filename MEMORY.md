# CoStrict Builder 项目记忆

更新时间：2026-09-11。依据当前仓库文件整理；本文件用于后续任务接手，参数与行为以脚本实际实现为准。

## 项目定位

- 本仓库是 CoStrict 的构建与发布工具，主要由 Bash 脚本、JSON 定义和部署配置组成。
- 构建对象包括 Docker 镜像、前端资源、可执行程序，以及 zip / conf / exec 组件包。
- 使用说明见 `README.md`，模块开发及配置机制见 `developer.md`，CI 入口为 `.github/workflows/build.yaml`。

## 关键路径

| 路径 | 用途 |
| --- | --- |
| `depends/` | 依赖构建定义，包含版本、源码路径、构建命令等 |
| `components/` | 组件包定义，包含类型、子系统、版本、配置路径等 |
| `configures/common/` | 服务通用配置与部署模板 |
| `configures/linux/`、`configures/darwin/`、`configures/windows/` | 平台配置 |
| `latest.json` | 版本及 checksum 记录 |
| `packages.json` | 包列表索引 |
| `costrict-manifest.json` | 系统发布清单模板 |
| `costrict-backend-spec.json` | backend 子系统规格模板 |
| `packages/` | 组件构建产物，一般按包名、OS、架构、版本分层 |
| `images/` | 镜像相关产物与构建版本记录 |
| `costrict-static/`、`site/` | 安装资源与本地下载站点 |
| `artifact-local/` | `local-build.sh` 默认输出目录 |

## 主要脚本与流程

- `build-costrict.sh`：编排依赖更新、依赖构建、backend 规格生成、组件版本更新、系统清单生成和组件打包。
  - `--update` 才启用 dependency 变更检测与版本递增。
  - `--build all|auto|包名列表` 指定依赖构建；不传则不构建依赖。
  - `--pack all|auto|包名列表` 指定组件打包；不传则不打包组件。
  - `--push <环境>` 与依赖构建配合使用；`--upload <环境>` 与组件打包配合使用。
  - `--local` 从 `local.json` 的 `packages` 字段读取本地构建模块列表。
  - `--version <版本>` 指定 `costrict-system` 发布版本。
  - 即使不构建或打包，流程仍会生成规格、清单并检测更新组件版本，不能把无参数运行当成只读检查。
- `build-depends.sh`：处理依赖构建、镜像推送等；其 `--update` 操作可能修改组件的镜像配置。
- `build-components.sh`：组件构建、签名、打包、索引及上传；`--pack` 包含 build / pack / index 完整流程。
- `check-update.sh`：检测变更，`--update` 写入更新后的版本；待构建列表由 `check-build.sh` 判断。
- `check-build.sh`：组件模式检查本地产物，dependency 模式检查 `images/<name>/versions.json`。
- `gen-backend-spec.sh`：生成 `configures/common/backend/system-spec.json`。
- `gen-manifest.sh`：生成 `configures/common/costrict-system/manifest.json`；生成后编排脚本会再次处理系统组件版本。
- `gen-component.sh` / `gen-depend.sh`：生成组件骨架 / 依赖定义。
- `build-mirror.sh`：构建 `costrict-mirror.tar.gz`，支持 `--ignore-images`。

## 常用操作

在仓库根目录执行；以下构建命令会写入配置、版本记录或产物。

```bash
# 检查本地构建状态
./check-build.sh --build-type dependency
./check-build.sh --packages backend,frontend

# 仅指定组件打包
./build-costrict.sh --pack backend,frontend,costrict-system

# 检测依赖更新，并构建依赖及组件
./build-costrict.sh --update --build all --pack all

# 利用下载缓存进行本地打包
./local-build.sh --cache-dir ./build-cache/

# 缓存完整时离线打包
./local-build.sh --cache-dir ./build-cache/ --offline
```

`local-build.sh` 默认利用 Release 中的预构建可执行包，重新构建并签名当前工作树的组件配置，不构建服务 Docker 镜像。输出 `artifact-local/packages.tar.gz` 和 `artifact-local/costrict-mirror.tar.gz`。默认缓存目录为 `local-build-cache/`，上面的命令显式使用现有 `build-cache/`。

`--assemble-only` 复用已签名组件包，不需要 smc 或签名私钥；`--cache-only` 只准备缓存。离线模式缺少缓存时会报错。安装资源中仍可能包含 nginx 镜像，不应把“不包含服务镜像”理解为完全无镜像。

## 接手注意事项

- README 的部分示例已落后于脚本，例如无参数完整构建、无环境值的 `--push` 和 `--skip-depend`；使用前核对脚本参数解析与帮助文本。
- 多个脚本使用相对路径，并可能在处理帮助参数前加载 `.env`，优先静态阅读源码确认行为。
- 工具依赖按操作而定：Bash、jq、Docker、smc、zip、rsync、SSH 等；本地资源打包另涉及下载、归档工具。
- `.env` 和签名私钥是本地敏感输入；记忆文件只记录用途，不保存其中的值。
- 根目录 `.gitignore` 使用白名单方式管理文件；新增需要版本管理的根文件时检查是否被忽略。
- 修改 Shell 后可用 `bash -n <脚本>` 做语法检查，JSON 可用 `jq empty <文件>` 验证；这些检查不能替代实际构建验证。

## 本次会话状态

- 用户请求生成记忆文件；本文件基于仓库静态检查生成。
- 开始时 `git status --short` 无输出；未执行构建、发布、上传或版本更新，未验证现有产物是否可用。
- 当前会话未提供其他历史任务、待修复问题或长期偏好，不推断补写。
