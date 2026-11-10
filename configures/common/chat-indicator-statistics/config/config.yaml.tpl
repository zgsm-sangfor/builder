# Chat Indicator Statistics config.yaml - docker-compose adapted.
server:
  host: "0.0.0.0"
  port: 8080

target_db:
  driver: "postgres"
  host: "postgres"
  port: 5432
  database: "chat_indicator_statistics"
  schema: "public"
  username: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  ssl_mode: "disable"
  sqlite_path: "./data/summary.db"

sync:
  batch_size: 5000
  gap_max_hours: 24
  max_retry: 3

bootstrap:
  datasource:
    name: "default_es"
    source_type: "elasticsearch"
    enabled: true
    config:
      hosts: ["https://elasticsearch:9200"]
      username: "elastic"
      password: "{{PASSWORD_ELASTIC}}"
      index: "costrict_chat_metrics_v4"
      verify_certs: true
      scroll_duration: "5m"
  daily_etl:
    enabled: true
    cron: "0 2 * * *"
    source: "default_es"

cron:
  daily_etl: "0 2 * * *"
  enabled: true

encryption:
  enabled: true
  secret_key: "12345678901234567890123456789012"

raw_log_preview:
  storage: "disk"
  root_dir: "/mnt/chat-rag/logs"
  max_size_mb: 5

log:
  level: info
  format: json
  output: console
