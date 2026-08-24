# app.ini 模板：基于部署参考配置（temp/gitea/gitea/gitea/conf/app.ini）模板化
# 部署时由 tpl-resolve.sh 将 {{VAR}} 替换为 .env 实际值
# 数据库/缓存复用项目现有 postgres 与 redis（无 ACL 用户，故 redis URL 不带认证）
APP_NAME = CoStrict - Gitea
RUN_MODE = prod
RUN_USER = git
WORK_PATH = /data/gitea

[repository]
ROOT = /data/git/repositories

[repository.local]
LOCAL_COPY_PATH = /data/gitea/tmp/local-repo

[repository.upload]
TEMP_PATH = /data/gitea/uploads

[server]
APP_DATA_PATH = /data/gitea
DOMAIN = {{COSTRICT_HOST}}
PROTOCOL = http
SSH_DOMAIN = {{COSTRICT_HOST}}
HTTP_PORT = 3000
ROOT_URL = http://{{COSTRICT_HOST}}:{{PORT_GITEA}}/
DISABLE_SSH = false
; SSH 对外公布端口为宿主机映射端口 {{PORT_GITEA_SSH}}（容器内监听 22）
SSH_PORT = {{PORT_GITEA_SSH}}
SSH_LISTEN_PORT = 22
LFS_START_SERVER = true
# 部署时自动生成
LFS_JWT_SECRET =

[database]
PATH = /data/gitea/gitea.db
DB_TYPE = postgres
HOST = postgres:5432
NAME = gitea
USER = {{POSTGRES_USER}}
PASSWD = {{PASSWORD_POSTGRES}}
LOG_SQL = false
SCHEMA =
SSL_MODE = disable

[indexer]
ISSUE_INDEXER_PATH = /data/gitea/indexers/issues.bleve

[session]
PROVIDER = redis
PROVIDER_CONFIG = redis://redis:6379/0?pool_size=100&idle_timeout=180s
COOKIE_SECURE = true
COOKIE_NAME = gitea_session
GC_INTERVAL_TIME = 86400
SESSION_LIFE_TIME = 86400
SAME_SITE = lax

[queue]
TYPE = redis
DATADIR = queues/common
LENGTH = 100000
BATCH_LENGTH = 20
CONN_STR = redis://redis:6379/1?pool_size=100&idle_timeout=180s
QUEUE_NAME = _queue
SET_NAME = _unique
MAX_WORKERS = 10

[queue.code_indexer]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20

[queue.issue_indexer]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20

[queue.notification-service]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20

[queue.mail]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20

[queue.push_update]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20

[queue.mirror]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20

[queue.pr_patch_checker]
TYPE = redis
LENGTH = 100000
BATCH_LENGTH = 20



[picture]
AVATAR_UPLOAD_PATH = /data/gitea/avatars
REPOSITORY_AVATAR_UPLOAD_PATH = /data/gitea/repo-avatars

[attachment]
PATH = /data/gitea/attachments

[log]
MODE = console
LEVEL = info
ROOT_PATH = /data/gitea/log



[service]
REQUIRE_SIGNIN_VIEW = false
REGISTER_EMAIL_CONFIRM = false
ENABLE_NOTIFY_MAIL = false
ALLOW_ONLY_EXTERNAL_REGISTRATION = false
ENABLE_CAPTCHA = false
DEFAULT_KEEP_EMAIL_PRIVATE = false
DEFAULT_ALLOW_CREATE_ORGANIZATION = true
DEFAULT_ENABLE_TIMETRACKING = true
NO_REPLY_ADDRESS = noreply.localhost
# 关闭注册
DISABLE_REGISTRATION = true

[admin]
# 用户电子邮件通知的默认配置
DEFAULT_EMAIL_NOTIFICATIONS = disabled
# 禁止普通（非管理员）用户创建组织
DISABLE_REGULAR_ORG_CREATION = true
# deletion: 用户不能通过界面或者 API 删除他自己。
USER_DISABLED_FEATURES = change_username,deletion

[security]
# webhook
DISABLE_WEBHOOKS = false
ALLOWED_HOST_LIST = *
# 禁止具有 Git 钩子权限的用户创建自定义 Git 钩子
DISABLE_GIT_HOOKS = true
INSTALL_LOCK = true
# 运行时生成
SECRET_KEY =
INTERNAL_TOKEN =
PASSWORD_HASH_ALGO =

[lfs]
PATH = /data/git/lfs

[mailer]
ENABLED = false

# 关闭openid
[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false


[cron.update_checker]
ENABLED = false

[repository.pull-request]
DEFAULT_MERGE_STYLE = merge

[repository.signing]
DEFAULT_TRUST_MODEL = committer

[oauth2]
# 部署后生成
JWT_SECRET =


[cache]
INTERVAL = 60
ADAPTER = redis
HOST = redis://redis:6379/2?pool_size=100&idle_timeout=180s
ITEM_TTL = 16h

[webhook]
QUEUE_LENGTH = 1000
DELIVER_TIMEOUT = 5
# webhook地址
# ALLOWED_HOST_LIST = *
SKIP_TLS_VERIFY = false
PAGING_NUM = 10


[other]
SHOW_FOOTER_VERSION = false
SHOW_FOOTER_TEMPLATE_LOAD_TIME = false
SHOW_FOOTER_POWERED_BY = false
ENABLE_SITEMAP = false
ENABLE_FEED = false

[migrations]
# ALLOWED_DOMAINS =
ALLOW_LOCALNETWORKS = true

[api]
# 资源限制50MB
DEFAULT_MAX_BLOB_SIZE=52428800

[proxy]
PROXY_ENABLED = false
# PROXY_URL =
# PROXY_HOSTS = *.github.com, github.com, *.githubusercontent.com

[costrict]
ENABLED = true
JWT_JWKS_URL = https://{{COSTRICT_HOST}}/cs-user/.well-known/jwks
JWT_ISSUER = cs-user
JWT_COOKIE_NAME = zgsmAdminToken
QUOTA_ENABLED = true
QUOTA_DEFAULT_MAX_FILE_SIZE_MB = 10
QUOTA_DEFAULT_REPO_QUOTA_MB = 50
