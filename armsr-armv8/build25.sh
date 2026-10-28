#!/bin/bash
# Log file for debugging
source shell/apk-custom-packages.sh
echo "第三方apk软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库（25.12 使用 apk）==============
  echo "🔄 正在同步第三方软件仓库 Cloning apk repo..."
  git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo

  # 拷贝 run/arm64 下所有 run 文件和 apk 文件到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-apk-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run

  # 使用 QiuSimons 预编译的 daed 取代官方源版本
  # 注意：必须在 apk-prepare-packages.sh 之前下载，才能被一并打包进本地 packages 目录
  sh shell/download-daed.sh apk aarch64

  # 解压并拷贝 apk 到 packages 目录
  sh shell/apk-prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# ============= honk（daeuniverse 官方源，仅 25.12 / 内核 6.12+）=============
# honk 需要 Linux 6.12+ 与 BTF，ImmortalWrt 25.12 内核已内置 BTF
echo "🔄 [honk] 配置 daeuniverse 软件源..."
wget -qO keys/daeuniverse.pem https://openwrt.daeuniverse.org/public-key.pem || {
    echo "❌ [honk] 下载 daeuniverse 公钥失败"
    exit 1
}
if ! grep -q "openwrt.daeuniverse.org" repositories; then
    echo "https://openwrt.daeuniverse.org/25.12/packages/aarch64_generic/packages.adb" >> repositories
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建 QEMU-arm64 25.12 固件..."

# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-app-ttyd"
PACKAGES="$PACKAGES luci-app-openclash"
# honk（daeuniverse eBPF 内核）+ LuCI 面板
PACKAGES="$PACKAGES honk luci-app-honk luci-i18n-daeuniverse-zh-cn"
# ADD by WJB
PACKAGES="$PACKAGES luci-app-msd_lite"
PACKAGES="$PACKAGES luci-i18n-msd_lite-zh-cn"
PACKAGES="$PACKAGES nano-plus"
PACKAGES="$PACKAGES luci-proto-wireguard"
PACKAGES="$PACKAGES luci-app-frpc"
PACKAGES="$PACKAGES luci-i18n-frpc-zh-cn"
# 网络诊断工具
PACKAGES="$PACKAGES bind-dig"
PACKAGES="$PACKAGES tcpdump"
PACKAGES="$PACKAGES mtr-nojson"
PACKAGES="$PACKAGES iperf3"
# 系统工具
PACKAGES="$PACKAGES htop"

# 文件管理器
# PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# PACKAGES="$PACKAGES luci-app-filetransfer"
# 静态文件服务器dufs(推荐)
# PACKAGES="$PACKAGES luci-i18n-dufs-zh-cn"

# ======== shell/apk-custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# nikki 的 LuCI 中文包依赖 app 和核心，确保一并安装
if echo "$CUSTOM_PACKAGES" | grep -q "nikki"; then
    PACKAGES="$PACKAGES luci-app-nikki nikki"
fi

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ 已选择 luci-app-ssr-plus，添加 mihomo core"
    mkdir -p files/usr/bin
    # Download mihomo
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-arm64-v1.19.24.gz"
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
    echo "✅ 已下载 mihomo core"
    ls -lah files/usr/bin
else
    echo "⚪️ 未选择 luci-app-ssr-plus"
fi

# 使用自定义 geoip/geosite 数据（来自 wanjiban/v2ray-rules-dat）
if echo "$PACKAGES" | grep -q "daed"; then
    echo "🔄 [daed] 下载自定义 geoip/geosite 数据..."
    GEO_REPO="wanjiban/v2ray-rules-dat"
    GEO_TAG=$(curl -s "https://api.github.com/repos/$GEO_REPO/releases/latest" | grep -m1 '"tag_name":' | cut -d'"' -f4)
    if [ -n "$GEO_TAG" ]; then
        mkdir -p files/usr/share/v2ray
        wget -q "https://github.com/$GEO_REPO/releases/download/$GEO_TAG/geoip.dat" -O files/usr/share/v2ray/geoip.dat
        wget -q "https://github.com/$GEO_REPO/releases/download/$GEO_TAG/geosite.dat" -O files/usr/share/v2ray/geosite.dat
        echo "✅ [daed] geoip/geosite 下载完成"
    else
        echo "⚠️ [daed] 获取 geo 数据失败，使用 feed 版本"
    fi
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# armsr 镜像脚本会执行 cp root-armsr/boot/.，提前创建空 boot 目录避免
# "cp: cannot stat .../root-armsr/boot/.: No such file or directory"
mkdir -p files/boot

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
