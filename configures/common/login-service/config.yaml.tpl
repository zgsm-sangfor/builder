# LoginService Docker Compose 配置模板；请按 README.md 补齐所有部署必填项后生成 config.yaml。

# 配置契约 v0.3，2026-10-14：v0.2 已整体确认（CHG-043），本次按 CHG-045 新增 login.refresh_token_ttl；其余字段与默认值不变，第三方隔离继续有效。依据见根目录技术设计第 9～14 章及第 14.5 节确认导航；模板占位值不是可运行配置。
# 加载规则：运行只读启动目录的 config.yaml，或用 --config 指定路径；本模板仅作留档与派生来源，运行加载器不得回退读取它。不支持环境变量覆盖。未知键容忍（忽略且不生效，为将来配置预留）；缺失必填项、重复键、类型错误一律拒绝启动；时长、字节数、5 段 cron、IANA 时区格式非法或跨字段校验失败同样拒绝启动。不支持热更新，改配置需受控重启；迁移子命令复用同一 --config 与同一份 database 配置。
# RT 期限按 login.refresh_token_ttl 配置；留空跟随 cs-user token，非空则独立计时。
# 除明确规定空值语义的可选项外，空字符串/null/空集合表示部署待填写或契约待定。
# 未另行注明的字段均非秘密；模板不包含实际地址、密码或密钥。

server:
  # 部署必填；监听所有 IPv4 网卡；已确认值：0.0.0.0。
  host: "0.0.0.0"
  # 部署必填；1～65535；已确认值：8080。
  port: 8080
  # 部署必填；已确认仅含协议、主机及可选端口（对外根地址），不含路径、查询和片段；程序在其后追加登录接口前缀 /login-service/、网关验证前缀 /token-auth/ 或旧协议前缀 /oidc-auth/（旧协议 /oidc-auth/api/v1/plugin/* 保持不变）；实际地址待提供。
  public_url: "{{COSTRICT_BASEURL}}"
  # 可选；是否禁用浏览器入口公开地址跳转，默认 false；修改后重启。
  disable_public_url_redirect: false
  # 必填；正时长；优雅关闭预算；已确认值：15s。收到 SIGTERM 后停止接收新请求，等待在途请求（含正在进行的上游调用）结束后再关闭数据库连接池；超时未完成即强制退出。在途 work 即使被中断也由滞留检查在 work_lost_threshold + work_check_interval 内失效，不会重复兑换上游。
  shutdown_timeout: "15s"
  # 必填；存活探针路径；已确认值：/healthz（根路径，不在 /login-service/、/token-auth/ 或 /oidc-auth/ 下）；仅表示进程存活，不检查依赖、不做鉴权、不写缓存；网关与编排平台须放行，且不得落入前端 HTML 回退路由。
  health_path: "/healthz"
  # 必填；就绪探针路径；已确认值：/readyz（根路径，不在 /login-service/、/token-auth/ 或 /oidc-auth/ 下）；检查数据库可连、必需配置与密钥已加载、迁移版本已就位；未就绪返回非 2xx 供摘除流量，不返回内部错误细节、不做鉴权。
  ready_path: "/readyz"

logger:
  # 必填；取值范围 debug、info、warn、error；已确认默认值：debug（用户 2026-10-13 指定；生产部署建议复核为 info）；改动需受控重启，不支持热更新。
  level: "info"
  # 必填；取值范围 json、console；已确认默认值：json（生产采集用 json，本地排查可切 console）。
  format: "json"
  # 必填；取值范围 console、file、both；已确认默认值：console；含 file 时按下方轮转参数写文件。
  output: "console"
  # 可选；日志文件路径；已确认默认值：logs/app.log；仅 output 含 file 时生效；启动时校验目录可写，写文件失败不得静默降级为仅控制台。
  filename: "logs/app.log"
  # 可选；单个日志文件体积上限（MB）；已确认默认值：100；仅 output 含 file 时生效。
  max_size: 100
  # 可选；保留的历史日志文件个数；已确认默认值：5；仅 output 含 file 时生效。
  max_backups: 5
  # 可选；历史日志保留天数（0 表示不按天数清理）；已确认默认值：30；仅 output 含 file 时生效。
  max_age: 30
  # 可选；是否压缩归档的历史日志文件；已确认默认值：true；仅 output 含 file 时生效。
  compress: true
  # 非配置字段（已确认）：日志库固定使用 zap，文件轮转固定使用 lumberjack；JSON 字段名、请求 ID 关联、脱敏规则由实现层固定，日志不得写入密码、密钥、token、cookie 或上游完整请求/响应体。
  # 本 logger 同时承载启动期告警：未知键（容忍但不生效）以 warn 记录键路径与数量，不打印字段值，见根目录技术设计第 10 章。

