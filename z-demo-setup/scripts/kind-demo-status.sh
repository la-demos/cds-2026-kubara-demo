#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/kind-demo-common.sh"

CONFIG_FILE="$DEMO_DEFAULT_CONFIG"

if [ "${1:-}" = "--config" ] || [ "${1:-}" = "-c" ]; then
  [ -n "${2:-}" ] || demo_die "Missing value for $1"
  CONFIG_FILE="$2"
elif [ "$#" -gt 0 ]; then
  demo_die "Usage: $0 [--config <file>]"
fi

demo_load_config "$CONFIG_FILE"
demo_require_cmd kind
demo_require_cmd kubectl
ARTIFACT_DIR="${DEMO_REPO_ROOT}/.local/kind-demo"

while IFS='|' read -r cluster_name _kind_config; do
  [ -n "$cluster_name" ] || continue
  printf '\n[%s]\n' "$cluster_name"
  if demo_cluster_exists "$cluster_name"; then
    kubeconfig="${ARTIFACT_DIR}/${cluster_name}.kubeconfig"
    [ -f "$kubeconfig" ] || demo_die "Host kubeconfig not found: $kubeconfig"
    kubectl --kubeconfig "$kubeconfig" get nodes -o wide
  else
    printf 'not created\n'
  fi
done < <(demo_parse_clusters)
