# CoStrict 模块开发指南

本文档为模块开发人员提供详细的指导，说明如何在 CoStrict 系统中创建和发布新的应用模块。

## 目录

1. [系统概述](#系统概述)
2. [应用类型](#应用类型)
3. [发布包类型](#发布包类型)
4. [发布包类型详细说明](#发布包类型详细说明)
5. [开发流程](#开发流程)
6. [配置文件详解](#配置文件详解)
7. [高级机制](#高级机制)
8. [构建和发布](#构建和发布)
9. [最佳实践](#最佳实践)
10. [常见问题](#常见问题)

---

## 系统概述

CoStrict 包管理系统采用模块化设计，支持多种类型的应用组件。每个模块通过配置文件定义其构建方式、依赖关系和发布流程。

### 核心构建脚本

- **build-components.sh**: 构建应用组件包
- **build-depends.sh**: 构建依赖（Docker镜像）
- **gen-manifest.sh**: 更新系统清单文件

### 包管理系统目录结构

```
builder/
├── components/          # 应用组件定义
│   └── {package}.json  # 应用组件的定义文件
├── depends/           # 依赖组件定义
│   └── {package}.json # 依赖组件的定义文件
├── configures/        # 应用配置文件
│   └── {package}/     # 每个应用的配置目录
├── packages/          # 构建产物输出目录
│   └── {package}/
│       └── {os}/
│           └── {arch}/
│               └── {ver}/
├── build-components.sh
├── build-depends.sh
└── gen-manifest.sh
```

---

## 应用类型

CoStrict 系统中的应用主要分为两种类型：客户端应用和服务端应用

### 1. 客户端应用

**适用场景**: 需要编译的可执行程序，如桌面应用、命令行工具等

**特点**:

- 需要跨平台编译（Windows/Linux/macOS）
- 支持多种架构（amd64/arm64）
- 通过 build.py 脚本进行构建

客户端应用一般由“客户端应用包”和若干个“配置数据包”构成。

### 2. 服务端应用

**适用场景**: Docker 容器化应用、配置包、Web 应用等

**特点**:

- 服务端应用的主体，是一个应用包（即zip格式的包），包含Docker Compose配置，配置数据文件，环境变量，模板文件，前端脚本等
- 依赖的Docker镜像，或前端脚本，可以通过“依赖包”机制构建
- 依赖的配置文件，可以直接嵌入到应用包中，也可以通过“配置数据包”构建和发布

服务端应用一般由若干“服务端应用包”和“依赖包”，“配置数据包”构成。

## 发布包类型

CoStrict 发布包分为两个大类，共5种类型：

### 类型1: 依赖包

#### 1. Docker镜像包

- 由 [`depends/`](depends/) 目录定义
- 使用 [`build-depends.sh`](build-depends.sh:1) 构建
- 支持 Docker 镜像的自动构建和发布

#### 2. 前端构建包

- 静态前端资源打包
- 通常包含 HTML/CSS/JS 文件

### 类型2: 应用包

#### 1. 客户端应用包 (type: exec)

- 需要编译的可执行程序
- 支持跨平台构建

#### 2. 服务端应用包 (type: zip)

- Docker 容器化应用
- 包含配置文件和部署脚本

#### 3. 配置数据包 (type: conf)

- 纯配置文件或数据文件
- 用于系统配置更新

## 发布包类型详细说明

CoStrict 系统中的应用主要分为两种类型：客户端应用和服务端应用

### 1. 应用包-客户端应用包 (type: exec)

客户端应用包定义在`components/`目录下。

**适用场景**: 需要编译的可执行程序，如桌面应用、命令行工具等

**特点**:

- 需要跨平台编译（Windows/Linux/macOS）
- 支持多种架构（amd64/arm64）
- 通过 build.py 脚本进行构建

**示例**: [`completion-agent.json`](components/completion-agent.json:1)

```json
{
  "name": "completion-agent",
  "type": "exec",
  "path": "../../middles/completion-agent",
  "version": "1.0.21",
  "platforms": [
    {"os": "windows", "arch": "amd64"},
    {"os": "linux", "arch": "amd64"},
    {"os": "linux", "arch": "arm64"},
    {"os": "darwin", "arch": "amd64"},
    {"os": "darwin", "arch": "arm64"}
  ],
  "enabled": false,
  "description": "Client agent for code completion"
}
```

**字段说明**:

- `name`: 应用名称（必填）
- `type`: 固定值为 "exec"（必填）
- `path`: 源码目录路径（必填）
- `version`: 应用版本号（必填）
- `platforms`: 支持的平台和架构列表（必填）
  - `os`: 操作系统（windows/linux/darwin）
  - `arch`: 架构（amd64/arm64）
- `enabled`: 是否启用该模块（可选，默认true）
- `description`: 应用描述（可选）

### 2. 应用包-服务端应用包 (type: zip)

服务端应用包定义在`components/`目录下。

**适用场景**: Docker 容器化应用、配置包、Web 应用等

**特点**:

- 将配置文件打包为 zip 压缩包
- 可以包含 Docker Compose 配置
- 支持环境变量和模板文件

**示例**: [`backend.json`](components/backend.json:1)

```json
{
  "name": "backend",
  "type": "zip",
  "path": "./configures",
  "version": "1.0.43",
  "description": "Backend Subsystem Definition File"
}
```

**字段说明**:

- `name`: 应用名称（必填）
- `type`: 固定值为 "zip"（必填）
- `path`: 打包源目录（必填，通常是 ./configures/{package}）
- `version`: 应用版本号（必填）
- `description`: 应用描述（可选）

### 3. 应用包-配置数据包 (type: conf)

配置数据包定义在`components/`目录下。

**适用场景**: 纯配置文件或数据文件的发布

**特点**:

- 不包含可执行代码
- 仅用于更新系统配置或数据
- 可以独立更新配置而不影响应用代码

**示例**: [`components/completion-config.json`](components/completion-config.json:1)

```json
{
  "name": "completion-config",
  "type": "conf",
  "path": "./configures/common",
  "version": "1.0.5",
  "description": "Configuration package for code completion"
}
```

**字段说明**:

- `name`: 配置包名称（必填）
- `type`: 固定值为 "conf"（必填）
- `path`: 配置文件所在目录（必填）
- `version`: 配置版本号（必填）
- `description`: 配置包描述（可选）

### 4. 依赖包-Docker镜像包 (type: exec)

Docker镜像包定义在`depends/`目录下。

**适用场景**: 需要自定义构建的 Docker 镜像

**特点**:

- 定义 Docker 镜像的构建过程
- 支持自动推送到镜像仓库
- 可以生成应用配置中的镜像地址

**示例**: [`depends/client-manager.json`](depends/client-manager.json:1)

### 5. 依赖包-前端构建包 (type: frontend)

前端构建包定义在`depends/`目录下。

**适用场景**: 静态前端资源的打包和发布

**特点**:

- 包含编译后的前端资源（HTML/CSS/JS）
- 编译后内容会拷贝到zip包的目录，后续可打包成后端应用包，部署到docker compose的nginx服务器中
- 支持版本管理和更新

```json
{
  "name": "costrict-admin-frontend",
  "version": "1.0.51",
  "type": "frontend",
  "path": "../../costrict-admin/frontend",
  "command": "bash build.sh",
  "enabled": true,
  "excludes": [
    "*/dist/*",
    "*/.git/*",
    "*/node_modules/*"
  ],
  "component": {
    "workdir": "../../costrict-admin/frontend",
    "command": "bash publish.sh"
  },
  "description": "Build the front-end page to be released for the costrict system."
}
```

**字段说明**:

- `name`: 前端包名称（必填）
- `version`: 前端包版本（必填）
- `type`: 构建类型（必填，前端构建包的类型为 "frontend"）
- `path`: 前端源代码目录（必填）
- `command`: 构建命令（必填，用于编译前端资源）
- `enabled`: 是否启用该模块（可选，默认为true）
- `excludes`: 排除的文件/目录列表（可选，用于排除不需要打包的文件）
- `component`: 构建后的处理
  - `workdir`: 工作目录
  - `command`: 发布命令，用于将构建产物拷贝到目标目录
- `description`: 描述（可选）

上述配置的前端依赖包，编译打包后，会将打包后的前端文件拷贝到./../costrict-admin/frontend目录下。
后续构建costrict-admin-frontend模块时，会将其打入zip类型的包中。

**示例**: [`components/costrict-admin-frontend.json`](components/costrict-admin-frontend.json:1)

```json
{
  "name": "costrict-admin-frontend",
  "type": "zip",
  "path": "./configures/common/costrict-admin-frontend",
  "version": "1.0.20",
  "description": "CoStrict Admin Frontend Application"
}
```

---

## 开发流程

### 完整开发流程图

```
1. 创建应用配置
   ↓
2. 准备源代码和配置文件
   ↓
3. 构建依赖（如需要）
   ↓
4. 构建应用组件
   ↓
5. 更新系统清单
   ↓
6. 测试和发布
```

### 步骤详解

#### 步骤 1: 创建应用配置

根据应用类型，创建相应的配置文件：

**客户端应用**: 在 [`components/`](components/) 目录创建 `{package}.json`

**服务端应用**: 在 [`components/`](components/) 目录创建 `{package}.json`

**依赖镜像**: 在 [`depends/`](depends/) 目录创建 `{package}.json`

#### 步骤 2: 准备源代码和配置文件

**客户端应用**:

- 确保源代码目录存在（由 `path` 字段指定）
- 确保存在 `build.py` 脚本（用于跨平台编译）
- `build.py` 应接受以下参数：
  - `--software`: 软件版本
  - `--os`: 目标操作系统
  - `--arch`: 目标架构
  - `--output`: 输出文件路径

**服务端应用**:

- 在 [`configures/{package}/`](configures/) 目录准备配置文件
- 包含必要的 Docker Compose 文件
- 配置环境变量文件（见[配置文件详解](#配置文件详解)）

**依赖镜像**:

- 确保 Dockerfile 存在于指定目录
- 确保构建环境可用

#### 步骤 3: 构建依赖（如需要）

如果应用依赖自定义构建的 Docker 镜像：

```bash
# 构建依赖镜像
./build-depends.sh --build -p {package}

# 推送到 Docker Hub
./build-depends.sh --push -p {package}

# 或推送到指定环境
./build-depends.sh --push test,prod -p {package}
```

#### 步骤 4: 构建应用组件

```bash
# 执行默认流程（更新、构建、打包、索引）
./build-components.sh --def -p {package}

# 或分步执行
./build-components.sh --update -p {package}   # 更新版本
./build-components.sh --build -p {package}    # 构建
./build-components.sh --pack -p {package}     # 打包
./build-components.sh --index -p {package}   # 创建索引
```

#### 步骤 5: 更新系统清单

新增模块需要在`costrict-manifest.json`添加模块定义。

然后调用`gen-manifest.sh`生成costrict系统的描述文件`configures/common/costrict-system/manifest.json`。

```bash
./gen-manifest.sh
```

此脚本会：

1. 读取 [`costrict-manifest.json`](costrict-manifest.json:1) 模板
2. 从 [`components/`](components/) 目录收集各组件版本
3. 生成 [`configures/common/costrict-system/manifest.json`](configures/common/costrict-system/manifest.json:1)

#### 步骤 6: 测试和发布

```bash
# 上传到指定环境
./build-components.sh --upload test,prod -p {package}

# 上传所有环境
./build-components.sh --upload all -p {package}

# 更新包列表
./build-components.sh --upload-packages test,prod
```

---

## 配置文件详解

### 应用配置目录结构

每个服务端应用的配置文件位于 [`configures/{package}/`](configures/) 目录：

```
configures/
└── {package}/
    ├── {package}.yml              # Docker Compose 配置
    ├── image.env                  # 镜像地址变量
    ├── port.env                   # 端口配置变量
    ├── app.env                    # 应用配置变量
    ├── config.yaml.tpl            # 模板配置文件
    ├── MANIFEST                   # 安装清单（可选）
    └── deploy.sh                  # 自定义安装脚本（可选）
```

**应用配置的两种方式**:

1. **集成配置包**: 配置文件直接包含在应用发布包中
   - 优点: 部署简单，配置和代码版本同步
   - 适用: 配置相对稳定的应用

2. **独立配置包**: 配置作为独立的包进行发布
   - 优点: 配置可以独立更新，不影响应用代码
   - 适用: 需要频繁调整配置的场景
   - 实现: 创建 `type: "conf"` 的配置包

### 环境变量文件

#### 1. image.env

定义应用依赖的 Docker 镜像地址。

**示例**: [`configures/common/apisix/image.env`](configures/common/apisix/image.env:1)

```bash
IMAGE_APISIX=apache/apisix:3.9.1-debian
```

#### 2. port.env

定义应用使用的端口号。

**示例**: [`configures/common/apisix/port.env`](configures/common/apisix/port.env:1)

```bash
PORT_APISIX_API="39180"
PORT_APISIX_ENTRY="39080"
```

#### 3. app.env

定义应用的其他配置变量。

```bash
APP_DEBUG=false
APP_TIMEOUT=30
```

**变量命名规范**:

- 镜像变量: `IMAGE_{APP_NAME}`
- 端口变量: `PORT_{APP_NAME}_{SERVICE}`
- 其他变量: `APP_{VAR_NAME}` 或自定义前缀

### 模板文件

后缀为 `.tpl` 的文件是模板文件，在安装过程中会被实例化为最终配置文件。

**模板语法**:

- 使用 Go template 语法
- 可以引用 `.env` 中定义的任何变量
- 变量引用格式: `{{ .VARIABLE_NAME }}`

**示例**: [`configures/common/apisix/config.yaml.tpl`](configures/common/apisix/config.yaml.tpl:1)

```yaml
apisix:
  node_listen: {{ .PORT_APISIX_ENTRY }}
  admin_api:
    port: {{ .PORT_APISIX_API }}
```

安装后生成 `config.yaml`:

```yaml
apisix:
  node_listen: 39080
  admin_api:
    port: 39180
```

### MANIFEST 文件

用于精确控制文件安装位置。

**格式**: 每行一个文件映射规则

```
src/file1.yml dst/file1.yml
src/config.tpl dst/config.yaml
```

### deploy.sh 脚本

提供完全自定义的安装逻辑。如果存在此文件，将完全接管安装过程。

---

## 高级机制

### 1. 配置合并机制

系统启动时会自动合并多个环境变量文件：

1. **收集阶段**:
   - 从各应用的 `image.env`、`port.env`、`app.env` 收集变量
   - 合并到统一的 `.env` 文件

2. **生成阶段**:
   - 读取 [`configures/firmware/costrict.env.in`](configures/firmware/costrict.env.in:1)
   - 实例化为 `.costrict.env`（生成动态密码等）
   - 合并到 `.env`

3. **覆盖阶段**:
   - 读取用户配置文件 `costrict-admin.env`
   - 覆盖默认配置项

### 2. 镜像预下载机制

系统会：

1. 收集所有 `image.env` 文件
2. 生成 `.images.list` 文件
3. 在安装前预下载所有镜像

### 3. 包升级机制

安装程序按以下优先级执行安装逻辑：

1. **deploy.sh** - 完全自定义安装
2. **MANIFEST** - 按清单复制文件
3. **默认安装** - 将包内容复制到 `install_dir/{package}/`

### 4. 模块启用/禁用

所有配置文件都支持 `enabled` 字段：

```json
{
  "enabled": false
}
```

如果 `enabled` 为 `false` 或 `"false"`，构建脚本将跳过该模块。

### 5. 分体式 Docker Compose 应用部署方式

对于复杂的服务端应用，可以采用分体式的 Docker Compose 部署方式，将不同的服务组件拆分为独立的 Docker Compose 文件。

**适用场景**:

- 大型微服务架构应用
- 需要独立管理各个服务组件
- 不同服务需要独立启动、停止或更新

**实现方式**:

1. **为每个服务组件创建独立的 Docker Compose 文件**:
   - 在 `configures/{package}/` 目录下为每个服务创建独立的 `.yml` 文件
   - 例如: `api-server.yml`, `worker.yml`, `database.yml`

2. **使用统一的网络和卷配置**:
   - 确保所有组件使用相同的 Docker 网络
   - 共享数据卷用于服务间通信

3. **环境变量统一管理**:
   - 使用 `image.env`、`port.env`、`app.env` 统一管理所有服务的配置
   - 各个 Docker Compose 文件引用相同的环境变量

**示例结构**:

```
configures/
└── myapp/
    ├── api-server.yml      # API 服务
    ├── worker.yml          # 后台任务服务
    ├── database.yml        # 数据库服务
    ├── image.env          # 镜像地址
    ├── port.env           # 端口配置
    └── app.env            # 应用配置
```

**优点**:

- 服务组件可以独立部署和更新
- 便于故障隔离和排查
- 支持水平扩展单个服务组件
- 更灵活的资源管理

**注意事项**:

- 确保服务间网络互通
- 合理规划端口映射，避免冲突
- 统一管理服务依赖关系
- 使用健康检查确保服务正常启动

---

## 构建和发布

### build-costrict.sh 详解 - 全自动构建发布包

[`build-costrict.sh`](build-costrict.sh:1) 是一个全自动构建发布包的脚本，能够自动检测变更、维护版本号变化、编译需要的组件以及发布。

**执行流程**:

该脚本按照以下 5 个步骤自动执行：

1. **Step 1 - 检查依赖更新**: 调用 [`check-update.sh`](check-update.sh:1) 使用 `--build-type dependency` 参数检查需要构建镜像的包，自动递增被更新模块的版本号

2. **Step 2 - 构建依赖镜像**: 如果 Step 1 检测到有更新，调用 [`build-depends.sh`](build-depends.sh:1) 构建镜像包（可选推送），否则跳过此步骤

3. **Step 3 - 更新系统清单**: 调用 [`gen-manifest.sh`](gen-manifest.sh:1) 更新 `configures/costrict-system/manifest.json`

4. **Step 4 - 检查组件更新**: 调用 [`check-update.sh`](check-update.sh:1) 使用 `--build-type component` 参数检查需要构建组件的包，自动递增被更新模块的版本号

5. **Step 5 - 构建发布包**: 如果 Step 4 检测到有更新，调用 [`build-components.sh`](build-components.sh:1) 构建包并上传到云环境（如果指定了 `--upload` 参数），否则跳过此步骤

**支持参数**:

| 参数 | 说明 |
|------|------|
| `--push [env]` | 推送镜像到指定环境（传递给 build-depends.sh）<br>• 如果 env 为空或 'def'，推送到 Docker Hub<br>• 否则推送到指定环境（如 'test,prod' 或 'all'）<br>注意：构建镜像始终执行，此选项只控制是否推送 |
| `--upload <env>` | 指定包上传的环境（传递给 build-components.sh） |
| `--help, -h` | 显示帮助信息 |

**关键特性**:

- **自动变更检测**: 脚本会自动检测依赖和组件的变更，只构建和发布有变更的部分
- **自动版本管理**: 检测到变更时，会自动递增相应模块的版本号
- **智能跳过机制**: 如果没有变更，会自动跳过不必要的构建步骤，提高效率
- **完整构建链路**: 从依赖镜像构建到应用组件发布，一次性完成整个构建流程

**使用示例**:

```bash
# 构建镜像（不推送），然后构建包
./build-costrict.sh

# 构建镜像并推送到 Docker Hub
./build-costrict.sh --push

# 构建镜像并推送到 test 和 prod 环境
./build-costrict.sh --push test,prod

# 构建包并上传到 prod 环境
./build-costrict.sh --upload prod

# 组合使用：构建镜像推送并上传包
./build-costrict.sh --push test --upload prod
```

**适用场景**:

- 日常开发后的快速构建和发布
- CI/CD 流水线中的自动化构建
- 批量更新多个组件和依赖
- 需要确保构建流程完整性的场景

**注意事项**:

- 脚本依赖于 [`check-update.sh`](check-update.sh:1) 来检测变更
- 版本号变更会自动写入对应的 `.json` 配置文件
- 建议在执行前确认 Git 仓库已提交所有必要的更改
- 使用 `--push` 和 `--upload` 参数前，请确保网络连接正常

---

### build-components.sh 详解

**完整命令**:

```bash
./build-components.sh [OPTIONS] [ACTIONS]
```

**选项**:

- `-p, --packages <PACKAGES>`: 指定要构建的包（逗号分隔）
- `--type <TYPE>`: 按类型过滤（exec/zip/conf）
- `--key <KEY>`: 指定私钥文件（默认: costrict-private.pem）
- `-h, --help`: 显示帮助信息

**动作**:

- `--update`: 自动更新组件版本
- `--clean`: 清理旧版本
- `--build`: 编译或构建模块
- `--pack`: 打包并签名模块
- `--index`: 为构建的包创建索引
- `--def`: 执行默认步骤（update, build, pack, index）
- `--upload <ENV>`: 上传包到指定环境
- `--upload-packages <ENV>`: 上传 packages.json

**环境配置**:

在 `.env` 文件中定义上传环境：

```bash
declare -a ENV_NAMES=("test" "prod" "qianliu")
declare -a ENV_HOSTS=("test.example.com" "prod.example.com" "qianliu.example.com")
declare -a ENV_PORTS=("8080" "8080" "8080")
declare -a ENV_PATHS=("/packages/test" "/packages/prod" "/packages/qianliu")
```

**示例**:

```bash
# 构建单个包
./build-components.sh --def -p completion-agent

# 构建多个包
./build-components.sh --def -p completion-agent,backend,cotun

# 按类型构建
./build-components.sh --def --type exec

# 上传到测试环境
./build-components.sh --upload test -p completion-agent

# 上传到多个环境
./build-components.sh --upload test,prod -p completion-agent

# 上传到默认环境
./build-components.sh --upload def -p completion-agent

# 上传到所有环境
./build-components.sh --upload all -p completion-agent
```

### build-depends.sh 详解

**完整命令**:

```bash
./build-depends.sh [OPTIONS] [ACTIONS]
```

**选项**:

- `-p, --packages <PACKAGES>`: 指定要构建的依赖（逗号分隔）
- `-h, --help`: 显示帮助信息

**动作**:

- `--build`: 构建依赖镜像
- `--update`: 使用构建的依赖更新组件信息
- `--push [<ENV>]`: 推送镜像到环境

**示例**:

```bash
# 构建依赖
./build-depends.sh --build -p client-manager

# 推送到 Docker Hub
./build-depends.sh --push -p client-manager

# 推送到指定环境
./build-depends.sh --push test,prod -p client-manager

# 推送到所有环境
./build-depends.sh --push all -p client-manager
```

**模板变量**:

`command` 和 `tag` 字段支持 Go template 语法：

```json
{
  "command": "docker build --build-arg VERSION={{.version}} . -t {{.repo}}/{{.name}}:v{{.version}}",
  "tag": "v{{.version}}"
}
```

可用变量包括 `depends/{package}.json` 中除 `command` 和 `tag` 之外的所有字段。

---

## 最佳实践

### 1. 版本管理

- 使用语义化版本号（SemVer）：`MAJOR.MINOR.PATCH`
- 在组件配置和依赖配置中保持版本一致
- 版本变更时同步更新所有相关配置

### 2. 目录组织

- 保持配置目录结构清晰
- 按功能模块组织子目录
- 为复杂的配置提供 README.md

### 3. 环境变量命名

- 使用一致的命名规范
- 避免命名冲突
- 为变量添加注释说明用途

### 4. 模板文件管理

- 将模板文件放在配置根目录
- 使用清晰的变量名
- 为复杂的模板添加注释

### 5. 测试流程

1. 先构建依赖（如需要）
2. 构建应用组件
3. 在本地环境测试
4. 上传到测试环境
5. 验证功能正常后上传到生产环境

### 6. 文档维护

- 为新组件添加描述信息
- 更新 README.md 说明组件用途
- 记录重要的配置变更

### 7. 安全考虑

- 敏感信息使用环境变量
- 使用模板文件动态生成密码
- 不要在配置文件中硬编码密钥

---

## 常见问题

### Q1: 如何调试构建失败的问题？

**A**: 

1. 检查配置文件语法是否正确
2. 查看构建脚本输出日志
3. 确认源代码路径和文件存在
4. 验证构建环境是否完整

### Q2: 如何处理跨平台编译问题？

**A**:

1. 确保源代码支持目标平台
2. 检查 build.py 脚本的跨平台兼容性
3. 在对应平台上测试编译结果
4. 使用 Docker 容器进行交叉编译

### Q3: 如何自定义安装流程？

**A**:

1. 使用 MANIFEST 文件精确控制文件安装位置
2. 或编写 deploy.sh 脚本完全自定义安装逻辑
3. 参考 [`configures/backend/MANIFEST`](configures/backend/MANIFEST:1) 示例

### Q4: 如何管理多个环境的配置？

**A**:

1. 使用环境变量文件区分不同环境
2. 在 costrict-admin.env 中覆盖环境特定配置
3. 使用模板文件动态生成配置
4. 为不同环境维护独立的配置文件

### Q5: 依赖镜像构建失败怎么办？

**A**:

1. 检查 Dockerfile 是否正确
2. 确认构建环境可用
3. 验证依赖的网络连接
4. 查看构建日志定位问题

---

## 附录

### A. 参考示例

- **客户端应用**: [`components/completion-agent.json`](components/completion-agent.json:1)
- **服务端应用**: [`components/backend.json`](components/backend.json:1)
- **依赖镜像**: [`depends/client-manager.json`](depends/client-manager.json:1)
- **配置示例**: [`configures/common/apisix/`](configures/common/apisix/)

### B. 相关文档

- 项目根目录 [`README.md`](README.md:1)
- 包管理配置 [`packages.json`](packages.json:1)
- 系统清单 [`costrict-manifest.json`](costrict-manifest.json:1)

### C. 联系支持

如有问题，请联系项目维护团队。

---

**最后更新**: 2025-01-15
