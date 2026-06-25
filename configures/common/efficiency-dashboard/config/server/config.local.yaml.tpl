server:
  port: 9990

stat_database:
  host: "postgres"
  port: 5432
  user: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  dbname: "costrict_stat"
  sslmode: "disable"

task_dir: "/app/task/raw/task"
repo_dir: "/app/task/raw/repo"
analysed_dir: "/app/analysed"

cors:
  allow_origins:
    - "*"

ai_estimation:
  enabled: false
  api_key: ""
  base_url: ""
  model: ""
  timeout_ms: 300000
  http_proxy: ""

task_real_minutes:
  gap_threshold_minutes: 30
  extension_minutes: 5
