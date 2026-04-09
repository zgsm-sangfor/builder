#!/bin/sh

. ./configure.sh

curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "user-indicator",
    "nodes": {
      "user-indicator:8080": 1
    },
    "type": "roundrobin"
  }'

curl -i http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
  "uris": ["/user-indicator/*"],
  "id": "user-indicator",
  "name": "user-indicator-collection",
  "upstream_id": "user-indicator",
  "plugins": {
    "limit-req": {
      "rate": 500,
      "burst": 2000,
      "rejected_code": 429,
      "key_type": "var_combination",
      "key": "$http_authorization",
      "allow_degradation": 'false'
    },
    "limit-count": {
      "count": 10,
      "key": "$http_authorization",
      "key_type": "var_combination",
      "policy": "local",
      "rejected_code": 429,
      "show_limit_quota_header": true,
      "time_window": 60,
      "allow_degradation": 'false'
    },
    "openid-connect": {
      "client_id": "'"$OIDC_CLIENT_ID"'",
      "client_secret": "'"$OIDC_CLIENT_SECRET"'",
      "discovery": "'"$OIDC_DISCOVERY_ADDR"'",
      "introspection_endpoint": "'"$OIDC_INTROSPECTION_ENDPOINT"'",
      "introspection_endpoint_auth_method": "client_secret_basic",
      "introspection_interval": 600,
      "bearer_only": true,
      "set_userinfo_header": true,
      "ssl_verify": false,
      "scope": "openid profile email"
    },
    "request-id": {
      "header_name": "X-Request-Id",
      "include_in_response": true,
      "algorithm": "uuid"
    }
  }
}'
