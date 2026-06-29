#!/bin/sh

. ./configure.sh

curl -i "http://$APISIX_ADDR/apisix/admin/upstreams" -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "metrics-kanban",
  "nodes": {
    "efficiency-dashboard-portal:80": 1
  },
  "type": "roundrobin",
  "hash_on": "vars",
  "scheme": "http",
  "pass_host": "pass"
}'

curl -i "http://$APISIX_ADDR/apisix/admin/routes" -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "metrics-kanban",
  "upstream_id": "metrics-kanban",
  "status": 1,
  "uris": [
    "/kanban/*"
  ],
  "name": "metrics-kanban",
  "plugins": {
    "limit-count": {
      "allow_degradation": false,
      "count": 3000,
      "key": "$http_authorization",
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60
    },
    "limit-req": {
      "allow_degradation": false,
      "burst": 2000,
      "key": "$http_authorization",
      "key_type": "var_combination",
      "nodelay": false,
      "policy": "local",
      "rate": 500,
      "rejected_code": 429
    },
    "request-id": {
      "algorithm": "uuid",
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "range_id": {}
    }
  }
}'
