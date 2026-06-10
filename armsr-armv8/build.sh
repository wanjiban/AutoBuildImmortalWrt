#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
# yml 传入的路由器型号 PROFILE
echo "Building for profile: $PROFILE"
# yml 传入的固件大小 ROOTFS_PARTSIZE
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

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
  # 下载 run 文件仓库
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # 拷贝 run/arm64 下所有 run 文件和ipk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
  # 添加架构优先级信息
  sed -i '1i\
  arch aarch64_generic 10\n\
  arch aarch64_cortex-a53 15' repositories.conf

  # 下载 luci-app-lucky 相关 ipk 包（自动获取最新版本）
  LUCKY_API="https://api.github.com/repos/sirpdboy/luci-app-lucky/releases/latest"
  LUCKY_ASSETS=$(curl -s $LUCKY_API | grep "browser_download_url" | cut -d '"' -f 4)
  DEST_DIR="/home/build/immortalwrt/extra-packages/luci-app-lucky"
  mkdir -p "$DEST_DIR"

  # 定义需要下载的包的正则表达式
  declare -A LUCKY_URLS=(
    [lucky]="lucky_.*aarch64_generic\.ipk"
    [i18n]="luci-i18n-lucky-zh-cn_.*all\.ipk"
    [app]="luci-app-lucky_.*all\.ipk"
  )

  for key in "${!LUCKY_URLS[@]}"; do
    url=$(echo "$LUCKY_ASSETS" | grep -E "/${LUCKY_URLS[$key]}" | head -n1)
    if [ -n "$url" ]; then
      wget -q "$url" -O "$DEST_DIR/$(basename "$url")" &
    fi
  done
  wait
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建QEMU-arm64固件..."


# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
# 服务——FileBrowser 用户名admin 密码admin
# PACKAGES="$PACKAGES luci-i18n-filebrowser-go-zh-cn"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-app-ttyd"
PACKAGES="$PACKAGES luci-app-openclash"
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
PACKAGES="$PACKAGES mtr"
PACKAGES="$PACKAGES iperf3"
# iptables 兼容层，避免部分脚本报 iptables: not found
PACKAGES="$PACKAGES iptables-nft"
# 系统工具
PACKAGES="$PACKAGES htop"

# 文件管理器
# PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# PACKAGES="$PACKAGES luci-app-filetransfer"
# 静态文件服务器dufs(推荐)
# PACKAGES="$PACKAGES luci-i18n-dufs-zh-cn"

# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

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
    # Download latest openclash Client
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*ipk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash latest ipk: $URL"
    wget "$URL" -P /home/build/immortalwrt/packages/
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ 已选择 luci-app-ssr-plus，添加 mihomo core"
    mkdir -p files/usr/bin
    # Download mihomo
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-arm64-v1.19.24.gz"
    mkdir -p files/usr/bin
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
    echo "✅ 已下载 mihomo core"
    ls -lah files/usr/bin
else
    echo "⚪️ 未选择 luci-app-ssr-plus"
fi


# 使用 QiuSimons 预编译的 daed 取代官方源版本
sh shell/download-daed.sh ipk

# 使用自定义 geoip/geosite 数据（来自 wanjiban/v2ray-rules-dat）
if echo "$PACKAGES" | grep -q "daed"; then
    echo "🔄 [daed] 下载自定义 geoip/geosite 数据..."
    GEO_REPO="wanjiban/v2ray-rules-dat"
    GEO_TAG=$(curl -s "https://api.github.com/repos/$GEO_REPO/releases/latest" | grep -m1 '"tag_name":' | cut -d'"' -f4)
    if [ -n "$GEO_TAG" ]; then
        mkdir -p files/usr/share/daed
        wget -q "https://github.com/$GEO_REPO/releases/download/$GEO_TAG/geoip.dat" -O files/usr/share/daed/geoip.dat
        wget -q "https://github.com/$GEO_REPO/releases/download/$GEO_TAG/geosite.dat" -O files/usr/share/daed/geosite.dat
        echo "✅ [daed] geoip/geosite 下载完成"
    else
        echo "⚠️ [daed] 获取 geo 数据失败，使用 feed 版本"
    fi
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
