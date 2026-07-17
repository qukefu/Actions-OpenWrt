module("luci.controller.easyclash", package.seeall)

local ec = require("luci.easyclash")
local json = require("luci.jsonc")
local http = require("luci.http")

function index()
	local e

	-- Main entry
	e = entry({"admin", "services", "easyclash"},
		alias("admin", "services", "easyclash", "nodes"),
		_("EasyClash"), 60)
	e.sysauth = false

	-- Nodes tab
	e = entry({"admin", "services", "easyclash", "nodes"},
		template("easyclash/nodes"), _("Nodes"), 10)
	e.leaf = true
	e.sysauth = false

	-- Clients tab
	e = entry({"admin", "services", "easyclash", "clients"},
		template("easyclash/clients"), _("Clients"), 20)
	e.leaf = true
	e.sysauth = false

	-- Subscribe tab
	e = entry({"admin", "services", "easyclash", "subscribe"},
		cbi("easyclash/subscribe"), _("Subscribe"), 30)
	e.leaf = true
	e.sysauth = false

	-- XHR endpoints
	e = entry({"admin", "services", "easyclash", "api", "status"}, call("api_status"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "proxies"}, call("api_proxies"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "switch"}, call("api_switch"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "speedtest"}, call("api_speedtest"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "clients"}, call("api_clients"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "toggle_proxy"}, call("api_toggle_proxy"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "toggle_favorite"}, call("api_toggle_favorite"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "save_alias"}, call("api_save_alias"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "traffic"}, call("api_traffic"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "update_sub"}, call("api_update_sub"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "add_sub"}, call("api_add_sub"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "del_sub"}, call("api_del_sub"))
	e.sysauth = false
	e = entry({"admin", "services", "easyclash", "api", "subs"}, call("api_subs"))
	e.sysauth = false
end

function json_response(data)
	http.prepare_content("application/json")
	http.write(json.stringify(data))
end

function is_post()
	return http.getenv("REQUEST_METHOD") == "POST"
end

function get_post_param(key)
	return http.formvalue(key)
end

function api_status()
	local info = ec.get_clash_info()
	json_response(info)
end

function api_proxies()
	local groups = ec.get_proxy_groups()
	json_response(groups)
end

function api_switch()
	local group = get_post_param("group")
	local name = get_post_param("name")
	if not group or not name then
		json_response({ok = false, msg = "missing params"})
		return
	end
	local ok = ec.switch_proxy(group, name)
	json_response({ok = ok})
end

function api_speedtest()
	local name = get_post_param("name")
	if not name then
		json_response({ok = false, msg = "missing params"})
		return
	end
	local delay = ec.speed_test(name)
	json_response({ok = true, name = name, delay = delay})
end

function api_clients()
	local clients = ec.get_clients()
	json_response(clients)
end

function api_toggle_proxy()
	local mac = get_post_param("mac")
	local ip = get_post_param("ip")
	if not mac or not ip then
		json_response({ok = false, msg = "missing params"})
		return
	end
	local enabled = ec.toggle_proxy(mac, ip)
	json_response({ok = true, enabled = enabled})
end

function api_toggle_favorite()
	local mac = get_post_param("mac")
	if not mac then
		json_response({ok = false, msg = "missing params"})
		return
	end
	local fav = ec.toggle_favorite(mac)
	json_response({ok = true, favorite = fav})
end

function api_save_alias()
	local mac = get_post_param("mac")
	local name = get_post_param("name")
	if not mac or not name then
		json_response({ok = false, msg = "missing params"})
		return
	end
	ec.save_alias(mac, name)
	json_response({ok = true})
end

function api_traffic()
	local ip = get_post_param("ip")
	if not ip then
		json_response({ok = false, msg = "missing params"})
		return
	end
	local t = ec.get_client_traffic(ip)
	json_response({ok = true, ip = ip, connections = t.connections, upload = t.upload, download = t.download})
end

function api_update_sub()
	ec.update_subscription()
	json_response({ok = true})
end

function api_subs()
	local subs = ec.get_subscriptions()
	json_response(subs)
end

function api_add_sub()
	local url = get_post_param("url")
	local name = get_post_param("name")
	if not url then
		json_response({ok = false, msg = "missing url"})
		return
	end
	ec.add_subscription(url, name or "")
	json_response({ok = true})
end

function api_del_sub()
	local idx = tonumber(get_post_param("idx"))
	if idx == nil then
		json_response({ok = false, msg = "missing idx"})
		return
	end
	ec.delete_subscription(idx)
	json_response({ok = true})
end
