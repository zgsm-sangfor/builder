# kbcli config.yaml - docker-compose adapted.
stat_database:
  host: postgres
  port: 5432
  user: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  dbname: efficiency_dashboard
  sslmode: disable

model_prices:
  gpt-4o:
    in_price: 18.0
    out_price: 72.0
  gpt-4o-mini:
    in_price: 1.08
    out_price: 4.32
  gpt-5.4:
    in_price: 18.0
    out_price: 108.0
  gpt-5-mini:
    in_price: 1.8
    out_price: 14.4
  claude-3.7-sonnet:
    in_price: 21.6
    out_price: 108.0
  claude-haiku-4.5:
    in_price: 7.2
    out_price: 36.0
  claude-sonnet-4.6:
    in_price: 21.6
    out_price: 108.0
  claude-opus-4.6:
    in_price: 36.0
    out_price: 180.0
  gemini-2.5-pro:
    in_price: 7.2
    out_price: 72.0
  gemini-2.5-pro-preview:
    in_price: 9.0
    out_price: 72.0
  gemini-2.5-flash:
    in_price: 2.16
    out_price: 18.0
  gemini-2.5-flash-lite:
    in_price: 0.72
    out_price: 2.88
  gemini-2.5-computer-use:
    in_price: 9.0
    out_price: 72.0
  deepseek-v4-flash:
    in_price: 1.01
    out_price: 2.02
  deepseek-v4-pro:
    in_price: 3.13
    out_price: 6.26
  deepseek-v3.2:
    in_price: 1.81
    out_price: 2.72
  deepseek-v3:
    in_price: 0.10
    out_price: 0.20
  qwen3-max:
    in_price: 2.5
    out_price: 10.0
  qwen3.5-plus:
    in_price: 0.8
    out_price: 4.8
  qwen-long:
    in_price: 0.5
    out_price: 2.0
  qwen-turbo:
    in_price: 0.24
    out_price: 0.94
  qwen3.5-omni-flash:
    in_price: 0.5
    out_price: 2.0
  kimi-k2.6:
    in_price: 6.5
    out_price: 27.0
  kimi-k2.5:
    in_price: 4.32
    out_price: 18.0
  kimi-k2:
    in_price: 4.0
    out_price: 16.0
  moonshot-v1-8k:
    in_price: 12.0
    out_price: 12.0
  moonshot-v1-128k:
    in_price: 60.0
    out_price: 60.0
  glm-4.7:
    in_price: 0.8
    out_price: 0.8
  glm-5.1:
    in_price: 0.8
    out_price: 0.8
  glm-5:
    in_price: 1.0
    out_price: 2.0
  kimi-k2.5-moonshot:
    in_price: 4.32
    out_price: 18.0
  minimax-m2.1:
    in_price: 0.5
    out_price: 1.0
  minimax-m2.5:
    in_price: 0.5
    out_price: 1.0
  minimax-m2.7:
    in_price: 0.5
    out_price: 1.0
  auto:
    in_price: 0.5
    out_price: 1.0
  default:
    in_price: 0.5
    out_price: 1.0

task_dir: "/app/task"
repo_dir: "/app/repo"
analysed_dir: "/app/analysed"
org_csv_file: "/app/analysed/org_mapping.csv"

org_dsn: "host=postgres port=5432 user={{POSTGRES_USER}} password={{PASSWORD_POSTGRES}} dbname=efficiency_dashboard sslmode=disable"

dept_sync:
  base_url: ""
  query_key: ""
  fallback_org_name: "深信服科技股份有限公司"
  fallback_dept_name: "未知部门"

http_proxy: "http://127.0.0.1:7890"

traditional_dev_lines_per_day: 100

analysis_start_date: "20260525"

serve:
  port: 8080
  init:
    command: import
    params:
      force: false
  crontab:
    - schedule: "0 0 */4 * * *"
      command: import
      params:
        force: false
    - schedule: "0 30 4 * * *"
      command: fix-task
    - schedule: "0 0 5 * * *"
      command: fix-commit
    - schedule: "0 0 3 * * 0"
      command: import
      params:
        force: true

efficiency_v2:
  baseline_defaults:
    weight_algo: 0.60
    weight_knn: 0.15
    weight_llm: 0.25
    team_work_density: 0.35
  baseline_calendar_calibration: 1.0
  baseline_algo:
    think_turn_min: 5
    exec_file_coord_min: 30
  confidence_thresholds:
    outlier_efficiency_ratio_max: 10.0
    outlier_efficiency_ratio_min: -2.0
    outlier_loc_per_calendar_min_max: 7
  exclusion:
    scope: [efficiency_ratio, loc_rate, actual_to_baseline]
  anchor_set_csv: /app/docs/data/efficiency_v2_anchor_set.csv
  stage:
    default_edit_duration_seconds: 30
    default_read_duration_seconds: 10
    default_command_duration_seconds: 30
    default_other_duration_seconds: 10
    default_message_chars_per_minute: 300
    gap_threshold_minutes: 5
    extension_minutes: 2
    max_inferred_duration_gap_minutes: 5

algo_estimation:
  commit_minutes_per_line: 1.8
  max_input_chars: 300000
  max_ratio: 10
  max_factor: 1.0
  min_factor: 0.2
  inchars_per_minutes: 20
  lines_per_minutes: 2
  min_minutes: 5

ai_estimation:
  enabled: false
  api_key: ""
  base_url: "https://newapi-ai.sangfor.com"
  model: "openrouter-deepseek-v4-flash"
  timeout_ms: 300000
  http_proxy: ""
