#!/bin/sh

. ./configure.sh

curl -i http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X PUT  -d '{
    "id": "costrict-orgd",
    "nodes": {
      "orgd:8083": 1
    },
    "type": "roundrobin"
  }'

curl -i  http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X PUT -d '{
    "id": "costrict-orgd",
    "name": "costrict-orgd",
    "uris": ["/orgd/api/v1/*"],
    "upstream_id": "costrict-orgd",
    "plugins": {
      "forward-auth": {
        "uri": "http://authz:8082/costrict-authz/api/v1/permissions/auth",
        "request_headers": ["X-User-ID", "Authorization"],
        "upstream_headers": ["X-User-ID"],
        "timeout": 3000
      },
      "file-logger": {
        "include_req_body": true,
        "include_resp_body": true,
        "path": "logs/access.log"
      }
    }
  }'

