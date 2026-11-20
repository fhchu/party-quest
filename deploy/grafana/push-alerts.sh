#!/usr/bin/env bash
# Pushes the alert rules in alerts.json to Grafana Cloud, with the email
# contact point they notify and a notification policy that sends every
# alert there. Replaces what Grafana has under the same IDs, so the repo is
# the record; rules pushed this way can't be edited in Grafana's interface.
# Run by .github/workflows/release.yml on every release; by hand:
#   GRAFANA_URL=... GRAFANA_API_TOKEN=... ALERT_EMAIL=... deploy/grafana/push-alerts.sh
#
# Needs: curl, jq; GRAFANA_URL (the stack, https://<name>.grafana.net),
# GRAFANA_API_TOKEN (a service account token that can edit alerting and
# folders) and ALERT_EMAIL (where alerts go).
set -euo pipefail
cd "$(dirname "$0")"
: "${GRAFANA_URL:?set GRAFANA_URL}" "${GRAFANA_API_TOKEN:?set GRAFANA_API_TOKEN}" "${ALERT_EMAIL:?set ALERT_EMAIL}"

folder=party-quest
contact=party-quest-email

# api METHOD PATH [BODY]: prints the response body, fails on an HTTP error.
api() {
	curl --fail-with-body --silent --show-error -X "$1" "$GRAFANA_URL$2" \
		-H "Authorization: Bearer $GRAFANA_API_TOKEN" -H 'Content-Type: application/json' \
		${3:+--data "$3"}
}

# Grafana Cloud names its logs data source after the stack, so look it up.
logs_uid=$(api GET /api/datasources | jq -r '[.[] | select(.type == "loki")][0].uid // empty')
[ -n "$logs_uid" ] || { echo "push-alerts.sh: no Loki data source in $GRAFANA_URL" >&2; exit 1; }

if [ "$(api GET "/api/folders/$folder" 2>/dev/null | jq -r '.uid // empty')" != "$folder" ]; then
	api POST /api/folders "$(jq -n --arg uid "$folder" '{uid: $uid, title: "Party Quest"}')" >/dev/null
fi

point=$(jq -n --arg name "$contact" --arg to "$ALERT_EMAIL" \
	'{uid: $name, name: $name, type: "email", settings: {addresses: $to}}')
if api GET "/api/v1/provisioning/contact-points?name=$contact" | jq -e 'length > 0' >/dev/null; then
	api PUT "/api/v1/provisioning/contact-points/$contact" "$point" >/dev/null
else
	api POST /api/v1/provisioning/contact-points "$point" >/dev/null
fi
api PUT /api/v1/provisioning/policies \
	"$(jq -n --arg r "$contact" '{receiver: $r, group_by: ["alertname"]}')" >/dev/null

# What every rule shares: fire on the first evaluation that matches, raise
# an alert if a query itself fails, and treat no data as fine (a log query
# that matches nothing returns none).
# Each query looks back over the longest [Nm] window in alerts.json.
range_sec=$(jq '[.rules[].expr | capture("\\[(?<m>[0-9]+)m\\]").m | tonumber] | max * 60' alerts.json)
# Each rule: the log query (A), then a threshold on it (C) that fires above 0.
group=$(jq --arg logs "$logs_uid" --arg folder "$folder" --argjson range "$range_sec" '{
	title, interval,
	rules: [.rules[] | {
		uid, title, folderUID: $folder, ruleGroup: $folder, condition: "C",
		noDataState: "OK", execErrState: "Error", for: "0s",
		annotations: {summary},
		data: [
			{refId: "A", datasourceUid: $logs, queryType: "instant",
			 relativeTimeRange: {from: $range, to: 0},
			 model: {refId: "A", expr, queryType: "instant"}},
			{refId: "C", datasourceUid: "__expr__",
			 model: {refId: "C", type: "threshold", expression: "A",
			         conditions: [{evaluator: {type: "gt", params: [0]}}]}}
		]
	}]
}' alerts.json)
group_name=$(jq -r .title <<<"$group")
api PUT "/api/v1/provisioning/folder/$folder/rule-groups/$group_name" "$group" >/dev/null
echo "pushed $(jq '.rules | length' <<<"$group") alert rules to $GRAFANA_URL"
