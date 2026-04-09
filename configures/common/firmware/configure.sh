#!/bin/bash

. ./.env

#---------------------------------------------------------
# apisix设置，无需修改
#---------------------------------------------------------

APISIX_ADDR="127.0.0.1:${PORT_APISIX_API}"
AUTH="X-API-KEY: ${APIKEY_APISIX_ADMIN}"
TYPE="Content-Type: application/json"

#---------------------------------------------------------
# 大模型相关设置，请根据实际部署情况设置
#---------------------------------------------------------
# 模型服务器的IP，需要根据实际情况设置
MODEL_SERVER_ADDR="127.0.0.1:${PORT_ONEAPI}"
CHAT_DEFAULT_MODEL="GLM-4.5-FP8"

# 代码补全模型的BASEURL,MODEL,APIKEY
COMPLETION_BASEURL="http://${MODEL_SERVER_ADDR}/v1/completions"
COMPLETION_MODEL="DeepSeek-Coder-V2-Lite"
COMPLETION_APIKEY=""

# 向量嵌入模型的BASEURL,MODEL和APIKEY
EMBEDDER_BASEURL="http://${MODEL_SERVER_ADDR}/v1/embeddings"
EMBEDDER_MODEL="embedding"
EMBEDDER_APIKEY=""

# RAG排序模型的BASEURL,MODEL和APIKEY
RERANKER_BASEURL="http://${MODEL_SERVER_ADDR}/v1/rerank"
RERANKER_MODEL="rerank"
RERANKER_APIKEY=""