database:
  # 部署必填；PG 主库地址（权威授权用主库），无默认值；已确认。
  host: "postgres"
  # 必填；1～65535；已确认值：5432。
  port: 5432
  # 部署必填；库名，无默认值；已确认。
  name: "loginservice"
  # 部署必填；数据库用户名，无默认值；已确认。
  user: "{{POSTGRES_USER}}"
  # 使用密码认证时必填；字面量密码，仅写入不提交的运行 config.yaml；本值敏感，不得进模板、日志或记录；已确认不使用环境变量引用。
  password: "{{PASSWORD_POSTGRES}}"
  # 必填；已确认允许 disable/require/verify-ca/verify-full，部署默认 verify-full。
  sslmode: "disable"
  # verify-ca/verify-full 时必填；CA 文件路径；其他模式可为空；已确认。
  sslrootcert: ""
  # 必填；正整数；已确认值：20，须覆盖请求与清理连接预算。
  max_open_conns: 20
  # 必填；0～max_open_conns；已确认值：5。
  max_idle_conns: 5
  # 必填；正时长；已确认值：30m。
  conn_max_lifetime: "30m"
  # 必填；正时长；已确认值：5s。
  connect_timeout: "5s"
  # 必填；正整数且 ≤ max_open_conns；已确认值：4；后台定时任务（业务清理、事件清理、滞留 work 检查）可同时占用的连接上限，为在线请求预留其余连接。
  cleanup_max_conns: 4
  # 已确认不设 schema/search_path 字段：使用数据库默认 search_path，数据库表以 cslogin_ 前缀区分。
  # 部署约束（非配置字段）：整轮清理用会话级 pg_try_advisory_lock，要求真实数据库会话固定（直连或会话固定连接），不得经事务级连接池代理复用连接。

casdoor:
  # 部署必填；浏览器可达的 Casdoor 前端基址，仅含协议、主机及可选端口，不含路径；程序追加 /login/oauth/authorize；已确认。
  external_url: "{{COSTRICT_BASEURL}}"
  # 部署必填；后端可达的 Casdoor 基址，格式同上且不含路径；程序追加 /api/login/oauth/access_token 与 /.well-known/jwks；已确认。
  internal_url: "http://casdoor:8000"
  # 部署必填；Casdoor 应用 client_id；已确认。
  client_id: "{{OIDC_AUTH_CLIENT_ID}}"
  # 部署必填；Casdoor 应用 client_secret，字面量，仅写入不提交的运行 config.yaml；本值敏感，不得进模板、日志或记录；已确认。
  client_secret: "{{OIDC_AUTH_CLIENT_SECRET}}"
  # 部署必填；期望的 issuer 值（允许与 internal_url/external_url 不同）：与 token 内 iss 声明做完整字符串相等比较（区分大小写及末尾斜杠，不自动规范化），不访问该地址、不做 OIDC discovery；
  # 验签公钥另从 internal_url 下的 /.well-known/jwks 获取；本值必须与 Casdoor 实际签发的 iss 完全一致；已确认。
  issuer: "http://casdoor:8000"
  # 已确认不设字段：audience 由 client_id 派生后比对；授权 scope 固定 openid；PKCE 固定启用；均不提供配置开关。

# 旧 oidc-auth RT 临时兼容配置；启用前须为 Casdoor token grant 入口落实有效服务鉴权。
old-oidc:
  # 显式启用旧 RT 兼容；默认 false，缺失本字段或整个配置组同关闭。
  enable: false
  # 旧 oidc-auth 签名公钥 PEM 内容，支持 YAML 多行字符串；只填公钥，不填私钥或文件路径。
  # 使用签发旧 RT 的那把私钥导出，不能重新生成密钥：
  # openssl pkey -in privatekey.pem -pubout -out publickey.pem
  # 将 publickey.pem 完整内容（含 BEGIN/END PUBLIC KEY）用 public_key: | 多行形式填写。
  # enable=true 时必填且须为合法 RSA 公钥；关闭时不加载或校验公钥内容。
  public_key: ""
  # Casdoor 应用组织，须与 casdoor.client_id 对应应用一致；兼容开启时必填。
  organization: ""

