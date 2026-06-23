#!/bin/sh

. ./configure.sh

curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT  -d '{
    "id": "license-manager",
    "nodes": {
      "license-manager:10000": 1
    },
    "type": "roundrobin"
  }'

curl -i  http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "license-manager",
    "name": "license-manager",
    "uris": ["/license-manager/api/v1/*"],
    "upstream_id": "license-manager",
    "plugins": {
      "limit-count": {
        "allow_degradation": false,
        "count": 10000,
        "key_type": "var_combination",
        "key": "$remote_addr $http_x_forwarded_for",
        "policy": "local",
        "rejected_code": 429,
        "show_limit_quota_header": true,
        "time_window": 86400
      },
      "limit-req": {
        "allow_degradation": false,
        "burst": 30,
        "key": "$remote_addr $http_x_forwarded_for",
        "key_type": "var_combination",
        "nodelay": false,
        "policy": "local",
        "rate": 30,
        "rejected_code": 429
      }
    }
  }'

