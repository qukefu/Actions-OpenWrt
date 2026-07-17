include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-easyclash
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=qukefu
PKG_LICENSE:=MIT

LUCI_TITLE:=EasyClash - Simplified OpenClash control panel
LUCI_DESCRIPTION:=A simplified web UI for managing OpenClash with node switching, client management, and subscription control.
LUCI_DEPENDS:=+luci-base +luci-compat +curl +jq +luci-app-openclash
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk
