stat_database:
  host: "postgres"
  port: 5432
  user: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  dbname: "costrict_stat"
  sslmode: "disable"

paths:
  task_dir: "/app/task/raw/task"
  repo_dir: "/app/task/raw/repo"
  analysed_dir: "/app/analysed"
  org_csv_file: "/app/analysed/org_mapping.csv"

model_prices:
  gpt-4o:
    in_price: 18.0
    out_price: 72.0
  gpt-4o-mini:
    in_price: 1.08
    out_price: 4.32
  claude-sonnet-4.6:
    in_price: 21.6
    out_price: 108.0
  claude-opus-4.6:
    in_price: 36.0
    out_price: 180.0
  deepseek-v3:
    in_price: 0.10
    out_price: 0.20
  default:
    in_price: 0.5
    out_price: 1.0

volumes:
  task_dir:
    enabled: true
  analysed_dir:
    enabled: true

ai_estimation:
  enabled: false
  api_key: ""
  x_api_key: ""
  base_url: ""
  model: ""
  timeout_ms: 300000
  http_proxy: ""

algo_estimation:
  max_input_chars: 300000
  max_ratio: 50
  max_factor: 1.0
  min_factor: 0.2
  inchars_per_minutes: 20
  lines_per_minutes: 2
  min_minutes: 5
  commit_line_per_minutes: 0.20833

task_statistics:
  gap_threshold_minutes: 10
  extension_minutes: 5

task_create:
  silica_max_days: 7
  create_pseudo_task: false

org_dsn: ""

serve:
  port: 8080
  init:
    command: "import"
    params:
      force: true
