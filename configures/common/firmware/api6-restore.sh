#!/bin/sh

# 功能：从 JSON 文件恢复所有路由和上游配置到 APISIX

. ./configure.sh

curl -X POST http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -d @api6-routes.json
curl -X POST http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -d @api6-upstreams.json
