#!/usr/bin/env bash
# check-tags.sh — 检测需要构建的项目（上游新 tag / 无 tag 来源的 commit 快照）
#
# 项目约定: projects/<项目名>/Dockerfile 顶部声明（构建参数）:
#   ARG UPSTREAM_REPO=<上游 git 仓库 URL>  必填，本脚本据此查询上游
#   ARG UPSTREAM_REF=<分支或 tag>          可选，默认 main
#
# 触发规则:
#   - 上游出现新 tag（按版本号排序取最新）→ 若 GHCR 尚无该 tag 则构建，打 <tag> + latest
#   - 上游无 tag → 若 GHCR 尚无该 commit 快照则构建，打 <sha8> + latest
#   - GHCR 已存在该 tag/commit（已构建过）→ 不输出，不触发构建
#
# 环境变量:
#   GHCR_OWNER   目标 GHCR 所有者（设置后才启用"已存在则跳过"判断）
#   GHCR_TOKEN   GHCR 访问 token（CI 传 secrets.GITHUB_TOKEN；缺省则匿名查询）
#
# 用法:
#   ./scripts/check-tags.sh                 检测所有项目（schedule / push 触发）
#   ./scripts/check-tags.sh --force <名>    强制输出该项目的 commit 快照（CI 手动触发）
#   ./scripts/check-tags.sh <名1,名2...>    只检测指定项目
#
# 输出: ["name|v1.2.3","name|commit:abc12345", ...]；无 → []
#   （workflow 按 name|SPEC 解析：SPEC=commit:xxx → commit 快照打 <sha8>+latest；否则 → 上游 tag 打 <tag>+latest）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

force=""
declare -a names=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force="${2:-}"
      shift 2
      ;;
    *)
      IFS=',' read -ra parts <<<"$1"
      names+=("${parts[@]}")
      shift
      ;;
  esac
done

[[ -f "$ROOT_DIR/build-state.txt" ]] && rm -f "$ROOT_DIR/build-state.txt"  # 兼容旧版残留，不再使用

# 带超时的 git ls-remote：网络抖动/仓库不可达时跳过而非卡死整个 workflow
git_ls() {
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true timeout 30 git ls-remote "$@" 2>/dev/null || true
}

# 查询 GHCR 是否已有该 tag（有 → 0；未配置 / 查询失败 / 无 skopeo → 1）
# 失败视为"无"：宁可重复构建（幂等覆盖），也不漏构建新版本
ghcr_has_tag() {
  local name="$1" tag="$2"
  [[ -n "${GHCR_OWNER:-}" ]] || return 1
  command -v skopeo >/dev/null 2>&1 || return 1
  local owner="${GHCR_OWNER,,}"
  local creds=()
  if [[ -n "${GHCR_TOKEN:-}" ]]; then
    creds=(--creds "x-access-token:${GHCR_TOKEN}")
  fi
  skopeo inspect "${creds[@]}" "docker://ghcr.io/${owner}/${name}:${tag}" >/dev/null 2>&1
}

projects=()
if [[ -n "$force" ]]; then
  [[ -d "$ROOT_DIR/projects/$force" ]] || { echo "错误: projects/$force 不存在" >&2; exit 1; }
  projects=("$force")
elif [[ ${#names[@]} -gt 0 ]]; then
  projects=("${names[@]}")
else
  for d in "$ROOT_DIR"/projects/*/; do
    [[ -d "$d" ]] && projects+=("$(basename "$d")")
  done
fi

entries=()
for name in "${projects[@]}"; do
  df="$ROOT_DIR/projects/$name/Dockerfile"
  [[ -f "$df" ]] || { echo "警告: 跳过 $name（缺少 Dockerfile）" >&2; continue; }

  repo="$(sed -n 's/^ARG UPSTREAM_REPO=//p' "$df" | head -1 | tr -d '[:space:]' || true)"
  [[ -n "$repo" ]] || { echo "警告: 跳过 $name（Dockerfile 未声明 ARG UPSTREAM_REPO）" >&2; continue; }

  head_sha8="$(git_ls "$repo" HEAD | awk '{print substr($1,1,8)}')"

  if [[ -n "$force" ]]; then
    # 手动触发: 始终构建该项目的 commit 快照（忽略 tag 状态）
    [[ -n "$head_sha8" ]] && entries+=("$name|commit:$head_sha8")
    continue
  fi

  latest_tag="$(git_ls --tags --refs "$repo" \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v?[0-9]+(\.[0-9]+)+' \
    | sort -V | tail -1 || true)"

  if [[ -n "$latest_tag" ]]; then
    if ghcr_has_tag "$name" "$latest_tag"; then
      echo "跳过 $name: GHCR 已有 $latest_tag" >&2
    else
      entries+=("$name|$latest_tag")
    fi
  elif [[ -n "$head_sha8" ]]; then
    if ghcr_has_tag "$name" "$head_sha8"; then
      echo "跳过 $name: GHCR 已有 $head_sha8" >&2
    else
      entries+=("$name|commit:$head_sha8")
    fi
  fi
done

printf '['
for i in "${!entries[@]}"; do
  [[ $i -gt 0 ]] && printf ','
  printf '"%s"' "${entries[$i]}"
done
printf ']\n'
