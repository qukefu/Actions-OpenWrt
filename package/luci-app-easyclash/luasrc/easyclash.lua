local uci = require("luci.model.uci").cursor()
local json = require("luci.jsonc")
local fs = require("nixio.fs")

local M = {}

local SCRIPT = "/usr/share/easyclash/easyclash.sh"

function M.get_clash_secret()
	local secret = uci:get("openclash", "config", "dashboard_password") or ""
	return secret
end

function M.get_clash_port()
	local port = uci:get("openclash", "config", "cn_port") or "9090"
	return port
end

function M.get_clash_api_base()
	local port = M.get_clash_port()
	return "http://127.0.0.1:" .. port
end

function M.shell_exec(cmd)
	local p = io.popen(cmd .. " 2>/dev/null")
	if not p then return nil end
	local out = p:read("*a")
	p:close()
	return out
end

function M.clash_api(path)
	local secret = M.get_clash_secret()
	local base = M.get_clash_api_base()
	local u = fs.access("/usr/bin/curl") and "/usr/bin/curl" or "curl"
	local auth = ""
	if secret ~= "" then
		auth = ' -H "Authorization: Bearer ' .. secret .. '"'
	end
	local cmd = u .. ' -s --connect-timeout 3' .. auth .. ' "' .. base .. path .. '"'
	local p = io.popen(cmd)
	if not p then return nil end
	local out = p:read("*a")
	p:close()
	return out
end

function M.get_proxies()
	local raw = M.clash_api("/proxies")
	if not raw or raw == "" then return {} end
	local ok, data = pcall(json.parse, raw)
	if not ok then return {} end
	local proxies = {}
	for name, info in pairs(data.proxies or {}) do
		proxies[name] = info
	end
	return proxies
end

function M.get_proxy_groups()
	local proxies = M.get_proxies()
	local cache = M.get_speed_cache()
	local groups = {}
	for name, info in pairs(proxies) do
		local t = info.type
		if t == "Selector" or t == "URLTest" or t == "Fallback" or t == "LoadBalance" then
			local nodes = {}
			for _, node in ipairs(info.all or {}) do
				local cached = nil
				if cache[node] then
					local d = tonumber(cache[node])
					if d and d >= 0 then cached = d end
				end
				table.insert(nodes, {name = node, cached_delay = cached})
			end
			local g = {
				name = name,
				type = t,
				now = info.now or "",
				nodes = nodes,
			}
			table.insert(groups, g)
		end
	end
	table.sort(groups, function(a, b) return a.name < b.name end)
	return groups
end

function M.get_speed_cache()
	local f = io.open("/tmp/easyclash_speedtest.json", "r")
	if not f then return {} end
	local raw = f:read("*a")
	f:close()
	local ok, data = pcall(json.parse, raw)
	if not ok then return {} end
	return data
end

function M.save_speed_cache(name, delay)
	local cache = M.get_speed_cache()
	cache[name] = tostring(delay)
	local f = io.open("/tmp/easyclash_speedtest.json", "w")
	if f then
		f:write(json.stringify(cache))
		f:close()
	end
end

