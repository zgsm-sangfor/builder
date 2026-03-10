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
    - [1. build-images.sh - Docker 镜像构建](#1-build-imagessh---docker-镜像构建)
    - [2. build-packages.sh - 部署包构建](#2-build-packagessh---部署包构建)
    - [3. build-costrict.sh - 完整构建](#3-build-costrictsh---完整构建)
    - [4. check-update.sh - 更新检测](#4-check-updatesh---更新检测)
    - [5. update-manifest.sh - 发布清单更新](#5-update-manifestsh---发布清单更新)
    - [6. start-local-site.sh - 本地测试站点](#6-start-local-sitesh---本地测试站点)
  - [📄 配置文件说明](#-配置文件说明)
    - [环境配置 (.env)](#环境配置-env)
    - [镜像配置 (images/\*.json)](#镜像配置-imagesjson)
    - [部署包配置 (builds/\*.json)](#部署包配置-buildsjson)
  - [📌 常见用例](#-常见用例)
    - [场景 1: 发布新版本](#场景-1-发布新版本)
    - [场景 2: 仅更新某个服务的配置](#场景-2-仅更新某个服务的配置)
    - [场景 3: 构建并推送 Docker 镜像](#场景-3-构建并推送-docker-镜像)
    - [场景 4: 本地测试](#场景-4-本地测试)
    - [场景 5: 检查哪些包需要更新](#场景-5-检查哪些包需要更新)
  - [❓ 常见问题](#-常见问题)
    - [Q1: 如何添加新的镜像构建配置？](#q1-如何添加新的镜像构建配置)
    - [Q2: 如何添加新的部署包？](#q2-如何添加新的部署包)
    - [Q3: 包上传到哪里？](#q3-包上传到哪里)
    - [Q4: 如何查看当前发布的模块版本？](#q4-如何查看当前发布的模块版本)
    - [Q5: checksum 变化时如何自动更新版本？](#q5-checksum-变化时如何自动更新版本)
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
./build-images.sh --build
./build-images.sh --build --push

# 步骤2: 检查更新并自动递增版本
./check-update.sh --update --packages backend,frontend

# 步骤3: 更新发布清单
./update-manifest.sh

# 步骤4: 构建部署包（可选上传）
./build-packages.sh --packages "backend,frontend,costrict-system" --def
./build-packages.sh --packages "backend,frontend,costrict-system" --def --upload def
```

---

## 📁 项目结构

```
builder/
├── build-images.sh          # Docker 镜像构建脚本
├── build-packages.sh        # 部署包构建脚本
├── build-costrict.sh        # 完整构建脚本（自动化流程）
├── check-update.sh          # 更新检测脚本
├── update-manifest.sh       # 发布清单更新脚本
├── start-local-site.sh      # 本地测试站点脚本
├── costrict-manifest.json   # CoStrict 组件清单模板
├── latest.json              # 包版本和 checksum 记录
│
├── images/                  # Docker 镜像配置目录
│   ├── casdoor.json
│   ├── chat-rag.json
│   └── ...
│
├── builds/                  # 部署包配置目录
│   ├── backend.json         # 后端部署包配置
│   ├── frontend.json        # 前端部署包配置
│   ├── costrict.json        # 完整系统配置
│   └── ...
│
├── configures/              # 配置文件目录
│   ├── common/              # 通用配置
│   │   ├── apisix/          # API 网关配置
│   │   ├── casdoor/         # 认证服务配置
│   │   ├── backend/         # 后端服务配置
│   │   └── ...
│   ├── darwin/              # macOS 配置
│   ├── linux/               # Linux 配置
│   └── windows/             # Windows 配置
│
└── site/                    # 本地测试站点
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

### 1. build-images.sh - Docker 镜像构建

**功能**：读取 `images/{package}.json` 配置，构建 Docker 镜像并推送到仓库

**用法**：
```bash
./build-images.sh [OPTIONS] [ACTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-p, --package <PACKAGE>` | 单个模块名 |
| `--packages <PACKAGES>` | 以逗号分隔的模块列表 (如 `"pkg1,pkg2,pkg3"`) |
| `-h, --help` | 帮助信息 |

**动作**：
| 动作 | 说明 |
|------|------|
| `--build` | 构建镜像 |
| `--push` | 推送镜像到仓库 |
| `--upload <ENV>` | 上传到指定环境，支持多个环境（逗号分隔）|

**环境说明**：
- 环境由 `.env` 中的 `DH_ENV_NAMES` 数组定义
- `def` - 默认环境（第一个环境）
- `all` - 所有环境
- 也可指定具体环境名，如 `test,prod`

**示例**：
```bash
# 构建单个模块的镜像
./build-images.sh --package casdoor --build

# 构建并推送到默认环境
./build-images.sh --package casdoor --build --push --upload def

# 构建多个模块并推送到多个环境
./build-images.sh --packages "casdoor,chat-rag" --build --upload test,prod

# 处理所有镜像
./build-images.sh --build --upload all
```

**配置文件**：[`images/*.json`](images/)

---

### 2. build-packages.sh - 部署包构建

**功能**：读取 `builds/{package}.json` 配置，构建 zip/exec/conf 类型包

**用法**：
```bash
./build-packages.sh [OPTIONS] [ACTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-p, --package <PACKAGE>` | 单个模块名 |
| `--packages <list>` | 以逗号分隔的模块列表 |
| `--type <type>` | 包类型过滤 (exec, conf, zip) |
| `--key <key>` | 私钥文件（默认: costrict-private.pem）|
| `-h, --help` | 帮助信息 |

**动作**：
| 动作 | 说明 |
|------|------|
| `--clean` | 清理构建产物 |
| `--build` | 构建包 |
| `--pack` | 打包 |
| `--index` | 构建索引 |
| `--def` | 执行默认步骤 (build + pack + index) |
| `--upload <env>` | 上传包到指定环境 |
| `--upload-packages <env>` | 仅上传 packages.json 到指定环境 |

**环境说明**：
- 环境由 `.env` 中的 `ENV_NAMES` 数组定义
- 支持与 build-images.sh 相同的环境关键字（def, all, 具体环境名）

**示例**：
```bash
# 构建单个包（执行完整流程）
./build-packages.sh --package backend --def

# 构建并上传到默认环境
./build-packages.sh --package backend --def --upload def

# 构建多个包并上传到多个环境
./build-packages.sh --packages "backend,frontend" --def --upload test,prod

# 仅上传 packages.json
./build-packages.sh --upload-packages def

# 仅构建指定类型的包
./build-packages.sh --type zip --def

# 使用自定义私钥签名
./build-packages.sh --package backend --def --key /path/to/private.pem
```

**配置文件**：[`builds/*.json`](builds/)

---

### 3. build-costrict.sh - 完整构建

**功能**：一键完成 CoStrict 完整版本的构建发布

**用法**：
```bash
./build-costrict.sh [选项]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `--push [env]` | 推送镜像到指定环境（会传递给 build-images.sh）。构建镜像始终执行，此选项只控制是否推送。如果 env 为空或 'def'，推送到 docker hub；否则推送到指定环境（如 'test,prod' 或 'all'）|
| `--upload <ENV>` | 指定包上传的环境（会传递给 build-packages.sh）|
| `--help, -h` | 显示帮助信息 |

**执行流程**：
1. 读取 `costrict-manifest.json` 获取组件列表
2. 调用 `build-images.sh` 构建镜像（可选推送）
3. 调用 `check-update.sh` 检测更新的模块
4. 调用 `update-manifest.sh` 更新 `manifest.json`
5. 调用 `build-packages.sh` 构建并上传

**示例**：
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

---

### 4. check-update.sh - 更新检测

**功能**：检测 builds 目录中包的版本和内容变化

**用法**：
```bash
./check-update.sh [OPTIONS]
```

**选项**：
| 选项 | 说明 |
|------|------|
| `-u, --update` | 当 checksum 变化时自动更新版本号（递增 patch） |
| `-p, --packages <list>` | 仅检查指定的包（逗号分隔） |
| `-v, --verbose` | 显示每个文件的 checksum 计算详情 |
| `-h, --help` | 帮助信息 |

**工作原理**：
- 遍历 `builds/` 目录中的 JSON 配置文件
- 计算包 `path` 所指目录的 CHECKSUM 和文件数
- 比较当前版本和 checksum 与 `latest.json` 中的记录
- 使用 `--update` 时自动递增包的 patch 版本号

**示例**：
```bash
# 检查所有包的更新状态
./check-update.sh

# 检查指定包并自动更新版本
./check-update.sh --update --packages backend,frontend

# 显示详细信息
./check-update.sh --verbose
```

---

### 5. update-manifest.sh - 发布清单更新

**功能**：以 `costrict-manifest.json` 为模板，补全组件版本信息

**用法**：
```bash
./update-manifest.sh
```

**无参数**

**输出**：`configures/common/costrict-system/manifest.json`

**工作原理**：
- 读取 `costrict-manifest.json` 获取组件列表
- 从 `builds/{name}.json` 读取各组件版本
- 生成完整的 manifest.json

---

### 6. start-local-site.sh - 本地测试站点

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

### 镜像配置 (images/*.json)

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

### 部署包配置 (builds/*.json)

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
./build-costrict.sh --upload prod
```

### 场景 2: 仅更新某个服务的配置

```bash
# 1. 修改配置文件
vim configures/common/casdoor/casdoor.yml

# 2. 检查更新并自动递增版本
./check-update.sh --update --packages casdoor

# 3. 重新构建并上传
./build-packages.sh --package casdoor --def --upload prod

# 4. 更新 manifest
./update-manifest.sh
```

### 场景 3: 构建并推送 Docker 镜像

```bash
# 构建单个镜像
./build-images.sh --package casdoor --build --upload prod

# 构建所有镜像
./build-images.sh --build --upload all
```

### 场景 4: 本地测试

```bash
# 启动本地包下载站点
./start-local-site.sh

# 然后设置 cloud 地址为 http://localhost
```

### 场景 5: 检查哪些包需要更新

```bash
# 查看所有包的变更状态
./check-update.sh --verbose

# 检查指定包
./check-update.sh --packages backend,frontend,casdoor
```

---

## ❓ 常见问题

### Q1: 如何添加新的镜像构建配置？

1. 在 [`images/`](images/) 目录创建 `{name}.json` 配置文件
2. 运行 `./build-images.sh --package {name} --build --upload def`

### Q2: 如何添加新的部署包？

1. 在 [`builds/`](builds/) 目录创建 `{name}.json` 配置文件
2. 在 [`configures/common/`](configures/common/) 目录创建对应配置文件
3. 运行 `./build-packages.sh --package {name} --def --upload def`

### Q3: 包上传到哪里？

- Docker 镜像 → 镜像仓库（由 `.env` 中的 `DH_ENV_*` 配置）
- 部署包 → Nginx 文件服务器（由 `.env` 中的 `ENV_*` 配置）

### Q4: 如何查看当前发布的模块版本？

```bash
# 查看构建配置中的版本
cat builds/backend.json | jq '.version'

# 查看生成的 manifest
cat configures/common/costrict-system/manifest.json

# 查看版本记录
cat latest.json
```

### Q5: checksum 变化时如何自动更新版本？

```bash
./check-update.sh --update
```

---

## 📚 相关文档

- [系统架构文档](arch.md) - 查看完整的模块依赖关系
- 各服务配置详见 [`configures/common/`](configures/common/) 目录

---

## 🔗 相关链接

- [Docker 官方文档](https://docs.docker.com/)
- [Docker Compose 文档](https://docs.docker.com/compose/)
