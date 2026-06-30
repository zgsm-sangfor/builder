#!/bin/sh

. ./configure.sh

# ****
# Costrict Web API Configuration
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
  "host": "shenma.sangfor.com.cn",
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
# Costrict Web PROXY Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-proxy",
    "nodes": {
      "costrict-web-proxy:8090": 1
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
  "uri": "/p-cloud-api/*",
  "name": "costrict-web-proxy",
  "id": "costrict-web-proxy",
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
        "/p-cloud-api/(.*)",
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
  "upstream_id": "costrict-web-proxy",
  "enable_websocket": true,
  "status": 1
}'

# ****
# Block Memory Route: intercept /cloud-api/api/memories* and return 200 directly
curl -i http://$APISIX_ADDR/apisix/admin/routes/block-memory -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "block-memory",
  "host": "shenma.sangfor.com.cn",
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
# Costrict Web Portal Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-portal",
    "nodes": {
      "costrict-web-portal:3000": 1
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
  "uri": "/cloud*",
  "name": "costrict-web-portal",
  "id": "costrict-web-portal",
  "host": "shenma.sangfor.com.cn",
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
        "Host": "portal-costrict-web-portal.costrict-web.svc.cluster.local"
      },
      "regex_uri": [
        "^/cloud/(.*)",
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
  "upstream_id": "costrict-web-portal",
  "status": 1
}'

# ****
# Costrict Web Proxy Portal Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-proxy-portal",
    "nodes": {
      "costrict-web-portal:3000": 1
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
  "uri": "/p-cloud/*",
  "name": "costrict-web-proxy-portal",
  "id": "costrict-web-proxy-portal",
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
        "Host": "portal-costrict-web-proxy-portal.costrict-web.svc.cluster.local"
      },
      "regex_uri": [
        "^/p-cloud/(.*)",
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
  "upstream_id": "costrict-web-proxy-portal",
  "status": 1
}'

# ****
# Costrict Web Gateway Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-web-gateway",
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
  "host": "shenma.sangfor.com.cn",
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
# Cloud Dashboard Configuration
curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "cloud-dashboard",
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
  "host": "shenma.sangfor.com.cn",
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
