#!/bin/sh

# 功能：从 APISIX 保存所有路由和上游配置到 JSON 文件

. ./configure.sh

curl http://$APISIX_ADDR/apisix/admin/routes -H "$AUTH" -H "$TYPE" -X GET > api6-routes.json
curl http://$APISIX_ADDR/apisix/admin/upstreams -H "$AUTH" -H "$TYPE" -X GET > api6-upstreams.json
