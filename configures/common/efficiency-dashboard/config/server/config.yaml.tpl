# server config.yaml - docker-compose adapted.
server:
  port: 9990

stat_database:
  host: postgres
  port: 5432
  user: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  dbname: efficiency_dashboard
  sslmode: disable

task_dir: "/app/task"
repo_dir: "/app/repo"
analysed_dir: "/app/analysed"
org_mapping: "/app/org_mapping.csv"

cors:
  allow_origins:
    - "*"

dashboard_title_prefix: "Costrict"

ai_estimation:
  enabled: false
  api_key: ""
  base_url: "https://open.bigmodel.cn/api/anthropic"
  model: "claude-3-5-sonnet-20241022"
  timeout_ms: 300000
  http_proxy: ""

task_real_minutes:
  gap_threshold_minutes: 30
  extension_minutes: 5

dept_sync:
  base_url: "http://costrict-dept-sync-svc:8080"
  query_key: "0b8e86321298d10b498af18f343409050853c57a2ec6145c9d16cd4a65300b75"
  root_dept_id: "49"

chat_stats:
  base_url: "http://chat-indicator-statistics:8080"
  username: ""
  password: ""