cs-user:
  # 部署必填；期望的 cs-user JWT iss，与上游实际签发值完整字符串相等（区分大小写及末尾斜杠，不自动规范化）。
  # 不从 base_url 推导，不用于 discovery 或获取公钥；JWKS 固定从 base_url 下的 /.well-known/jwks 获取。缺失、空值或非字符串拒绝启动。
  issuer: "cs-user"
  # 部署必填；cs-user 内部服务基址，仅含协议、主机及可选端口，不含路径；程序追加固定兑换路径；字段已确认，实际地址由部署填写，内部路径见技术设计第 11 章。
  base_url: "http://costrict-web-cs-user:8081"
  # 部署必填；LoginService 作为内部程序调用 cs-user 时提交的共享密钥，供 cs-user 校验调用方是内部程序；字面量，仅写入不提交的运行 config.yaml；本值敏感，不得进模板、日志或记录；已确认。
  internal_secret: "{{PASSWORD_COSTRICT_WEB_CS_USER_TOKEN}}"
  # 契约已核对：内部调用以请求头 `X-Internal-Token` 提交本字段值；三类能力对应 `POST /api/internal/auth/verify`、`POST /api/internal/users/reissue-token`、`POST /api/internal/auth/refresh`，企业身份场景另有 `POST /api/internal/enterprise-identities/{provider}/{enterprise_uid}/tokens`（需 `X-Tenant-Id`）；cs-user 不回 Set-Cookie，业务 Cookie 由本服务按 cookie 组写入。结论来自 costrict-web 提交静态核对，真实联调前不得宣称已验证。

cookie:
  # 必填；布尔；已确认默认 true；HTTPS 部署输出 Secure；HTTP 部署须设 false 并完全省略该属性，不得输出 Secure=false。
  secure: false
  # 必填；已确认空字符串表示 host-only（不写 Domain）；填 example.com 即覆盖该域及其全部子域；通配符 *.example.com 非法；须与 public_url 主机域匹配，且不得为公共后缀。
  domain: ""
  # 必填；已确认默认 "/"；业务 Cookie Path。
  path: "/"
  # 必填；布尔；按用户要求已确认默认 false（与上游 zgsmAdminToken 的 HttpOnly=false 一致，供前端 JS 读取）；关闭时页面 XSS 可读取该凭据。
  http_only: false
  # 必填；已确认默认 None；允许 Lax/Strict/None；None 必须同时 secure=true；secure=false 时禁止 None（HTTP 部署须显式改 Lax/Strict）。
  same_site: "None"
  # 已确认不设字段：业务 Cookie 名固定 zgsmAdminToken；流程 Cookie 名按协议固定 __Host-oidc_flow（HTTPS）/ oidc_flow（HTTP）；业务 Cookie 的 Expires 固定取已验证 cs-user token 的 exp，不写 Max-Age；流程 Cookie 保持会话 Cookie，不写 Max-Age/Expires；不设独立期限配置。

security:
  # 当前密钥版本 id：新签发摘要、新加密、新签名一律使用该版本；必须存在于下方 keys 中；由加载器校验。
  current_key_id: "{{LOGIN_SERVICE_KEY_ID}}"
  # 密钥版本列表（受控小集合）；轮换时新增版本并切换 current_key_id，旧版本保留到对应材料最大有效期结束，仅用于校验历史摘要与解密历史密文。
  keys:
    # 每版本一条：id 即 key_id，字符集 [A-Za-z0-9_.-]，长度 1–32；已确认。
    - id: "{{LOGIN_SERVICE_KEY_ID}}"
      # 32 字节以上随机值，base64 编码；字面量，仅写入不提交的运行 config.yaml；本值敏感，不得进模板、日志或记录。
      secret: "{{LOGIN_SERVICE_KEY_SECRET}}"
  # 已确认不设字段：各用途子密钥（refresh_token/login_ticket/device_secret/oauth_state/login_code/handoff_code/work_id/flow/csrf/confirmation/cipher）由版本密钥按用途派生（HKDF-SHA256，info=用途名），实现层固定，不逐用途配置。

third_party:
  # 接入方登记列表；本期不开放配置管理 API，先受控配置维护；空列表表示尚未登记任何接入方。
  # v0.3 已确认隔离：claims 契约确认前，加载器拒绝非空 clients；空列表不开放第三方登录/交换，但不阻塞普通设备及同域网页能力。实际接入条目与 claims 后续确认，不把下方示例当作已批准集合。
  # 每项字段：
  #   client_id     string  必填；已登记接入方标识，HTTP Basic 用户名，全局唯一，最长 128 字符（已确认）。
  #   secret        string  必填；接入方密钥，已确认明文存储（受控配置、不提交，恒定时间比较；服务间仍须经 TLS 或受保护加密通道传输）；本值敏感，不得进模板、日志或记录。
  #   redirect_uris string[] 必填；允许回调地址白名单，严格匹配 scheme/host/port/path，拒绝 URL 用户信息段与未批准通配。
  #   enabled       bool    必填；停用后不允许发起与交接，交付时复核启用状态与回调白名单。
  #   claims        string[] 必填；允许向该接入方输出的身份字段白名单；反映到 API-16 的 subject 字段，建议取值 subject_id、display_name（取值集合待确认）。
  # 示例（假值，仅演示字段形状，不表示已登记接入方）：
  #   - client_id: "partner_console"
  #     secret: "<明文密钥>"
  #     redirect_uris: ["https://partner.example.net/auth/callback"]
  #     enabled: true
  #     claims: ["subject_id", "display_name"]
  clients: []

