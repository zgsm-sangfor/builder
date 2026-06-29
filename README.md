# CoStrict 构建工程

> 📦 CoStrict 项目的自动化构建工具，用于构建 Docker 镜像、部署包、客户端程序等可发布产物

---

## 📋 目录

- [CoStrict 构建工程](#costrict-构建工程)
  - [📋 目录](#-目录)
  - [🚀 快速开始](#-快速开始)
    - [前置要求](#前置要求)
    - [一键完整构建](#一键完整构建)
    - [分步构建](#分步构建)
  - [📁 项目结构](#-项目结构)
  - [📦 包类型说明](#-包类型说明)
  - [🔧 打包工具详解](#-打包工具详解)
    - [1. build-depends - Docker 镜像构建](#1-build-depends---docker-镜像构建)
    - [2. build-components - 部署包构建](#2-build-components---部署包构建)
    - [3. build-costrict - 完整构建](#3-build-costrict---完整构建)
    - [4. check-update - 更新检测](#4-check-update---更新检测)
    - [5. check-packaged - 打包状态检测](#5-check-packaged---打包状态检测)
    - [6. gen-manifest - 发布清单更新](#6-gen-manifest---发布清单更新)
    - [7. gen-backend-spec - backend 子系统规格生成](#7-gen-backend-spec---backend-子系统规格生成)
    - [8. gen-component - 组件模块定义生成](#8-gen-component---组件模块定义生成)
    - [9. gen-depend - 依赖包定义生成](#9-gen-depend---依赖包定义生成)
    - [10. start-local-site - 本地测试站点](#10-start-local-site---本地测试站点)
  - [📄 配置文件说明](#-配置文件说明)
    - [环境配置 (.env)](#环境配置-env)
    - [构建依赖的配置 (depends)](#构建依赖的配置-depends)
    - [部署包配置 (components)](#部署包配置-components)
  - [📌 常见用例](#-常见用例)
    - [场景 1: 发布新版本](#场景-1-发布新版本)
    - [场景 2: 仅更新某个服务的配置](#场景-2-仅更新某个服务的配置)
    - [场景 3: 构建并推送 Docker 镜像](#场景-3-构建并推送-docker-镜像)
    - [场景 4: 本地测试](#场景-4-本地测试)
    - [场景 5: 检查哪些包需要更新](#场景-5-检查哪些包需要更新)
    - [场景 6: 快速创建新模块](#场景-6-快速创建新模块)
  - [❓ 常见问题](#-常见问题)
    - [Q1: 如何添加新的镜像构建配置？](#q1-如何添加新的镜像构建配置)
    - [Q2: 如何添加新的部署包？](#q2-如何添加新的部署包)
    - [Q3: 包上传到哪里？](#q3-包上传到哪里)
    - [Q4: 如何查看当前发布的模块版本？](#q4-如何查看当前发布的模块版本)
    - [Q5: checksum 变化时如何自动更新版本？](#q5-checksum-变化时如何自动更新版本)
    - [Q6: 如何跳过依赖构建，只构建组件包？](#q6-如何跳过依赖构建只构建组件包)
  - [📚 相关文档](#-相关文档)
  - [🔗 相关链接](#-相关链接)

---

## 🚀 快速开始

### 前置要求

- Docker 已安装并运行
- Bash 环境（Linux/macOS 或 WSL）
- 有镜像仓库的推送权限
- smc 命令在 PATH 中（`/root/.costrict/bin`）

### 一键完整构建

```bash
# 构建镜像（不推送），然后构建包
./build-costrict.sh

# 构建镜像并推送到 docker hub
./build-costrict.sh --push

# 构建镜像并推送到 test 和 prod 环境
./build-costrict.sh --push test,prod

# 构建包并上传到默认环境
./build-costrict.sh --upload def

# 完整构建：推送镜像到所有环境，上传包到 prod
./build-costrict.sh --push all --upload prod
```

### 分步构建

```bash
# 步骤1: 构建 Docker 镜像（可选推送）
./build-depends.sh --build
./build-depends.sh --build --push

# 步骤2: 检查镜像是否已构建，列出待构建列表
./check-packaged.sh --build-type dependency

# 步骤3: 检查更新并自动递增依赖包版本
./check-update.sh --update --build-type dependency

# 步骤4: 更新 backend 子系统规格
./gen-backend-spec.sh

# 步骤5: 检查更新并自动递增组件包版本
./check-update.sh --update --build-type component

# 步骤6: 更新发布清单
./gen-manifest.sh

# 步骤7: 构建部署包（可选上传）
./build-components.sh --packages "backend,frontend,costrict-system" --def
./build-components.sh --packages "backend,frontend,costrict-system" --def --upload def
```

---

## 📁 项目结构

```
builder/
├── build-depends.sh          # Docker 镜像构建脚本
├── build-components.sh       # 部署包构建脚本
├── build-costrict.sh         # 完整构建脚本（自动化流程）
├── check-update.sh           # 更新检测与版本递增脚本
├── check-packaged.sh         # 已打包/已构建状态检测脚本
├── gen-manifest.sh           # 发布清单更新脚本
├── gen-backend-spec.sh       # backend 子系统规格生成脚本
├── gen-component.sh          # 组件模块定义生成脚本
├── gen-depend.sh             # 依赖包定义生成脚本
├── start-local-site.sh       # 本地测试站点脚本
├── costrict-manifest.json    # CoStrict 组件清单模板
├── costrict-backend-spec.json # backend 子系统规格模板
├── packages.json             # 包列表索引
├── latest.json               # 包版本和 checksum 记录
│
├── depends/                  # Docker 镜像配置目录
│   ├── casdoor.json
│   ├── chat-rag.json
│   └── ...
│
├── components/               # 部署包配置目录
│   ├── backend.json          # 后端部署包配置
│   ├── frontend.json         # 前端部署包配置
│   ├── costrict.json         # 完整系统配置
│   └── ...
│
├── configures/               # 配置文件目录
│   ├── common/               # 通用配置
│   │   ├── apisix/           # API 网关配置
│   │   ├── casdoor/          # 认证服务配置
│   │   ├── backend/          # 后端服务配置
│   │   └── ...
│   ├── darwin/               # macOS 配置
│   ├── linux/                # Linux 配置
│   └── windows/              # Windows 配置
│
├── packages/                 # 构建产物输出目录
│   └── {package}/
│       └── {os}/{arch}/{ver}/
│
└── site/                     # 本地测试站点
    ├── docker-compose.yml
    └── nginx.conf
```

---

## 📦 包类型说明

| 包类型 | 后缀 | 说明 | 用途 |
|--------|------|------|------|
| **Docker 镜像** | - | 容器镜像 | 推送到镜像仓库，供部署拉取 |
| **Docker-Compose 包** | `.zip` | Compose 部署文件 | 私有化部署包 |
| **K8s 包** | `.zip` | Kubernetes 部署文件 | K8s 集群部署 |
| **客户端程序包** | `.exec` | 可执行程序 | 客户端工具下载 |
| **客户端配置包** | `.conf` | 配置文件 | 客户端配置更新 |

---

## 🔧 打包工具详解

### 1. build-depends - Docker 镜像构建

**功能**：读取 `depends/{package}.json` 配置，构建 Docker 镜像并推送到仓库

**用法**：
```bash
./build-depends.sh [OPTIONS] [ACTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-p, --packages <PACKAGES>` | 以逗号分隔的模块列表 (如 `"pkg1,pkg2,pkg3"`) |
| `-h, --help` | 帮助信息 |

**动作**：
| 动作 | 说明 |
|------|------|
| `--build` | 构建镜像 |
| `--update` | 使用构建好的依赖更新组件配置（如 image.env）|
| `--push [<ENV>]` | 推送镜像。如果 ENV 为空或包含 `def`，推送到 docker hub；否则推送到指定环境（逗号分隔），如 `test,prod` |

**环境说明**：
- 推送目标环境由 `.env` 中的 `DH_ENV_NAMES` 数组定义
- `def` - 推送到 docker hub
- `all` - 推送到所有环境
- 也可指定具体环境名，如 `test,prod`

**示例**：
```bash
# 构建单个模块的镜像
./build-depends.sh --packages casdoor --build

# 构建并推送到 docker hub
./build-depends.sh --packages casdoor --build --push

# 构建多个模块并推送到多个环境
./build-depends.sh --packages "casdoor,chat-rag" --build --push test,prod

# 构建并更新组件配置，再推送到所有环境
./build-depends.sh --packages casdoor --build --update --push all

# 处理所有镜像
./build-depends.sh --build --push all
```

**配置文件**：[`depends/*.json`](depends/)

---

### 2. build-components - 部署包构建

**功能**：读取 `components/{package}.json` 配置，构建 zip/exec/conf 类型包

**用法**：
```bash
./build-components.sh [OPTIONS] [ACTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-p, --packages <list>` | 以逗号分隔的模块列表 |
| `--type <type>` | 包类型过滤 (exec, conf, zip) |
| `--key <key>` | 私钥文件（默认: costrict-private.pem）|
| `-h, --help` | 帮助信息 |

**动作**：
| 动作 | 说明 |
|------|------|
| `--clean` | 清理早期版本 |
| `--build` | 构建包 |
| `--pack` | 打包并签名 |
| `--index` | 构建索引 |
| `--def` | 执行默认步骤 (build + pack + index) |
| `--upload <env>` | 上传包到指定环境 |
| `--upload-packages <env>` | 仅上传 packages.json 到指定环境 |

**环境说明**：
- 环境由 `.env` 中的 `ENV_NAMES` 数组定义
- `def` - 默认环境（第一个环境）
- `all` - 所有环境
- 支持逗号分隔的多个环境，如 `test,prod`

**示例**：
```bash
# 构建单个包（执行完整流程）
./build-components.sh --packages backend --def

# 构建并上传到默认环境
./build-components.sh --packages backend --def --upload def

# 构建多个包并上传到多个环境
./build-components.sh --packages "backend,frontend" --def --upload test,prod

# 仅上传 packages.json
./build-components.sh --upload-packages def

# 仅构建指定类型的包
./build-components.sh --type zip --def

# 使用自定义私钥签名
./build-components.sh --packages backend --def --key /path/to/private.pem
```

**配置文件**：[`components/*.json`](components/)

---

### 3. build-costrict - 完整构建

**功能**：一键完成 CoStrict 完整版本的构建发布

**用法**：
```bash
./build-costrict.sh [选项]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `--push [env]` | 推送镜像到指定环境（会传递给 build-depends.sh）。构建镜像始终执行，此选项只控制是否推送。如果 env 为空或 'def'，推送到 docker hub；否则推送到指定环境（如 'test,prod' 或 'all'）|
| `--upload <ENV>` | 指定包上传的环境（会传递给 build-components.sh）|
| `--skip-depend` | 跳过依赖处理（Step 1 和 Step 2），不处理 dependency 包 |
| `--help, -h` | 显示帮助信息 |

**执行流程**：
1. 调用 [`check-update.sh`](check-update.sh:1) 自动递增 dependency 包的版本号
2. 调用 [`check-packaged.sh`](check-packaged.sh:1) 检查尚未构建的 dependency 包，若有则调用 [`build-depends.sh`](build-depends.sh:1) 构建
3. 调用 [`gen-backend-spec.sh`](gen-backend-spec.sh:1) 更新 `backend/system-spec.json`
4. 调用 [`check-update.sh`](check-update.sh:1) 自动递增 component 包的版本号
5. 调用 [`gen-manifest.sh`](gen-manifest.sh:1) 更新 manifest，并重新检查 costrict-system 版本
6. 调用 [`check-packaged.sh`](check-packaged.sh:1) 检查尚未打包的 component 包，若有则调用 [`build-components.sh`](build-components.sh:1) 构建

**示例**：
```bash
# 构建镜像（不推送），然后构建包
./build-costrict.sh

# 构建镜像并推送到 docker hub
./build-costrict.sh --push

# 构建镜像并推送到 test 和 prod 环境
./build-costrict.sh --push test,prod

# 构建包并上传到 prod 环境
./build-costrict.sh --upload prod

# 完整构建：推送镜像到所有环境，上传包到 prod
./build-costrict.sh --push all --upload prod

# 跳过依赖处理，仅构建组件包
./build-costrict.sh --skip-depend --upload def
```

---

### 4. check-update - 更新检测

**功能**：检测 `components/` 或 `depends/` 目录中包的版本和内容变化，支持自动递增版本号

**用法**：
```bash
./check-update.sh [OPTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-t, --build-type <TYPE>` | 检测类型：`component`（默认，检测 components 目录）或 `dependency`（检测 depends 目录）|
| `-u, --update` | 当 checksum 变化时自动更新版本号（递增 patch） |
| `-p, --packages <list>` | 仅检查指定的包（逗号分隔） |
| `-v, --verbose` | 显示每个文件的 checksum 计算详情 |
| `-h, --help` | 帮助信息 |

**工作原理**：
- 遍历 `components/` 或 `depends/` 目录中的 JSON 配置文件（由 `--build-type` 指定）
- 计算包 `path` 所指目录的 CHECKSUM 和文件数
- 比较当前版本和 checksum 与 `latest.json` 中的记录
- 使用 `--update` 时自动递增包的 patch 版本号

**示例**：
```bash
# 检查所有组件包的更新状态
./check-update.sh

# 检查依赖包的更新状态
./check-update.sh --build-type dependency

# 检查指定包并自动更新版本
./check-update.sh --update --packages backend,frontend

# 自动更新依赖包版本
./check-update.sh --update --build-type dependency

# 显示详细信息
./check-update.sh --verbose
```

---

### 5. check-packaged - 打包状态检测

**功能**：检测组件包或依赖包的版本是否已经构建/打包完成，输出尚未构建的模块列表

**用法**：
```bash
./check-packaged.sh [OPTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-t, --build-type <TYPE>` | 检测类型：`component`（默认，检测 components 目录）或 `dependency`（检测 depends 目录）|
| `-p, --packages <list>` | 仅检查指定的包（逗号分隔） |
| `-v, --verbose` | 显示每个平台的详细检查信息 |
| `-h, --help` | 帮助信息 |

**工作原理**：
- **component 模式**：遍历 `components/` 目录的 JSON 配置，检查 `packages/{name}/{os}/{arch}/{version}/` 目录下是否存在构建产物
- **dependency 模式**：遍历 `depends/` 目录的 JSON 配置，检查 `images/{name}/versions.json` 中是否记录了对应版本

**示例**：
```bash
# 检查所有组件包是否已打包
./check-packaged.sh

# 检查依赖包是否已构建
./check-packaged.sh --build-type dependency

# 检查指定包
./check-packaged.sh --packages backend,frontend

# 详细模式
./check-packaged.sh --verbose
```

---

### 6. gen-manifest - 发布清单更新

**功能**：以 [`costrict-manifest.json`](costrict-manifest.json:1) 为模板，扫描 `components/` 目录补全组件版本信息

**用法**：
```bash
./gen-manifest.sh
```

**无参数**

**输出**：`configures/common/costrict-system/manifest.json`

**工作原理**：
- 遍历 `components/*.json`，提取每个已启用的模块的 `name`、`subsystem`、`version` 字段
- 排除 `costrict-system` 自身
- 替换模板中的 components 数组，生成完整的 manifest.json

---

### 7. gen-backend-spec - backend 子系统规格生成

**功能**：扫描 `components/` 和 `configures/common/*/services.json`，自动生成 backend 子系统规格文件

**用法**：
```bash
./gen-backend-spec.sh
```

**无参数**

**输出**：`configures/common/backend/system-spec.json`

**工作原理**：
- 扫描 `components/` 目录，筛选出 `enabled` 且 `subsystem=backend` 的模块，提取 components 数组
- 扫描 `configures/common/*/services.json`，聚合所有已启用模块的 services 定义
- 以 [`costrict-backend-spec.json`](costrict-backend-spec.json:1) 为模板输出完整的 system-spec.json

---

### 8. gen-component - 组件模块定义生成

**功能**：创建可被 [`build-components.sh`](build-components.sh:1) 构建的组件模块定义，同时生成源目录骨架与待构建元件

**用法**：
```bash
./gen-component.sh [OPTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `--name <NAME>` | 组件名（必填）。决定输出文件名 `components/<NAME>.json` |
| `--type <TYPE>` | 组件类型：`zip`（默认）/ `conf` / `exec` |
| `--path <PATH>` | 源目录（默认按 type 推导） |
| `--version <VERSION>` | 版本号（默认：1.0.0） |
| `--platforms <SPEC>` | 平台规格，逗号分隔（如 `linux/amd64,windows/amd64`） |
| `--subsystem <SUBSYSTEM>` | 所属子系统（默认：backend） |
| `--description <DESC>` | 描述信息 |
| `--disabled` | 将 enabled 置为 false |
| `--no-scaffold` | 仅生成 JSON，不创建目录骨架 |
| `--force` | 覆盖已存在的文件 |
| `-h, --help` | 帮助信息 |

**示例**：
```bash
# 生成一个 zip 组件
./gen-component.sh --name my-pkg

# 生成一个 conf 配置组件
./gen-component.sh --name my-config --type conf

# 生成一个 exec 可执行组件
./gen-component.sh --name my-app --type exec

# 指定多平台与版本
./gen-component.sh --name my-app --version 2.1.0 --platforms linux/amd64,linux/arm64,darwin/arm64
```

---

### 9. gen-depend - 依赖包定义生成

**功能**：创建可被 [`build-depends.sh`](build-depends.sh:1) 构建的依赖包定义文件（`depends/<NAME>.json`）

**用法**：
```bash
./gen-depend.sh [OPTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `--name <NAME>` | 模块名（必填）。决定输出文件名 `depends/<NAME>.json` |
| `--path <PATH>` | 构建镜像时的工作路径（必填） |
| `--version <VERSION>` | 版本号（默认：1.0.0） |
| `--repo <REPO>` | Docker Hub 仓库名（默认：zgsm） |
| `--type <TYPE>` | 依赖类型：`exec`（默认）/ `frontend` |
| `--tag <TAG>` | 镜像标签模板（exec 默认：v{{.version}}） |
| `--command <COMMAND>` | 构建命令模板（默认按 type 自动生成） |
| `--description <DESC>` | 描述信息 |
| `--disabled` | 将 enabled 置为 false |
| `--force` | 覆盖已存在的定义文件 |
| `-h, --help` | 帮助信息 |

**示例**：
```bash
# 生成一个 Docker 镜像依赖定义
./gen-depend.sh --name my-service --version 1.0.0 --path ../../services/my-service

# 生成一个前端类型依赖定义
./gen-depend.sh --name my-frontend --version 1.0.0 --path ../../my-frontend --type frontend
```

---

### 10. start-local-site - 本地测试站点

**功能**：启动本地 nginx 容器，构建可供下载包的测试站点

**用法**：
```bash
./start-local-site.sh
```

**无参数**

**使用方式**：
- 设置 cloud 地址为 `http://localhost` 即可通过该站点更新软件

---

## 📄 配置文件说明

### 环境配置 (.env)

```bash
# Docker 镜像上传环境
declare -a DH_ENV_NAMES=("test" "prod")
declare -a DH_ENV_URLS=(...)
declare -a DH_ENV_USERS=(...)
declare -a DH_ENV_PASSWORDS=(...)

# 包上传环境
declare -a ENV_NAMES=("test" "prod")
declare -a ENV_HOSTS=(...)
declare -a ENV_PORTS=(...)
declare -a ENV_PATHS=(...)
```

### 构建依赖的配置 (depends)

```json
{
  "name": "costrict-admin-backend",
  "repo": "zgsm",
  "version": "1.0.43",
  "path": "../costrict-admin/backend",
  "command": "docker build --build-arg VERSION={{ .version }} . -t {{ .repo }}/{{ .name }}:{{ .tag }}",
  "tag": "{{ .version }}",
  "description": "The back-end docker-service of costrict"
}
```

**字段说明**：
| 字段 | 必填 | 说明 |
|------|------|------|
| name | ✓ | 模块名 |
| repo | ✓ | 镜像仓库名 |
| version | | 镜像版本 |
| path | | 构建时的工作路径 |
| command | | 构建命令（支持模板语法） |
| tag | | 镜像标签（默认为 version） |
| description | | 镜像描述 |

### 部署包配置 (components)

```json
{
  "name": "backend",
  "version": "1.0.0",
  "type": "zip",
  "path": "configures/common/backend",
  "os": ["linux"],
  "arch": ["amd64", "arm64"]
}
```

---

## 📌 常见用例

### 场景 1: 发布新版本

```bash
# 完整自动化发布
./build-costrict.sh --push all --upload prod
```

### 场景 2: 仅更新某个服务的配置

```bash
# 1. 修改配置文件
vim configures/common/casdoor/casdoor.yml

# 2. 检查更新并自动递增版本
./check-update.sh --update --packages casdoor

# 3. 重新构建并上传
./build-components.sh --packages casdoor --def --upload prod

# 4. 更新 manifest
./gen-manifest.sh
```

### 场景 3: 构建并推送 Docker 镜像

```bash
# 构建单个镜像并推送到 docker hub
./build-depends.sh --packages casdoor --build --push

# 构建所有镜像并推送到所有环境
./build-depends.sh --build --push all
```

### 场景 4: 本地测试

```bash
# 启动本地包下载站点
./start-local-site.sh

# 然后设置 cloud 地址为 http://localhost
```

### 场景 5: 检查哪些包需要更新

```bash
# 查看所有组件包的变更状态
./check-update.sh --verbose

# 查看依赖包的变更状态
./check-update.sh --build-type dependency --verbose

# 检查指定包
./check-update.sh --packages backend,frontend,casdoor
```

### 场景 6: 快速创建新模块

```bash
# 创建新的组件模块定义（zip 类型）
./gen-component.sh --name my-service --description "My new service"

# 创建新的 Docker 镜像依赖定义
./gen-depend.sh --name my-image --version 1.0.0 --path ../../services/my-image

# 然后手动编辑配置文件后正常构建
```

---

## ❓ 常见问题

### Q1: 如何添加新的镜像构建配置？

1. 使用 [`gen-depend.sh`](gen-depend.sh:1) 快速生成：`./gen-depend.sh --name {name} --path {path} --version {ver}`
2. 或手动在 [`depends/`](depends/) 目录创建 `{name}.json` 配置文件
3. 运行 `./build-depends.sh --packages {name} --build --push`

### Q2: 如何添加新的部署包？

1. 使用 [`gen-component.sh`](gen-component.sh:1) 快速生成：`./gen-component.sh --name {name}`
2. 或手动在 [`components/`](components/) 目录创建 `{name}.json` 配置文件
3. 在 [`configures/common/`](configures/common/) 目录创建对应配置文件
4. 运行 `./build-components.sh --packages {name} --def --upload def`

### Q3: 包上传到哪里？

- Docker 镜像 → 镜像仓库（由 `.env` 中的 `DH_ENV_*` 配置）
- 部署包 → Nginx 文件服务器（由 `.env` 中的 `ENV_*` 配置）

### Q4: 如何查看当前发布的模块版本？

```bash
# 查看构建配置中的版本
cat components/backend.json | jq '.version'

# 查看生成的 manifest
cat configures/common/costrict-system/manifest.json

# 查看版本记录
cat latest.json
```

### Q5: checksum 变化时如何自动更新版本？

```bash
# 更新组件包版本
./check-update.sh --update

# 更新依赖包版本
./check-update.sh --update --build-type dependency
```

### Q6: 如何跳过依赖构建，只构建组件包？

```bash
./build-costrict.sh --skip-depend --upload def
```

---

## 📚 相关文档

- [模块开发指南](developer.md) - 查看完整的模块开发流程
- 各服务配置详见 [`configures/common/`](configures/common/) 目录

---

## 🔗 相关链接

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
