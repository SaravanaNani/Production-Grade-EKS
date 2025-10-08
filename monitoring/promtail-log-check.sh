# 1) What labels exist?
curl -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" | jq .

# 2) Which jobs?
curl -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" | jq .

# 3) Streams for each job (instant)
curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="varlogs"}' | jq '.data.result | length'

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="kubernetes-pods"}' | jq '.data.result | length'

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="app-logs"}' | jq '.data.result | length'

# 4) Recent log lines in last 5 minutes (range); MUST use bash vars (no single-quote subshells)
START=$(($(date +%s)-300))000000000
END=$(date +%s)000000000

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query_range" \
  --data-urlencode "query={job=\"kubernetes-pods\"}" \
  --data-urlencode "limit=10" \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" | jq '.data.result | length'

curl -G -s "http://$BASTION_PVT_IP:3100/loki/api/v1/query_range" \
  --data-urlencode "query={job=\"app-logs\",namespace=\"adq-dev\"}" \
  --data-urlencode "limit=10" \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" | jq '.data.result | length'


#   # Extpected Outputs:
#   {
#   "status": "success",
#   "data": [
#     "container",
#     "filename",
#     "job",
#     "namespace",
#     "pod"
#   ]
# }
# {
#   "status": "success",
#   "data": [
#     "app-logs",
#     "kubernetes-pods",
#     "varlogs"
#   ]
# }
# 9
# 5
# 1
# 3
# 1

