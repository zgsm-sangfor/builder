# gitea

gitea 独立 Git 服务组件（不隶属于 costrict-web 组件）。

## 端口

- `3000`：HTTP 服务（`PORT_GITEA`）
- `3322`：SSH 服务（`PORT_GITEA_SSH`，映射容器内 22）

## 组成

| 服务 | 说明 |
| --- | --- |
| `gitea` | Gitea 主服务（镜像 `docker.gitea.com/gitea:1.27.0`） |

## 依赖（复用项目现有组件）

- **postgres**：复用项目现有 PostgreSQL，使用独立库 `gitea`（由 `postgres/initdb.d/10-create-db.sql` 创建），账号为 `${POSTGRES_USER}` / `${PASSWORD_POSTGRES}`。
- **redis**：复用项目现有 Redis（无密码），用于 session/cache/queue（`redis://redis:6379/0`）。

## 配置

- `conf/app.ini.tpl`：部署时由 `tpl-resolve.sh` 解析为 `conf/app.ini`（`{{COSTRICT_HOST}}`、`{{PORT_GITEA}}`、`{{PORT_GITEA_SSH}}`、`{{POSTGRES_USER}}`、`{{PASSWORD_POSTGRES}}` 替换为实际值）。
- 环境变量（`gitea.yml` 中 `GITEA__*`）与 app.ini 保持一致，作为容器启动时配置来源。

## 与其他组件的关系

- `costrict-web` 的 api/worker 通过 `GIT_SYSTEM_WEBHOOK_BASE_URL`、`GIT_CAPABILITY_*` 对接 Gitea。
- `costrict-web-workflow-backend` 通过 `GITEA_BASE_URL=http://gitea:3000/`（compose 网络内）与 `GITEA_PUBLIC_BASE_URL=http://{{COSTRICT_HOST}}:{{PORT_GITEA}}`（外部访问）对接。
