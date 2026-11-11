# CoStrict Builder 项目指南

## 项目定位与入口

本仓库是 CoStrict 的构建、打包与发布工具，主要由 Bash 脚本、JSON 定义及服务部署配置组成。业务服务源码通常位于其他仓库；依赖定义中的 `remote` 和 `path` 指向源码仓库及本地目录，不要假设这里能够直接编译所有服务。

- `README.md`：使用说明与配置示例。
- `developer.md`：模块开发和配置机制。
- `.github/workflows/build.yaml`：CI 构建入口。
- 参数、默认值及路径以当前脚本实现为准；文档可能落后于代码。

## 目录与配置关系

| 路径 | 用途 |
| --- | --- |
| `depends/<name>.json` | 依赖定义：源码、版本、镜像仓库、构建/拉取/更新命令 |
| `components/<name>.json` | 部署组件定义：包类型、子系统、包版本、配置来源、组件依赖 |
| `configures/common/<name>/` | 服务通用运行配置、Compose 文件、镜像变量、安装清单等 |
| `configures/linux/`、`darwin/`、`windows/` | 各平台配置，位于 `configures/` 下 |
| `configures/common/<name>/image.env` | 部署使用的实际镜像地址及标签 |
| `configures/common/<name>/services.json` | 供后台规格生成器使用的服务定义 |
| `static/` | 仓库内维护的安装脚本与静态安装资源 |
| `site/` | 下载站点和本地测试站点配置 |
| `latest.json` | 版本及 checksum 记录 |
| `packages.json` | 包列表索引 |
| `packages/`、`images/` | 组件与镜像相关构建产物/记录 |

同一服务的组件包版本与依赖镜像版本是独立版本，不要求相等。例如 `components/<name>.json` 变更配置包版本，`depends/<name>.json` 变更服务镜像版本。修改镜像时还要核对 `image.env` 和依赖的 `update.command`，避免下一次构建将配置覆盖回旧地址。

`depends` 中的 `repo` 用于拼接镜像地址，`remote` 是 Git 源码地址，两者用途不同。镜像仓库可包含完整注册表前缀，如 `ghcr.io/zgsm-sangfor`；命令使用 `{{.repo}}/{{.name}}` 时不要再重复添加 `ghcr.io/`。同时检查 `tag`、构建、拉取和配置更新命令采用的标签是否一致。

## 启用与禁用模块

模块默认启用，禁用使用 JSON 布尔值 `"enabled": false`。

- 若需要同时停止默认组件打包及依赖构建，应检查 `components/<name>.json` 与 `depends/<name>.json` 两处。
- 构建脚本的默认扫描会过滤禁用模块；显式指定包名的执行路径需另外确认，不应假设所有入口都强制过滤。
- 清单及 backend 规格生成器按组件开关过滤；统一使用布尔值，不使用字符串 `"false"`，不同脚本对此的处理并不完全相同。
- 修改开关不会自动停止已经部署的容器，也不会立即重写已生成的系统清单。

## 构建流程与生成文件

`build-costrict.sh` 编排以下流程：依赖变更检测 → 依赖构建及配置更新 → backend 规格生成 → 组件版本检测 → 系统清单生成 → 组件打包 → 可选离线包生成。

| 脚本 | 作用 |
| --- | --- |
| `build-depends.sh` | 构建/拉取依赖，更新镜像配置，可推送镜像 |
| `build-components.sh` | 构建、签名、打包、索引及上传组件；`--pack` 包含 build/pack/index |
| `check-update.sh` | 检测源文件变化，使用 `--update` 可写入新版本 |
| `check-build.sh` | 检查本地组件产物及依赖构建记录 |
| `gen-backend-spec.sh` | 从组件定义和各服务 `services.json` 生成 backend 规格 |
| `gen-manifest.sh` | 从组件定义生成系统发布清单，排除系统组件自身 |
| `gen-images.sh` | 按启用服务及 Compose 引用输出去重镜像列表；需 Python 3、PyYAML，无需 Docker |
| `build-mirror.sh` | 组装离线安装包；`--no-images` 排除服务镜像目录 |
| `local-build.sh` | 利用下载缓存和预构建产物进行本地组装、签名打包 |

生成文件的来源：

- `costrict-backend-spec.json` + `components/*.json` + `configures/common/*/services.json` → `configures/common/backend/system-spec.json`。
- `costrict-manifest.json` + `components/*.json` → `configures/common/costrict-system/manifest.json`。

优先修改源定义；仅修改生成文件会在下次生成时丢失。需要同步发布清单时再运行生成器，并检查产生的差异。

在仓库根目录执行脚本。常见构建用法如下，均可能写入配置、版本或产物：

```bash
./build-costrict.sh --build auto --pack auto
./build-costrict.sh --pack backend,frontend,costrict-system
./build-costrict.sh --update --build all --pack all
```

`--build` 和 `--pack` 分别控制依赖构建及组件打包，`--push <环境>` 和 `--upload <环境>` 控制推送及上传。不要将无参数运行视为只读检查：编排流程仍可能生成规格、清单并更新组件版本。某些脚本在解析帮助参数之前就加载 `.env`，查询行为时可直接阅读源码。

离线安装资源暂存目录可能仍叫 `costrict-static/`，与仓库维护的 `static/` 不同。`local-build.sh` 中仍存在旧路径引用，运行前核对；不要直接照搬旧文档的目录和选项。`--no-images` 也不保证整个安装包完全没有 nginx 等安装辅助镜像。

## 验证与工作约定

- 开始前检查 `git status --short`，保留已有未提交改动。
- JSON 配置改动用 `jq empty <文件>` 或 Python JSON 解析校验；部分现有文件带 UTF-8 BOM，Python 可使用 `utf-8-sig` 编码。
- Shell 改动用 `bash -n <脚本>` 检查语法；使用 `git diff --check` 检查新增空白问题。上游部分文件已有 CRLF/尾随空白，不要为无关任务批量格式化。
- 配置级修改优先静态校验及检查关联文件，不必为验证配置启动完整构建、Docker 服务或上传流程。
- 完整打包依操作需要 Bash、jq、Docker、smc、zip、rsync、SSH 等工具，以及外部源码或下载缓存。静态校验不能证明镜像标签存在或部署运行正常。
- `.env`、签名私钥及服务凭据只作为本地输入使用，不将具体值写入文档或日志。
- 根目录 `.gitignore` 采用白名单。新增需要版本管理的文件后使用 `git check-ignore` 检查，必要时增加精确放行项。
- 本文件只保留可复用的项目知识；不记录会话改动历史、临时 Git 状态、任务清单或用户操作流水。
