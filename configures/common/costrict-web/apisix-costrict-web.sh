#!/bin/sh

. ./configure.sh

# =====================================================================
# APISIX 路由配置（基于 k8s 参考：temp/costrict-web.sh + temp/costrict-web-workflow.sh）
# 适配说明（compose 环境差异）：
#   - 上游 host:port 由 k8s service/nodePort 改为 compose 服务名:端口
#   - 跳过 costrict-web-proxy(/p-cloud-api/*) 与 costrict-web-proxy-portal(/p-cloud/*)：
#     compose 环境未部署 proxy 服务
#   - 跳过 costrict-web-portal-copy(host=113.108.13.6)：该路由按 Host 头分流，
#     仅用于 k8s 集群公网入口场景，compose 单机不需要
#   - 参考脚本中 allow_degradation 为 '$Allow_DEGRADATION'（部署时替换的占位写法），
#     compose 的 configure.sh 无该机制，这里直接使用布尔 false（与默认一致）
# =====================================================================

# ****
# 1. Costrict Web API Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-api",
    "nodes": {
      "costrict-web-api:8080": 1
    },
    "timeout": {
      "connect": 6,
      "send": 600,
      "read": 600
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "node",
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uri": "/cloud-api/*",
  "name": "costrict-web-api",
  "id": "costrict-web-api",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "/cloud-api/(.*)",
        "/$1"
      ]
    },
    "limit-count": {
      "count": 600,
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60,
      "key": "$http_zgsm_client_id$http_authorization$cookie_casdoor_session_id",
      "allow_degradation": false
    },
    "limit-req": {
      "rate": 100,
      "burst": 200,
      "rejected_code": 429,
      "key_type": "var_combination",
      "key": "$http_zgsm_client_id$http_authorization",
      "allow_degradation": false
    },
    "request-id": {
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "algorithm": "uuid"
    }
  },
  "upstream_id": "costrict-web-api",
  "enable_websocket": true,
  "status": 1
}'

# ****
# (参考含 costrict-web-proxy: /p-cloud-api/* -> costrict-web-proxy:8090)
# compose 环境未部署 proxy 服务，跳过

# ****
# 2. Block Memory Route: intercept /cloud-api/api/memories* and return 200 directly
curl -i http://$APISIX_ADDR/apisix/admin/routes/block-memory -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "block-memory",
  "uri": "/cloud-api/api/memories*",
  "priority": 9999,
  "plugins": {
    "response-rewrite": {
      "status_code": 200,
      "body": ""
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": { "127.0.0.1:1": 1 }
  }
}'

# ****
# 3. Costrict Web Portal Configuration
# 注意：与参考一致，/cloud 主入口转发到 workflow-web(multica-web)，并 rewrite 为 /workflow-web 前缀
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-portal",
    "nodes": {
      "costrict-web-workflow-web:3000": 1
    },
    "timeout": {
      "connect": 6,
      "send": 6,
      "read": 6
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "pass",
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uris": ["/cloud/*","/cloud"],
  "name": "costrict-web-portal",
  "id": "costrict-web-portal",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "plugins": {
    "proxy-rewrite": {
      "headers": {
        "Host": "costrict-web-workflow-web"
      },
      "regex_uri": [
        "^/cloud(.*)",
        "/workflow-web$1"
      ]
    },
    "limit-count": {
      "count": 600,
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60,
      "key": "$http_zgsm_client_id$http_authorization$cookie_casdoor_session_id",
      "allow_degradation": false
    },
    "limit-req": {
      "rate": 600,
      "burst": 3000,
      "rejected_code": 429,
      "key_type": "var_combination",
      "key": "$http_zgsm_client_id$http_authorization",
      "allow_degradation": false
    },
    "request-id": {
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "algorithm": "uuid"
    }
  },
  "upstream_id": "costrict-web-portal",
  "status": 1
}'

# ****
# (参考含 costrict-web-proxy-portal: /p-cloud/* -> proxy-portal)
# compose 环境未部署 proxy 服务，跳过

# ****
# 4. Costrict Web Gateway Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-gateway",
    "nodes": {
      "costrict-web-gateway:8081": 1
    },
    "timeout": {
      "connect": 6,
      "send": 600,
      "read": 600
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "pass",
    "keepalive_pool": {
      "idle_timeout": 600,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uri": "/cloud-gateway/*",
  "name": "costrict-web-gateway",
  "id": "costrict-web-gateway",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "OPTIONS"
  ],
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "^/cloud-gateway/(.*)",
        "/$1"
      ]
    },
    "limit-count": {
      "count": 600,
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60,
      "key": "$http_zgsm_client_id$http_authorization$cookie_casdoor_session_id",
      "allow_degradation": false
    },
    "limit-req": {
      "rate": 100,
      "burst": 200,
      "rejected_code": 429,
      "key_type": "var_combination",
      "key": "$http_zgsm_client_id$http_authorization",
      "allow_degradation": false
    },
    "request-id": {
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "algorithm": "uuid"
    }
  },
  "upstream_id": "costrict-web-gateway",
  "enable_websocket": true,
  "status": 1
}'

# ****
# 5. Cloud Dashboard Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "cloud-dashboard",
    "nodes": {
      "efficiency-dashboard-server:9990": 1
    },
    "timeout": {
      "connect": 6,
      "send": 6,
      "read": 6
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "pass",
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uri": "/cloud-dashboard/*",
  "name": "cloud-dashboard",
  "id": "cloud-dashboard",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "/cloud-dashboard/(.*)",
        "/$1"
      ]
    },
    "limit-count": {
      "count": 600,
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60,
      "key": "$http_zgsm_client_id$http_authorization$cookie_casdoor_session_id",
      "allow_degradation": false
    },
    "limit-req": {
      "rate": 600,
      "burst": 3000,
      "rejected_code": 429,
      "key_type": "var_combination",
      "key": "$http_zgsm_client_id$http_authorization",
      "allow_degradation": false
    },
    "request-id": {
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "algorithm": "uuid"
    }
  },
  "upstream_id": "cloud-dashboard",
  "status": 1
}'

# ****
# 6. Costrict Web CS User JWKS Configuration
# 供 gitea [costrict] JWT_JWKS_URL 使用: /cs-user/.well-known/jwks
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "cs-user-jwks",
    "nodes": {
      "costrict-web-cs-user:8081": 1
    },
    "timeout": {
      "connect": 6,
      "send": 60,
      "read": 60
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "pass",
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "cs-user-jwks",
  "uri": "/cs-user/.well-known/jwks",
  "name": "cs-user-jwks",
  "methods": [
    "GET"
  ],
  "plugins": {
    "proxy-rewrite": {
      "regex_uri": [
        "/cs-user/(.*)",
        "/$1"
      ]
    }
  },
  "upstream_id": "cs-user-jwks",
  "status": 1
}'

# ****
# (参考含 costrict-web-portal-copy: /cloud/*,/cloud + host=113.108.13.6 -> costrict-web-portal:3000)
# 该路由依赖 Host 头分流，仅用于 k8s 集群公网入口场景，compose 单机环境跳过

# =====================================================================
# Workflow 路由（参考 temp/costrict-web-workflow.sh）
# =====================================================================

# ****
# 7. Workflow Backend Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "workflow-backend",
    "nodes": {
      "costrict-web-workflow-backend:8080": 1
    },
    "timeout": {
      "connect": 6,
      "send": 60,
      "read": 60
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "pass",
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uri": "/workflow-backend/*",
  "name": "workflow-backend",
  "id": "workflow-backend",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "plugins": {
    "limit-count": {
      "_meta": {
        "disable": false
      },
      "allow_degradation": false,
      "count": 600,
      "key": "$cookie_zgsmAdminToken",
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60
    },
    "limit-req": {
      "_meta": {
        "disable": false
      },
      "allow_degradation": false,
      "burst": 30,
      "key": "$cookie_zgsmAdminToken",
      "key_type": "var_combination",
      "nodelay": false,
      "policy": "local",
      "rate": 15,
      "rejected_code": 429
    },
    "proxy-rewrite": {
      "regex_uri": [
        "/workflow-backend/(.*)",
        "/$1"
      ]
    }
  },
  "upstream_id": "workflow-backend",
  "enable_websocket": true,
  "status": 1
}'

# ****
# 8. Workflow Web Configuration
# 与参考一致：/workflow-web* 原样转发（无 proxy-rewrite 剥离前缀），限流插件 disable
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "workflow-web",
    "nodes": {
      "costrict-web-workflow-web:3000": 1
    },
    "timeout": {
      "connect": 6,
      "send": 60,
      "read": 60
    },
    "type": "roundrobin",
    "scheme": "http",
    "pass_host": "pass",
    "keepalive_pool": {
      "idle_timeout": 60,
      "requests": 1000,
      "size": 320
    }
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uri": "/workflow-web*",
  "name": "workflow-web",
  "id": "workflow-web",
  "methods": [
    "GET",
    "POST",
    "PUT",
    "DELETE",
    "PATCH",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
    "PURGE"
  ],
  "plugins": {
    "limit-count": {
      "_meta": {
        "disable": true
      },
      "allow_degradation": false,
      "count": 6000,
      "key": "$cookie_zgsmAdminToken",
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60
    },
    "limit-req": {
      "_meta": {
        "disable": true
      },
      "allow_degradation": false,
      "burst": 30,
      "key": "$cookie_zgsmAdminToken",
      "key_type": "var_combination",
      "nodelay": false,
      "policy": "local",
      "rate": 15,
      "rejected_code": 429
    }
  },
  "upstream_id": "workflow-web",
  "enable_websocket": true,
  "status": 1
}'
