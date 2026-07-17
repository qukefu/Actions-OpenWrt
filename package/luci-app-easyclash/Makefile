include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-easyclash
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=qukefu
PKG_LICENSE:=MIT
PKG_ARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-easyclash
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=EasyClash - Simplified OpenClash control panel
	PKGARCH:=all
endef

define Package/luci-app-easyclash/description
	A simplified web UI for managing OpenClash with node switching,
	client management, and subscription control.
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-easyclash/conffiles
/etc/config/easyclash
endef

define Package/luci-app-easyclash/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if ! uci -q get uhttpd.easyclash >/dev/null; then
		uci add uhttpd easyclash
		uci set uhttpd.easyclash.listen_http='0.0.0.0:8080'
		uci set uhttpd.easyclash.index_page='cgi-bin/luci/admin/services/easyclash/nodes'
		uci set uhttpd.easyclash.home='/www'
		uci set uhttpd.easyclash.cgi_prefix='/cgi-bin'
		uci commit uhttpd
	fi
	/etc/init.d/uhttpd restart 2>/dev/null || true
fi
endef

define Package/luci-app-easyclash/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if uci -q get uhttpd.easyclash >/dev/null; then
		uci delete uhttpd.easyclash
		uci commit uhttpd
		/etc/init.d/uhttpd restart 2>/dev/null || true
	fi
fi
endef

define Package/luci-app-easyclash/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/easyclash

	$(INSTALL_DATA) ./luasrc/controller/easyclash.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DATA) ./luasrc/easyclash.lua $(1)/usr/lib/lua/luci/
	$(INSTALL_DATA) ./luasrc/view/easyclash/nodes.htm $(1)/usr/lib/lua/luci/view/easyclash/
	$(INSTALL_DATA) ./luasrc/view/easyclash/clients.htm $(1)/usr/lib/lua/luci/view/easyclash/
	$(INSTALL_DATA) ./luasrc/view/easyclash/subscribe.htm $(1)/usr/lib/lua/luci/view/easyclash/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/share/easyclash
	$(INSTALL_DIR) $(1)/www/luci-static/resources/easyclash
	$(INSTALL_DIR) $(1)/www

	$(INSTALL_DATA) ./root/etc/config/easyclash $(1)/etc/config/
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-easyclash-http $(1)/etc/uci-defaults/
	$(INSTALL_BIN) ./root/usr/share/easyclash/easyclash.sh $(1)/usr/share/easyclash/
	$(INSTALL_DATA) ./htdocs/luci-static/resources/easyclash/main.css $(1)/www/luci-static/resources/easyclash/
	$(INSTALL_DATA) ./root/www/index.html $(1)/www/
endef

$(eval $(call BuildPackage,luci-app-easyclash))
