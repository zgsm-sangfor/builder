# LoginService Docker Compose 部署

本目录对应 `../costrict-cloud/loginservice/helm`：

- `login-service.yml` 对应 Deployment/Service，启动命令为 `serve --config /app/config.yaml`，容器端口为 8080。
- `config.yaml.tpl` 对应 Helm ConfigMap 的 `config.yaml`；安装阶段会生成同名 `config.yaml`。
- `image.env` 对应 Helm 的 `image.repository` 和 `image.tag`。
- `/healthz` 用于存活检查，`/readyz` 用于就绪检查；就绪检查包含数据库连接和迁移状态。

## 自动生成的上线配置

安装程序会从现有 `.costrict.env` 自动生成并展开以下配置，不需要手工填写：

- `server.public_url`、`casdoor.external_url`：使用 `COSTRICT_BASEURL`。
- `database.host/name/user/password`：使用 Compose 内的 `postgres`、`loginservice` 及现有 PostgreSQL 变量。
- `casdoor.internal_url`：`http://casdoor:8000`。
- `cs-user.issuer/base_url`：`cs-user`、`http://costrict-web-cs-user:8081`。
- Casdoor 客户端凭据：复用 `OIDC_AUTH_CLIENT_ID`、`OIDC_AUTH_CLIENT_SECRET`。
- LoginService 安全密钥：安装时由 `gen-secret.sh` 自动生成。

## 部署前必须补充

1. `image.env` 中的完整镜像 tag（Helm 的 `image.tag`）。
2. Casdoor 应用必须确认回调地址包含 `${COSTRICT_BASEURL}/login-service/api/v1/login/callback`。
3. 若启用 `old-oidc`，补充 `old-oidc.public_key` 和 `old-oidc.organization`；不使用时保持 `enable: false`。
4. 仅在非 HTTPS 的测试环境中把 `cookie.secure` 改为 `false`，生产环境保持 `true`；回跳白名单已经自动使用 `COSTRICT_BASEURL/*`。
5. 需要 APISIX 接入时，把上游地址配置为 `login-service:8080`，并放行根路径 `/healthz`、`/readyz`。

`replicaCount`、`imagePullSecrets`、Kubernetes ConfigMap checksum 在 Compose 中没有直接对应项；扩容由 Compose 编排层处理，私有仓库凭据由 Docker 登录配置提供。