function M.urlencode(s)
	if not s then return "" end
	return (s:gsub("([^%w%-_%.~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function M.speed_test(name, timeout, url)
	timeout = timeout or 2000
	url = url or "http://www.gstatic.com/generate_204"
	local secret = M.get_clash_secret()
	local auth = ""
	if secret ~= "" then auth = ' -H "Authorization: Bearer ' .. secret .. '"' end
	local u = "curl -s --connect-timeout 5" .. auth .. " \"" .. M.get_clash_api_base() .. "/proxies/" .. M.urlencode(name) .. "/delay?url=" .. M.urlencode(url) .. "&timeout=" .. timeout .. "\""
	local p = io.popen(u)
	if not p then return -1 end
	local out = p:read("*a")
	p:close()
	local ok, data = pcall(json.parse, out)
	if not ok or not data then return -1 end
	if data.delay then return data.delay end
	return -1
end

function M.switch_proxy(group, name)
	local secret = M.get_clash_secret()
	local auth = ""
	if secret ~= "" then auth = ' -H "Authorization: Bearer ' .. secret .. '"' end
	local u = "curl -s -X PUT" .. auth .. " \"" .. M.get_clash_api_base() .. "/proxies/" .. M.urlencode(group) .. "\" -H \"Content-Type: application/json\" -d '{\"name\":\"" .. name .. "\"}'"
	local p = io.popen(u)
	if not p then return false end
	p:read("*a")
	p:close()
	return true
end

function M.get_clash_info()
	local raw = M.clash_api("")
	if not raw or raw == "" then
		return {running = false, mode = "unknown", uptime = "stopped"}
	end
	local ok, data = pcall(json.parse, raw)
	if not ok or not data then
		return {running = false, mode = "unknown", uptime = "stopped"}
	end
	-- try to read uptime from /proc
	local pid = nil
	local cmd_out = M.shell_exec("pgrep -f clash | head -1")
	if cmd_out then
		pid = tonumber(cmd_out:match("%d+"))
	end
	local uptime_txt = "running"
	if pid then
		local stat = fs.readfile("/proc/" .. pid .. "/stat")
		if stat then
			local fields = {}
			for f in stat:gmatch("%S+") do table.insert(fields, f) end
			if #fields >= 22 then
				local starttime = tonumber(fields[22]) or 0
				local clk_tck = tonumber(M.shell_exec("getconf CLK_TCK")) or 100
				local uptime = tonumber(M.shell_exec("awk '{print int($1)}' /proc/uptime")) or 0
				local elapsed = uptime - (starttime / clk_tck)
				if elapsed > 0 then
					local days = math.floor(elapsed / 86400)
					local hours = math.floor((elapsed % 86400) / 3600)
					local mins = math.floor((elapsed % 3600) / 60)
					if days > 0 then
						uptime_txt = days .. "d" .. hours .. "h"
					elseif hours > 0 then
						uptime_txt = hours .. "h" .. mins .. "m"
					else
						uptime_txt = mins .. "m"
					end
				end
			end
		end
	end
	return {
		running = true,
		mode = data.mode or "unknown",
		uptime = uptime_txt,
	}
end

function M.get_clients()
	local leases_raw = M.shell_exec("cat /tmp/dhcp.leases 2>/dev/null")
	local arp_raw = M.shell_exec("cat /proc/net/arp 2>/dev/null")
	local clients = {}
	local seen = {}

	-- parse ARP table for active connections
	local arp_map = {}
	if arp_raw and arp_raw ~= "" then
		for line in arp_raw:gmatch("[^\n]+") do
			local fields = {}
			for f in line:gmatch("%S+") do table.insert(fields, f) end
			if #fields >= 4 then
				local ip = fields[1]
				local mac = fields[4]
				if mac ~= "00:00:00:00:00:00" and mac ~= "HW" and ip ~= "IP" then
					arp_map[mac:lower()] = {ip = ip, online = true}
				end
			end
		end
	end

	-- parse DHCP leases
	if leases_raw and leases_raw ~= "" then
		for line in leases_raw:gmatch("[^\n]+") do
			local expires, mac, ip, hostname = line:match("^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)")
			if mac and ip then
				local m = mac:lower()
				if not seen[m] then
					seen[m] = true
					local h = hostname or ""
					if h == "*" then h = "" end
					local arp_info = arp_map[m]
					local online = true
					-- check if lease is expired or not in arp
					if tonumber(expires or 0) == 0 and not arp_info then
						online = false
					elseif not arp_info then
						online = (tonumber(expires or 0) > os.time())
					end
					table.insert(clients, {
						mac = m,
						ip = ip,
						hostname = h,
						online = online,
					})
				end
			end
		end
	end

	-- add devices only in arp (static IPs, etc.)
	for mac, info in pairs(arp_map) do
		if not seen[mac] then
			seen[mac] = true
			table.insert(clients, {
				mac = mac,
				ip = info.ip,
				hostname = "",
				online = true,
			})
		end
	end

	-- load saved config from UCI
	uci:foreach("easyclash", "device", function(s)
		if s.mac then
			local m = s.mac:lower()
			for _, c in ipairs(clients) do
				if c.mac == m then
					c.alias = s.name
					c.favorite = (s.favorite == "1")
					c.proxy = (s.proxy == "1")
				end
			end
		end
	end)

	-- sort: online first, then favorites within groups
	table.sort(clients, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		if (a.favorite or false) ~= (b.favorite or false) then
			return (a.favorite or false)
		end
		return (a.alias or a.hostname or "") < (b.alias or b.hostname or "")
	end)

	return clients
end

function M.get_client_traffic(ip)
	local raw = M.clash_api("/connections")
	if not raw or raw == "" then return {connections = 0, upload = 0, download = 0} end
	local ok, data = pcall(json.parse, raw)
	if not ok then return {connections = 0, upload = 0, download = 0} end

	local up = 0
	local down = 0
	local count = 0
	for _, conn in ipairs(data.connections or {}) do
		if conn.metadata and conn.metadata.sourceIP == ip then
			count = count + 1
			up = up + (tonumber(conn.upload) or 0)
			down = down + (tonumber(conn.download) or 0)
		end
	end
	return {connections = count, upload = up, download = down}
end

function M.save_device_setting(mac, field, value)
	mac = mac:lower()
	local found = false
	uci:foreach("easyclash", "device", function(s)
		if s.mac and s.mac:lower() == mac then
			found = true
			uci:set("easyclash", s[".name"], field, value)
		end
	end)
	if not found then
		uci:section("easyclash", "device", nil, {mac = mac, [field] = value})
	end
	uci:save("easyclash")
	uci:commit("easyclash")
end

function M.toggle_proxy(mac, ip)
	local enabled = nil
	uci:foreach("easyclash", "device", function(s)
		if s.mac and s.mac:lower() == mac:lower() then
			enabled = (s.proxy ~= "1")
		end
	end)
	if enabled == nil then enabled = true end

	M.save_device_setting(mac, "proxy", enabled and "1" or "0")

	if enabled then
		M.shell_exec(SCRIPT .. ' proxy_enable "' .. ip .. '"')
	else
		M.shell_exec(SCRIPT .. ' proxy_disable "' .. ip .. '"')
	end

	return enabled
end

function M.toggle_favorite(mac)
	local fav = nil
	uci:foreach("easyclash", "device", function(s)
		if s.mac and s.mac:lower() == mac:lower() then
			fav = (s.favorite ~= "1")
		end
	end)
	if fav == nil then fav = true end
	M.save_device_setting(mac, "favorite", fav and "1" or "0")
	return fav
end

function M.save_alias(mac, name)
	M.save_device_setting(mac, "name", name)
end

function M.get_subscriptions()
	local subs = {}
	uci:foreach("easyclash", "subscribe", function(s)
		table.insert(subs, {
			url = s.url or "",
			name = s.name or "",
			last_update = s.last_update or "",
			status = s.status or "",
		})
	end)
	return subs
end

function M.add_subscription(url, name)
	uci:section("easyclash", "subscribe", nil, {
		url = url,
		name = name or "",
		last_update = "",
		status = "",
	})
	uci:save("easyclash")
	uci:commit("easyclash")
end

function M.delete_subscription(idx)
	local i = 0
	uci:foreach("easyclash", "subscribe", function(s)
		if i == idx then
			uci:delete("easyclash", s[".name"])
		end
		i = i + 1
	end)
	uci:save("easyclash")
	uci:commit("easyclash")
end

function M.update_subscription()
	os.execute(SCRIPT .. " update_subscription &")
end

function M.format_traffic(bytes)
	if not bytes or bytes == 0 then return "0" end
	bytes = tonumber(bytes)
	if not bytes then return "0" end
	if bytes >= 1024 * 1024 then
		return string.format("%.1fM", bytes / (1024 * 1024))
	elseif bytes >= 1024 then
		return string.format("%.1fK", bytes / 1024)
	else
		return string.format("%d", bytes)
	end
end

return M
