#!/usr/bin/env bash
# 统一 Release 产物整理脚本
#
# 目标：
#   1. 所有工作流使用同一套 Tag / 标题命名规则
#   2. 所有固件先统一收拢到 release/ 目录，再上传
#   3. release/ 内固定附带 SHA256SUMS.txt 与 build-info.txt
#
# 命名规则：
#   Tag   : wayos-<slug>-<version>-<YYYYMMDD-HHMMSS>
#   标题  : WayOS <platform> <version> [(profile)] - <YYYY-MM-DD HH:MM UTC>
#
# 用法（在 workflow step 中通过 env 传入）：
#   RELEASE_PLATFORM   平台展示名，例如 x86-64 / QEMU armsr-armv8
#   RELEASE_SLUG       平台标签名（小写、无空格），例如 x86-64 / armsr-armv8
#   RELEASE_VERSION    版本号，例如 24.10.6 / 25.12.2
#   RELEASE_PROFILE    可选，型号或 profile
#   RELEASE_FILES      多行文件路径或 glob（每行一个）
#   RELEASE_EXTRA_INFO 可选，附加到 build-info.txt 的多行文本
#
# 输出（写入 $GITHUB_OUTPUT）：
#   tag        发布 Tag
#   name       发布标题
#   stage_dir  产物目录（默认 release）

set -euo pipefail

: "${RELEASE_PLATFORM:?RELEASE_PLATFORM 未设置}"
: "${RELEASE_SLUG:?RELEASE_SLUG 未设置}"
: "${RELEASE_VERSION:?RELEASE_VERSION 未设置}"

RELEASE_PROFILE="${RELEASE_PROFILE:-}"
STAGE_DIR="${RELEASE_STAGE_DIR:-release}"
RELEASE_FILES="${RELEASE_FILES:-}"

timestamp="$(date -u +'%Y%m%d-%H%M%S')"
built_at="$(date -u +'%Y-%m-%d %H:%M UTC')"

# Tag 只允许小写字母、数字、点、下划线、连字符
base_tag="wayos-${RELEASE_SLUG}-${RELEASE_VERSION}-${timestamp}"
base_tag="$(printf '%s' "$base_tag" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g')"
tag="$base_tag"

# 同一天可以发布多个版本，绝不覆盖已有 Release。
# 时间戳精确到秒已能区分绝大多数构建；若极端情况下远端已存在同名 Tag，
# 再追加 run id / 序号，确保每次发布都是全新 Release。
tag_exists() {
    [ -n "${GITHUB_TOKEN:-}" ] || return 1
    [ -n "${GITHUB_REPOSITORY:-}" ] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs/tags/$1" || true)"
    [ "$code" = "200" ]
}

attempt=1
while tag_exists "$tag"; do
    if [ "$attempt" -eq 1 ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
        tag="${base_tag}-${GITHUB_RUN_ID}"
    else
        tag="${base_tag}-${attempt}"
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -gt 5 ]; then
        echo "❌ [release] 无法生成唯一 Tag（${base_tag} 已存在）" >&2
        exit 1
    fi
    echo "⚠️ [release] Tag 已存在，改用 ${tag}"
done

profile_text=""
if [ -n "$RELEASE_PROFILE" ]; then
    profile_text=" (${RELEASE_PROFILE})"
fi

name="WayOS ${RELEASE_PLATFORM} ${RELEASE_VERSION}${profile_text} - ${built_at}"

# 清理并重建产物目录，保证每次上传内容一致
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# ImageBuilder 会在目标目录生成元数据文件，它们不属于固件，统一排除
is_metadata() {
    case "$(basename "$1")" in
        profiles.json|*.buildinfo|*.manifest|sha256sums|*.bom.cdx.json) return 0 ;;
    esac
    return 1
}

copied=0
skipped=()

while IFS= read -r pattern; do
    pattern="$(printf '%s' "$pattern" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$pattern" ] || continue

    matched=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        [ -f "$file" ] || continue
        is_metadata "$file" && continue
        cp -f "$file" "$STAGE_DIR"/
        copied=$((copied + 1))
        matched=$((matched + 1))
    done < <(compgen -G "$pattern" || true)

    if [ "$matched" -eq 0 ]; then
        skipped+=("$pattern")
    fi
done <<< "$RELEASE_FILES"

if [ "$copied" -eq 0 ]; then
    echo "❌ [release] 没有匹配到任何固件，终止发布" >&2
    printf '   未匹配: %s\n' "${skipped[@]:-}" >&2
    exit 1
fi

if [ "${#skipped[@]}" -gt 0 ]; then
    echo "⚠️ [release] 以下规则未匹配到文件（已忽略）："
    printf '   %s\n' "${skipped[@]}"
fi

# 逐个计算校验值，写入统一的 SHA256SUMS.txt
shopt -s nullglob
stage_files=("$STAGE_DIR"/*)
shopt -u nullglob

asset_names=()
for file in "${stage_files[@]}"; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    case "$base" in
        SHA256SUMS.txt|build-info.txt) continue ;;
    esac
    asset_names+=("$base")
done

if command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
else
    sha_cmd=(shasum -a 256)
fi

(
    cd "$STAGE_DIR"
    "${sha_cmd[@]}" "${asset_names[@]}" > SHA256SUMS.txt
)
( cd "$STAGE_DIR" && "${sha_cmd[@]}" -c SHA256SUMS.txt >/dev/null )

# 生成 build-info.txt，便于回溯任意一次发布
{
    echo "# WayOS Release Build Info"
    echo
    echo "project: WayOS (AutoBuildImmortalWrt)"
    echo "platform: ${RELEASE_PLATFORM}"
    echo "slug: ${RELEASE_SLUG}"
    echo "version: ${RELEASE_VERSION}"
    echo "profile: ${RELEASE_PROFILE:-default}"
    echo "release_tag: ${tag}"
    echo "release_name: ${name}"
    echo "built_at: ${built_at}"
    echo "workflow: ${GITHUB_WORKFLOW:-local}"
    echo "run_id: ${GITHUB_RUN_ID:-local}"
    echo "run_number: ${GITHUB_RUN_NUMBER:-local}"
    echo "ref: ${GITHUB_REF:-local}"
    echo "commit: ${GITHUB_SHA:-local}"
    echo "triggered_by: ${GITHUB_ACTOR:-local}"
    if [ -n "${RELEASE_EXTRA_INFO:-}" ]; then
        echo
        echo "# Extra"
        printf '%s\n' "$RELEASE_EXTRA_INFO"
    fi
    echo
    echo "# Assets (${#asset_names[@]})"
    for base in "${asset_names[@]}"; do
        size="$(wc -c < "$STAGE_DIR/$base" | tr -d ' ')"
        echo "${base}  ${size} bytes"
    done
} > "$STAGE_DIR/build-info.txt"

echo "✅ [release] 已整理 ${copied} 个固件到 ${STAGE_DIR}/"
echo "   tag : ${tag}"
echo "   name: ${name}"
( cd "$STAGE_DIR" && ls -lh )

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "tag=${tag}"
        echo "name=${name}"
        echo "stage_dir=${STAGE_DIR}"
    } >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "## WayOS ${RELEASE_PLATFORM} ${RELEASE_VERSION}"
        echo
        echo "- Tag: \`${tag}\`"
        echo "- 产物目录: \`${STAGE_DIR}/\`（${copied} 个文件 + SHA256SUMS.txt + build-info.txt）"
    } >> "$GITHUB_STEP_SUMMARY"
fi
