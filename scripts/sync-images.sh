#!/usr/bin/env bash
# sync-images.sh — 手动同步镜像到 GHCR（多架构 + 双 tag）
#
# 用法:
#   bash scripts/sync-images.sh "nginx:1.21, docker.io/user/app:2.0"
#   GHCR_OWNER=<owner>  指定目标 GHCR 仓库所有者（CI 中传入 github.repository_owner）
#   DRY_RUN=1           只打印计划，不实际同步（本地调试）
#
# 输入格式: [registry/][namespace/]name[:tag]
# 目标命名规则（同步到 ghcr.io/<owner>/mirror/ 下）:
#   nginx:1.21            (官方 library) → mirror/nginx:1.21 + mirror/nginx:latest
#   library/nginx:1.21    (官方 library) → mirror/nginx:1.21 + mirror/nginx:latest
#   docker.io/nginx:1.21  (官方 library) → mirror/nginx:1.21 + mirror/nginx:latest
#   user/app:2.0          (自定义命名空间) → mirror/user-app:2.0 + mirror/user-app:latest
#   docker.io/user/app:2.0                → mirror/user-app:2.0 + mirror/user-app:latest
#   ghcr.io/x/y:1.0       (其他 registry) → mirror/x-y:1.0 + mirror/x-y:latest
#
# 多架构: skopeo copy --all 保留 manifest list（多平台镜像）
set -euo pipefail

INPUTS="${1:-}"
[[ -n "$INPUTS" ]] || { echo "错误: 未提供镜像引用" >&2; exit 1; }

OWNER="${GHCR_OWNER:-}"
[[ -n "$OWNER" ]] || { echo "错误: 未设置 GHCR_OWNER" >&2; exit 1; }
OWNER="${OWNER,,}"   # GHCR 仓库名必须小写

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  command -v skopeo >/dev/null || { echo "错误: 需要 skopeo（ubuntu-latest runner 自带）" >&2; exit 1; }
fi

IFS=',' read -ra refs <<<"$INPUTS"

failed=0
for ref in "${refs[@]}"; do
  ref="$(echo "$ref" | tr -d '[:space:]')"
  [[ -n "$ref" ]] || continue

  # ---- 解析引用: [registry/][namespace/]name[:tag] ----
  tag="latest"
  body="$ref"
  if [[ "$body" == *:* ]]; then
    tag="${body##*:}"
    body="${body%:*}"
  fi

  registry=""
  if [[ "$body" =~ ^[^/]+/ ]]; then
    first="${body%%/*}"
    if [[ "$first" == *.* || "$first" == *:* || "$first" == "localhost" ]]; then
      registry="$first"
      body="${body#*/}"
    fi
  fi

  namespace=""
  name="$body"
  if [[ "$body" == */* ]]; then
    namespace="${body%%/*}"
    name="${body#*/}"
  fi

  # 命名规则: library（或省略命名空间）不加前缀，自定义命名空间拼到名字上
  if [[ -n "$namespace" && "$namespace" != "library" ]]; then
    dst_name="${namespace}-${name}"
  else
    dst_name="$name"
  fi

  registry="${registry:-docker.io}"
  src="docker://${registry}/${body}:${tag}"
  dst="docker://ghcr.io/${OWNER}/mirror/${dst_name}"

  echo "==> ${src} → ${dst}:${tag}"
  echo "==> ${src} → ${dst}:latest"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "    (dry-run) skopeo copy --all ${src} ${dst}:${tag}"
    echo "    (dry-run) skopeo copy --all ${src} ${dst}:latest"
    continue
  fi

  if skopeo copy --all "$src" "${dst}:${tag}"; then
    skopeo copy --all "$src" "${dst}:latest" || failed=1
  else
    failed=1
  fi
done

exit "$failed"