web:
  # 同域业务页白名单；return_to 规范化后按通配模式匹配（* 匹配任意字符序列）；空列表表示不允许跳转业务页；已确认。
  # 已确认按 scheme://host[:port]/path 直接拼接后做通配匹配；条目须为 http/https，禁止用户信息段与 fragment；应与 public_url 同注册域；须写目标页面的完整 URL；指向本服务时使用新前缀（如 /login-service/ui/），外部目标不强加本服务前缀。
  return_to_allowlist: ["{{COSTRICT_BASEURL}}/*"]
  # 已确认可为空；为空时认证完成后停留在 LoginService 页面，不跳转业务页；非空时必须匹配上面的白名单。
  default_return_to: ""
  # 流程 Cookie（__Host-oidc_flow / oidc_flow）内部签名的有效期限；是防伪造材料期限，不是用户登录期限；到期后只能由页面入口或 API-06 重建；可配置；默认值：1h；须 ≥ transaction_ttl。
  flow_ttl: "1h"
  # csrf_token 签名有效期限；可配置；默认值：1h；实际寿命 = min(csrf_ttl, flow 号票剩余有效期)。
  csrf_ttl: "1h"
  # 完整网页登录 request-target 上限；协议硬上限 8192 字节。
  web_login_url_max_bytes: 8192
  # entry_context 结构限制。
  entry_context_max_bytes: 4096
  entry_context_max_keys: 32
  entry_context_key_max_bytes: 128
  entry_context_value_max_bytes: 1024
  entry_context_max_depth: 5

hook:
  # 是否启用全部 Hook；false 时不执行 Hook，但仍校验 YAML 结构和字段类型。
  enabled: false
  # HookEvent JSON 协议版本；事件结构变化时递增。
  event_version: 1
  # 异步 Outbox Worker 数量；只影响并发投递数。
  worker_count: 4
  # Worker 扫描待投递 Outbox 的间隔。
  poll_interval: "1s"
  # Hook 未单独配置 timeout 时使用的单次执行超时。
  default_timeout: "5s"
  # HTTP Hook 最大响应体字节数，超过后视为协议失败。
  http_max_response_bytes: 65536
  definitions: []
login:
  # 可选；设备领取轮询间隔，整数秒，范围 1～86400；缺失时默认 5；修改后重启生效。
  device_poll_interval_seconds: 5
  # 可选；RT 有效时长，默认空字符串（缺失同空）：与本次 cs-user token 到期时间一致。
  # 非空为正 Go duration（如 720h）；初次签发/成功轮换时从签发时刻计时，可短于或长于 token 期限，无 token 期限上限。
  # null、零、负值、错误类型或非法时长拒绝；重启改配置只影响之后签发的 RT，不回算已签发 RT。
  # RT 有效不保证上游续签成功；旧 cs-user token 是否可续签由 cs-user 判定，上游失败不轮换 RT。
  refresh_token_ttl: ""
  # 浏览器登录票据（API-01 返回 login_url 中的 ticket）有效期；已确认值：10m。
  login_ticket_ttl: "10m"
  # 登录事务期限，从创建时计算；认证、确认、准备完成与领取均校验；已确认值：10m。
  transaction_ttl: "10m"
  # 用户输入设备的随机登录码有效期；已确认值：5m。2026-10-14 明确：从码生成时间计算，与生成时 token 期限解耦，不因该 token 过期而缩短或提前失效。
  login_code_ttl: "5m"
  # 随机登录码字符数（128 bit Base32 编码）；已确认值：26。
  login_code_length: 26
  # 第三方一次性交接码有效期；已确认值：60s。
  handoff_code_ttl: "60s"
  # 可选；正 Go duration；默认 30s。刷新成功后前代 RT 仅在窗口内取回同一已提交结果，不重新续签或撤销后继 RT；实际截止时间取提交时间加本值与输入 RT 原期限、新 RT/token 期限的最早值。
  # 缺失时由加载器采用默认值；空值、零、负值或类型错误拒绝启动。重启后不回算已持久化的 previous_valid_until；不影响第三方交接码的重发策略。
  refresh_replay_window: "30s"
  # 已确认不设字段：设备领取秘密(claim_secret)、oauth_state、confirmation_token 均为“不超过事务期限”，由 transaction_ttl 派生，不单独配置。

