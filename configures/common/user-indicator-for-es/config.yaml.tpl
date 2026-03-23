# 配置文件，根据 helm 和 values.yaml 生成
server:
  host: "0.0.0.0"
  port: 8080
  mode: "debug"  # debug, release, test
  router:
    basePath: "/user-indicator/api/v1"

es:
  addresses: ["https://es:9200"]
  username: ""
  password: ""
  indexs:
    "costrict_metrics": ""
  indicatorIndex: "costrict_metrics"
  tls:
    # 启用tls
    enable: false
    # 启用tls 则需要CA证书
    certPath: "./cert/ca.crt"
    # 理论上，设置了正确的 certPath 就可以正常验证
    # 但如果当前访问域名和证书的域不匹配,则设置skipVerify 为true跳过验证
    # skipVerify: true 可以不用设置certPath
    skipVerify: false

# 指标配置,指的是客户指标
userIndicatorConfig:
  enable: true
  esIndex: "costrict_metrics"
  # 支持的语言，采用数组, 高频语言放在前面，速度比map快，开销更小
  supportedLanguages: ["javascript","python","java","c","c++","typescript","go","sql","php","rust","swift","kotlin","ruby","scala","dart","shell","bash","_","others","html","css","json","yaml","xml","dockerfile","markdown","latex"]
  supportedIndicator: ["code_accept_frequency","code_accept_lines","code_reject_frequency","code_reject_lines","code_completion_frequency","code_completion_response_time","errors_frequency","code_completion_lines"]
  # 为空表示支持任意值
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
  enableSyncUserInfo: true
  reportIntervalMinutes: -1

# 聊天指标配置,指的是聊天模型相关指标,专供后台服务器使用,由于是内部服务，限制较少。
chatIndicatorConfig:
  enable: true
  esIndex: "costrict_chat_metrics"
  metricsSize: 50 # 聊天指标单次上报最大指标数量,和es的nested 单文档限制有关
  processTimeOut: 5000 # 最大处理时间，包含数据处理和es写入，单位毫秒

indicatorConfig:
  enable: true
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
  enableSyncUserInfo: true
  reportIntervalMinutes: 1

database:
  host: "postgres"
  port: 5432
  user: "{{POSTGRES_USER}}"
  password: "{{PASSWORD_POSTGRES}}"
  dbname: "quota_manager"
  sslmode: "disable"
  maxConns: 3
  maxIdle: 3

logger:
  level: "debug"         # debug, info, warn, error
  format: "json"     # json, console
  output: "console"        # console, file, both
  # filename: "logs/app.log"  # 日志文件路径
  # max_size: 100         # 单个日志文件最大大小，单位MB
  # max_backups: 5        # 保留的旧日志文件最大数量
  # max_age: 30           # 旧日志文件最多保留天数
  # compress: true        # 是否压缩旧日志文件

