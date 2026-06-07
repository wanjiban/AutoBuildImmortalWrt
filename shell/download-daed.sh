#!/bin/bash
# 下载 QiuSimons 预编译的 daed IPK/APK，替代 ImmortalWrt 官方源版本
# 用法: download-daed.sh <ipk|apk>

PKG_EXT="${1:-ipk}"

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) FEARCH="x86_64" ;;
    aarch64) FEARCH="aarch64_generic" ;;
    *)
        echo "⚠️ [daed] 不支持的架构 $ARCH，跳过"
        return 0
        ;;
esac

echo "🔄 [daed] 架构=$ARCH 包格式=$PKG_EXT"

RELEASE_API="https://api.github.com/repos/QiuSimons/luci-app-daed/releases/latest"
ASSET_URLS=$(curl -s "$RELEASE_API" | grep "browser_download_url" | cut -d'"' -f4)

if [ -z "$ASSET_URLS" ]; then
    echo "⚠️ [daed] 获取 release 信息失败（可能被限流），跳过"
    return 0
fi

mkdir -p extra-packages/daed
ext=".$PKG_EXT"

for URL in $ASSET_URLS; do
    fname=$(basename "$URL")

    # daed 核心（架构相关）
    if echo "$fname" | grep -qiE "^daed[-_].*${FEARCH}.*${ext}$"; then
        echo "  ⬇️  $fname"
        wget -q "$URL" -P extra-packages/daed/ && continue
    fi

    # luci-app-daed 和 luci-i18n-daed-zh-cn（通用）
    if echo "$fname" | grep -qiE "luci-(app|i18n)-daed.*${ext}$"; then
        echo "  ⬇️  $fname"
        wget -q "$URL" -P extra-packages/daed/
    fi
done

echo "✅ [daed] 下载完成"
ls -lh extra-packages/daed/ 2>/dev/null
