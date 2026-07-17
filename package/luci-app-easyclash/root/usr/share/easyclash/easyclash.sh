#!/bin/sh

CLASH_PORT=$(uci -q get openclash.config.cn_port || echo "9090")
CLASH_SECRET=$(uci -q get openclash.config.dashboard_password || echo "")
CLASH_API="http://127.0.0.1:${CLASH_PORT}"
SPEED_URL="http://www.gstatic.com/generate_204"
SPEED_TIMEOUT=5000

_auth_header() {
	if [ -n "$CLASH_SECRET" ]; then
		echo "-H \"Authorization: Bearer ${CLASH_SECRET}\""
	fi
}

_curl() {
	local url="$1"
	shift
	eval curl -s $(_auth_header) "$@" "\"${url}\""
}

get_proxies() {
	_curl "${CLASH_API}/proxies"
}

get_proxy_groups() {
	curl -s "${CLASH_API}/proxies" | jq '[.proxies | to_entries[] | select(.value.type == "Selector" or .value.type == "URLTest" or .value.type == "Fallback" or .value.type == "LoadBalance") | {name: .key, type: .value.type, now: .value.now, all: .value.all}]'
}

switch_proxy() {
	local group="$1"
	local name="$2"
	curl -s -X PUT "${CLASH_API}/proxies/$(urlencode "$group")" \
		-H "Content-Type: application/json" \
		-d "{\"name\": \"$name\"}"
}

speed_test() {
	local name="$1"
	local timeout="${2:-$SPEED_TIMEOUT}"
	local url="${3:-$SPEED_URL}"
	result=$(curl -s "${CLASH_API}/proxies/$(urlencode "$name")/delay?url=$(urlencode "$url")&timeout=$timeout")
	delay=$(echo "$result" | jq -r '.delay // -1')
	if [ "$delay" = "-1" ] || [ "$delay" = "null" ]; then
		echo "timeout"
	else
		echo "$delay"
	fi
}

get_traffic() {
	curl -s "${CLASH_API}/connections" | jq '[.connections[]? | {id, upload: .upload, download: .download, src: (.metadata.sourceIP // "unknown"), dst: (.metadata.destinationIP // "unknown"), host: (.metadata.host // "")}]'
}

get_client_traffic() {
	local ip="$1"
	get_traffic | jq --arg ip "$ip" '[.[] | select(.src == $ip)] | {connections: length, upload: ([.[].upload] | add // 0), download: ([.[].download] | add // 0)}'
}

urlencode() {
	local string="$1"
	local strlen=${#string}
	local encoded=""
	local pos c o

	for (( pos=0 ; pos<strlen ; pos++ )); do
		c=${string:$pos:1}
		case "$c" in
			[-_.~a-zA-Z0-9/] ) o="${c}" ;;
			* ) printf -v o '%%%02x' "'$c" ;;
		esac
		encoded+="${o}"
	done
	echo "${encoded}"
}

proxy_enable() {
	local ip="$1"
	mkdir -p /etc/easyclash
	local rule="SRC-IP-CIDR,${ip}/32,Proxy"
	if ! grep -qF "${rule}" /etc/easyclash/rules.list 2>/dev/null; then
		echo "${rule}" >> /etc/easyclash/rules.list
	fi
	reload_rules
}

proxy_disable() {
	local ip="$1"
	local rule="SRC-IP-CIDR,${ip}/32,Proxy"
	if [ -f /etc/easyclash/rules.list ] && grep -qF "${rule}" /etc/easyclash/rules.list 2>/dev/null; then
		sed -i "\|${rule}|d" /etc/easyclash/rules.list
	fi
	reload_rules
}

reload_rules() {
	local config
	if [ -s /etc/easyclash/rules.list ]; then
		local rules_json
		rules_json=$(while read -r line; do
			[ -z "$line" ] && continue
			echo "\"$line\","
		done < /etc/easyclash/rules.list)
		rules_json="${rules_json%,}"
		rules_json="[${rules_json},\"MATCH,DIRECT\"]"
	else
		rules_json='["MATCH,DIRECT"]'
	fi

	config=$(curl -s "${CLASH_API}/configs")
	if [ -z "$config" ]; then
		return 1
	fi

	config=$(echo "$config" | jq --argjson rules "$rules_json" '.rules = $rules')
	curl -s -X PUT "${CLASH_API}/configs?force=true" \
		-H "Content-Type: application/json" \
		-d "$config" > /dev/null
}

restart_clash() {
	if /etc/init.d/openclash enabled >/dev/null 2>&1; then
		/etc/init.d/openclash restart >/dev/null 2>&1
	fi
}

update_subscription() {
	if [ -x /usr/share/openclash/openclash.sh ]; then
		/usr/share/openclash/openclash.sh >/dev/null 2>&1 &
	fi
}

get_clash_mode() {
	curl -s "${CLASH_API}/configs" | jq -r '.mode // "unknown"'
}

is_clash_running() {
	curl -s -o /dev/null -w '%{http_code}' "${CLASH_API}" | grep -q 200
}

get_uptime() {
	if is_clash_running; then
		local pid=$(pgrep -f "clash" | head -1)
		if [ -n "$pid" ] && [ -f "/proc/$pid/stat" ]; then
			local seconds=$(awk '{print int($22 / 100)}' "/proc/$pid/stat" 2>/dev/null)
			if [ -n "$seconds" ]; then
				local days=$((seconds / 86400))
				local hours=$(((seconds % 86400) / 3600))
				local mins=$(((seconds % 3600) / 60))
				if [ $days -gt 0 ]; then
					echo "${days}d${hours}h"
				elif [ $hours -gt 0 ]; then
					echo "${hours}h${mins}m"
				else
					echo "${mins}m"
				fi
				return
			fi
		fi
	fi
	echo "stopped"
}

get_dhcp_leases() {
	awk '{printf "{\"expires\":%s,\"mac\":\"%s\",\"ip\":\"%s\",\"hostname\":\"%s\"}\n", $1, $2, $3, $4}' /tmp/dhcp.leases 2>/dev/null | jq -s '.'
}

get_arp_table() {
	awk '{printf "{\"ip\":\"%s\",\"mac\":\"%s\"}\n", $1, $4}' /proc/net/arp 2>/dev/null | jq -s '[.[] | select(.mac != "00:00:00:00:00:00")]'
}

case "$1" in
	get_proxies) get_proxies ;;
	get_proxy_groups) get_proxy_groups ;;
	switch_proxy) switch_proxy "$2" "$3" ;;
	speed_test) speed_test "$2" "$3" ;;
	get_traffic) get_traffic ;;
	get_client_traffic) get_client_traffic "$2" ;;
	proxy_enable) proxy_enable "$2" ;;
	proxy_disable) proxy_disable "$2" ;;
	reload_rules) reload_rules ;;
	restart_clash) restart_clash ;;
	update_subscription) update_subscription ;;
	get_clash_mode) get_clash_mode ;;
	is_clash_running) is_clash_running ;;
	get_uptime) get_uptime ;;
	get_dhcp_leases) get_dhcp_leases ;;
	get_arp_table) get_arp_table ;;
	*)
		echo "Usage: $0 {get_proxies|get_proxy_groups|switch_proxy|speed_test|get_traffic|proxy_enable|proxy_disable|reload_rules|update_subscription|get_clash_mode|is_clash_running|get_uptime|get_dhcp_leases|get_arp_table}"
		exit 1
		;;
esac
