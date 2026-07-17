local uci = require("luci.model.uci").cursor()
local ec = require("luci.easyclash")

m = Map("easyclash", translate("Subscription Management"),
	translate("Manage your subscription links for proxy node updates."))

s = m:section(TypedSection, "subscribe", translate("Subscription Links"))
s.addremove = true
s.anonymous = true
s.template = "cbi/tblsection"

name = s:option(Value, "name", translate("Name"))
name.datatype = "string"
name.rmempty = true

url = s:option(Value, "url", translate("URL"))
url.datatype = "string"
url.rmempty = false

status = s:option(DummyValue, "status", translate("Status"))
function status.cfgvalue(self, section)
	local d = m:get(section, "status") or ""
	if d == "" then return translate("Never updated") end
	local s2 = m:get(section, "last_update") or ""
	return s2 .. " " .. d
end

function m.on_after_commit(self)
	luci.sys.call("/usr/share/easyclash/easyclash.sh update_subscription &")
end

return m
