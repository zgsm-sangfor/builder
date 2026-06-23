# costrict-web

costrict-web package component

本目录的内容会被 build-components.sh 以 zip 方式整体打包为 `costrict-web.zip`。

如需针对不同平台提供不同内容，可在 `./configures/<os>/<arch>/costrict-web/` 下放置
平台特定版本；未提供平台目录时，回退到本 common 目录。

---

costrict-web 包含 6 个镜像，6 个服务：postgres、api、gateway、portal、proxy、worker。

## 资源配置

| 服务 | 镜像 | CPU | 内存 | 磁盘 |
|------|------|-----|------|------|
| costrict-web-postgres | pgvector/pgvector:pg16 | 200m | 1Gi | 10Gi |
| costrict-web-api | ghcr.io/xdfield/costrict-web-api | 10m~1000m | 64Mi~512Mi | 10Gi（artifacts） |
| costrict-web-gateway | ghcr.io/xdfield/costrict-web-gateway | 10m~500m | 64Mi~256Mi | - |
| costrict-web-portal | ghcr.io/xdfield/costrict-web-portal | 10m~500m | 64Mi~256Mi | - |
| costrict-web-proxy | ghcr.io/xdfield/costrict-web-proxy | 10m~500m | 64Mi~256Mi | - |
| costrict-web-worker | ghcr.io/xdfield/costrict-web-worker | 10m~1000m | 64Mi~512Mi | - |

## 端口

| 服务 | 端口 | NodePort |
|------|------|----------|
| gateway | 8081 | 30276 |
| portal | 3000 | 32440 |
| proxy | 8090 | 30290 |

## 数据库

地址：costrict-web-postgres:5432
数据库名：costrict_db
用户：costrict
初始化时创建 `vector` 扩展。

## Redis

地址：redis:6379
库：默认库 0（由 api 使用）
