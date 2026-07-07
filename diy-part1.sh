#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
# helloworld already includes passwall/ssr-plus/v2ray
echo 'src-git helloworld https://github.com/fw876/helloworld' >>feeds.conf.default
# OpenClash needs to be added as package via git clone
git clone --depth=1 https://github.com/vernesong/OpenClash package/luci-app-openclash
