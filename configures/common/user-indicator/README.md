# User Indicator for ES - Docker Compose 部署配置

本目录包含 user-indicator 服务的 Docker Compose 部署配置，用于在本地或测试环境中快速启动服务。

## 文件说明

- **docker-compose.yml**: Docker Compose 主配置文件，定义了服务的编排方式
- **config.yaml**: 应用配置文件，包含 Elasticsearch、数据库、指标配置等
- **cert/ca.crt**: Elasticsearch TLS 证书（需根据实际环境配置）
- **.env.example**: 环境变量配置模板
- **start.sh**: 启动服务脚本
- **stop.sh**: 停止服务脚本

## 快速开始

### 1. 准备配置

首先，根据实际环境修改配置文件：

1. 修改 `config.yaml` 中的 Elasticsearch、数据库连接配置
2. 配置 TLS 证书文件 `cert/ca.crt`（如果不需要 TLS，可设置 `es.tls.enable: false`）
3. 如需使用环境变量覆盖配置，复制 `.env.example` 为 `.env` 并修改

### 2. 启动服务

使用启动脚本：
```bash
./start.sh
```

或直接使用 docker-compose：
```bash
docker-compose up -d
```

### 3. 查看日志

查看服务运行日志：
```bash
docker-compose logs -f user-indicator
```

### 4. 停止服务

使用停止脚本：
```bash
./stop.sh
```

或直接使用 docker-compose：
```bash
docker-compose down
```

## 配置说明

### 资源限制

服务默认资源配置（与 helm chart 保持一致）：
- **CPU 请求**: 500m
- **CPU 限制**: 3
- **内存请求**: 512Mi
- **内存限制**: 6Gi

可在 `.env` 文件中覆盖这些值。

### 健康检查

服务配置了健康检查：
- 检查端点: `http://localhost:8080/health`
- 检查间隔: 30秒
- 超时时间: 5秒
- 失败重试: 3次
- 启动宽限期: 30秒

### 网络配置

- 服务默认暴露端口: `8080:8080`
- 内部服务地址需根据实际网络环境调整（如 Elasticsearch、PostgreSQL）

## 与 Helm Chart 等价性

本 Docker Compose 配置与 Helm Chart 保持了以下等价配置：

| 配置项 | Helm 值 | Docker Compose 值 |
|--------|---------|-------------------|
| 镜像版本 | v0.0.5 | v0.0.5 |
| CPU 请求 | 500m | 500m |
| CPU 限制 | 3 | 3 |
| 内存请求 | 512Mi | 512Mi |
| 内存限制 | 6Gi | 6Gi |
| 健康检查路径 | /health | /health |
| 就绪检查路径 | /ready | 通过健康检查实现 |
| 服务端口 | 8080 | 8080 |

## 注意事项

1. **证书配置**: 确保 Elasticsearch 的 TLS 证书正确配置在 `cert/ca.crt` 中
2. **网络连接**: 确保 Docker 容器可以访问 Elasticsearch 和 PostgreSQL 服务
3. **资源隔离**: 生产环境建议使用网络隔离和资源配额
4. **日志管理**: 默认日志输出到控制台，可通过 Docker 日志驱动配置

## 故障排查

查看服务状态：
```bash
docker-compose ps
```

进入容器调试：
```bash
docker-compose exec user-indicator sh
```

重启服务：
```bash
docker-compose restart user-indicator
```

## 参考文档

- 原始项目文档: [README](../../../../README.md)
- Helm Chart: [helm/](../../../../helm)
- Dockerfile: [Dockerfile](../../../../Dockerfile)