cleanup:
  # 业务清理间隔（登录事务、一次性码、设备刷新会话三张表）；已确认值：10m；必须为正；变更配置不得启动同一任务的并行副本。
  business_interval: "10m"
  # 事件历史清理调度；5 段 cron（分 时 日 月 周）；已确认默认每日 03:00。
  event_schedule: "0 3 * * *"
  # 调度时区（IANA 名称）；已确认 Asia/Shanghai；时间比较统一使用 UTC。
  timezone: "Asia/Shanghai"
  # 业务数据保留期：事务/码及终止后设备会话的 cleanup_after 基准；已确认值：24h。
  business_retention: "24h"
  # 事件历史保留期；可配；已确认默认 30 天（Go duration 不支持 d，写作 720h）。
  event_retention: "720h"
  # 每批删除行数上限；已确认值：500。
  batch_size: 500
  # 单批 SQL 最长执行时间；已确认值：2s。
  statement_timeout: "2s"
  # 单批锁等待上限；已确认值：100ms。
  lock_timeout: "100ms"
  # 批次间退让时间；已确认值：100ms。
  batch_backoff: "100ms"
  # 业务清理单轮时间预算；已确认值：60s。
  business_round_budget: "60s"
  # 事件清理单轮时间预算；已确认值：5m。
  event_round_budget: "5m"
  # 已确认不设字段：整轮互斥用会话级 pg_try_advisory_lock（见 database 组部署约束）；清理连接并发上限由 database.cleanup_max_conns 约束。

runtime:
  # 必填；正整数（字节）；单个带 JSON body 的新接口请求体允许的最大字节数；已确认值：16384（16 KiB，设计 4.1.2 建议值）；超限返回 413 request_too_large，不解析、不落库、不调上游；页面与静态资源不受此限。
  max_request_bytes: 16384
  # 必填；正时长；单次上游调用（Casdoor 换取令牌/用户信息、cs-user 兑换与刷新）的整体超时；默认 10s。超时返回 503 upstream_unavailable，不自动重试；设备确认后的兑换失败保留有效事务供用户再次确认，RT 刷新保留原 RT、代次不推进。
  upstream_timeout: "10s"
  # 必填；正整数（字节）；单次上游响应体读取上限；已确认值：262144（256 KiB）；超限即中止本次调用并返回 503 upstream_unavailable，不解析部分响应，不自动重试。
  upstream_max_response_bytes: 262144
  # 必填；正时长；工作失联判定阈值：work_started_at 早于“当前时间减该值”即视为原处理程序失联；已确认值：30s；须 ≥ upstream_timeout。
  work_lost_threshold: "30s"
  # 必填；正时长；滞留 work 检查的独立周期，不依赖 cleanup.business_interval；已确认值：30s；最坏发现延迟约为 work_check_interval + work_lost_threshold。
  work_check_interval: "30s"
  # 必填；正时长；滞留 work 检查单条 SQL 的执行时间上限；已确认值：2s；防止检查语句拖慢在线请求。
  work_check_statement_timeout: "2s"
  # 检查机制（非配置字段）：每周期只做一次探测查询，命中后用条件 UPDATE 校验状态/版本/work_id 使旧工作失效；不批量删除、不回调上游、不重试结果不明操作；查询必须匹配部分索引 (work_started_at, id) WHERE work_id IS NOT NULL，禁止退化为全表扫描的写法。
  # 已确认不设字段：上游 3xx 不自动跟随跳转；兑换与刷新在结果不明时不自动重试。
  # 已确认不设字段：限流与可信代理/转发头信任由网关承担，本服务不设相关字段、不解析转发头判定来源。本组字段已全部讨论确认。

# 可选；整个配置组缺失时关闭两个 APISIX 接口，不影响既有登录配置。
apisix:
  # 默认关闭；开启后注册 discovery 与 introspection。
  enabled: true
  # 开启时必填，1～128 位字母、数字、下划线、点或短横线；与 Casdoor client_id 独立。
  client_id: "{{OIDC_AUTH_CLIENT_ID}}"
  # 开启时必填，32～256 位 URL 非保留字符（字母、数字、-._~）；使用随机秘密，仅填真实配置。
  client_secret: "{{OIDC_AUTH_CLIENT_SECRET}}"
