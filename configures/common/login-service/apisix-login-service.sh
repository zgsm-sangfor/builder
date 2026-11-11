#!/bin/sh

. ./configure.sh

curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
   "id": "costrict-login-service",
    "nodes": [
      {
        "host": "login-service",
        "port": 8080,
        "weight": 2
      }
    ],
    "type": "roundrobin",
    "hash_on": "vars",
    "scheme": "http",
    "pass_host": "pass"
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "costrict-login-oidc",
  "name": "oidc-auth-old-routes",
  "uris": [
    "/oidc-auth/api/v1/plugin*",
    "/oidc-auth/api/v1/manager*"
  ],
  "upstream_id": "costrict-login-service"
}'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "id": "costrict-login-service",
  "upstream_id": "costrict-login-service",
  "status": 1,
  "uris": [
    "/login-service/*"
  ],
  "name": "costrict-login-service",
  "plugins": {
    "limit-req": {
        "rate": 100,
        "burst": 200,
        "rejected_code": 429,
        "key_type": "var",
        "key": "remote_addr"
    },
    "limit-count": {
        "count": 7200,
        "time_window": 60,
        "rejected_code": 429,
        "policy": "local",
        "show_limit_quota_header": true,
        "key_type": "var",
        "key": "remote_addr"
    },
    "request-id": {
      "algorithm": "uuid",
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "range_id": {}
    }
  }
}'