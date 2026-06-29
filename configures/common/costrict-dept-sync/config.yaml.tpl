server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"

admin_key: ""

database:
  driver: "postgres"
  host: "postgres"
  port: 5432
  user: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  dbname: "dept_sync"
  sqlite_path: "/app/data/dept_sync.sqlite"
  charset: "utf8mb4"
  max_open_conns: 20
  max_idle_conns: 10
  conn_max_lifetime: 300

cache:
  default_ttl: 300
  cleanup_interval: 60

sync:
  cron: "0 4 * * *"
  universal_id_template: "{user_id}"

provider:
  sangfor:
    hr_url: ""
    dept_url: ""
    hr_key: ""
    dept_key: ""
    timeout: 60
    skip_verify: false

logger:
  level: "info"
  format: "json"
  output: "console"
