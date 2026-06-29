# 配置文件，根据 config.simple.yaml 修改创建。
server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"
  router:
    externalBasePath: "/user-indicator/api/v1"
    internalBasePath: "/internal/indicator/api/v1"

storage:
  type: "elasticsearch"

es:
  addresses: ["http://es:9200"]
  username: "elastic"
  password: "{{PASSWORD_ELASTIC}}"
  tls:
    enable: true
    certPath: ""
    skipVerify: true
  dataStream:
    enabled: true
    rolloverMaxAge: "30d"
    rolloverMaxSize: "50gb"
    rolloverMaxDocs: 10000000

jwtSettings:
  enable: true
  userIdField: ["displayName"]
  userNameField: ["properties", "oauth_GitHub_username"]

userIndicatorConfig:
  enable: true
  esIndex: "costrict_user_metrics_v2"
  supportedLanguages: ["javascript","python","java","c","c++","typescript","go","sql","php","rust","swift","kotlin","ruby","scala","dart","shell","bash","_","others","html","css","json","yaml","xml","dockerfile","markdown","latex"]
  supportedIndicator: ["code_accept_frequency","code_accept_lines","code_reject_frequency","code_reject_lines","code_completion_frequency","code_completion_response_time","errors_frequency","code_completion_lines"]
  stringValueIndicator:
    - name: "code_completion_frequency"
      values: ["accepted","rejected"]
    - name: "code_completion_lines"
      values: ["accepted","rejected"]
    - name: "errors_frequency"
  values: []
  processTimeOut: 5000
  batchProcessTimeOut: 10000
  maxBatchSize: 100
  maxMetricsSize: 50
  enableSyncUserInfo: false
  reportIntervalMinutes: 20

chatIndicatorConfig:
  enable: true
  esIndex: "costrict_chat_metrics_v4"
  metricsSize: 50
  processTimeOut: 5000

rawDumpConfig:
  enable: true
  blobStorageType: "disk"
  basePath: "./data/raw"
  allowedUAPrefix: "csc"
  maxBodySize: 10485760
  fileIndexStorageType: ""
  jsonlChunkEnabled: true

logger:
  level: "info"
  format: "json"
  output: "console"
  # filename: "logs/app.log"  # 日志文件路径
  # max_size: 100         # 单个日志文件最大大小，单位MB
  # max_backups: 5        # 保留的旧日志文件最大数量
  # max_age: 30           # 旧日志文件最多保留天数
  # compress: true        # 是否压缩旧日志文件

