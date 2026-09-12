#!/bin/sh

. ./configure.sh

curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT  -d '{
    "id": "costrict-authz",
    "nodes": {
      "authz:8082": 1
    },
    "type": "roundrobin"
  }'

curl -i  http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-authz",
    "name": "costrict-authz",
    "uris": ["/authz/api/v1/*"],
    "upstream_id": "costrict-authz",
    "plugins": {
      "file-logger": {
        "include_req_body": true,
        "include_resp_body": true,
        "path": "logs/access.log"
      }
    }
  }'

curl -i  http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-authz-oauth-callback",
    "name": "costrict-authz-oauth-callback",
    "uris": ["/auth/callback"],
    "priority": 10,
    "upstream_id": "costrict-authz",
    "plugins": {
      "file-logger": {
        "include_req_body": true,
        "include_resp_body": true,
        "path": "logs/access.log"
      }
    }
  }'

