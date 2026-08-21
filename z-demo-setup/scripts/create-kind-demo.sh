#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/kind-demo-common.sh"

CONFIG_FILE="$DEMO_DEFAULT_CONFIG"
RECREATE="false"
DRY_RUN="false"
ARTIFACT_DIR="${DEMO_REPO_ROOT}/.local/kind-demo"
HUB_KUBECONFIG="${DEMO_REPO_ROOT}/.local/kind.kubeconfig"
MERGED_KUBECONFIG="${HOME}/.kube/config"
HUB_CONTEXT="kind-hub"

usage() {
  cat <<USAGE
Usage: $0 [options]

Create the kind clusters from z-demo-setup/config/kind-demo.yaml, export one host and one
Docker-internal kubeconfig for every cluster, and merge all host kubeconfigs.

Options:
  -c, --config <file>  Demo environment YAML
      --hub-kubeconfig <file>
                        Existing hub kubeconfig (default: .local/kind.kubeconfig)
      --merged-kubeconfig <file>
                        Merged kubeconfig (default: ~/.kube/config)
      --hub-context <name>
                        Context selected after merging (default: kind-hub)
      --recreate       Delete existing demo clusters before creating them
      --dry-run        Print commands without executing them
  -h, --help           Show this help
USAGE
}

merge_host_kubeconfigs() {
  local merged_sources
  local temp_kubeconfig
  local source
  local sources=("${host_kubeconfigs[@]}" "$HUB_KUBECONFIG")

  if [ -f "$MERGED_KUBECONFIG" ] && [ "$MERGED_KUBECONFIG" != "$HUB_KUBECONFIG" ]; then
    sources+=("$MERGED_KUBECONFIG")
  fi

  merged_sources="$(IFS=:; printf '%s' "${sources[*]}")"

  if [ "$DRY_RUN" = "true" ]; then
    printf '+ env KUBECONFIG=%q kubectl config view --flatten > %q\n' "$merged_sources" "$MERGED_KUBECONFIG"
    printf '+ kubectl config use-context %q --kubeconfig %q\n' "$HUB_CONTEXT" "$MERGED_KUBECONFIG"
    return
  fi

  mkdir -p "$(dirname "$MERGED_KUBECONFIG")"
  temp_kubeconfig="$(mktemp "${MERGED_KUBECONFIG}.tmp.XXXXXX")"

  if ! env "KUBECONFIG=$merged_sources" kubectl config view --flatten > "$temp_kubeconfig"; then
    rm -f "$temp_kubeconfig"
    demo_die "Failed to merge kubeconfigs"
  fi

  kubectl config get-contexts -o name --kubeconfig "$temp_kubeconfig" |
    awk -v context="$HUB_CONTEXT" '$0 == context { found = 1 } END { exit found ? 0 : 1 }' || {
      rm -f "$temp_kubeconfig"
      demo_die "Hub context not found after merging: $HUB_CONTEXT"
    }
  kubectl config use-context "$HUB_CONTEXT" --kubeconfig "$temp_kubeconfig" >/dev/null

  chmod 600 "$temp_kubeconfig"
  mv "$temp_kubeconfig" "$MERGED_KUBECONFIG"

  printf 'Merged kubeconfig: %s\n' "$MERGED_KUBECONFIG"
  for source in "${sources[@]}"; do
    printf '  - %s\n' "$source"
  done
}

write_kubeconfig() {
  local cluster_name="$1"
  local output_file="$2"
  local internal="${3:-false}"

  if [ "$DRY_RUN" = "true" ]; then
    if [ "$internal" = "true" ]; then
      printf '+ kind get kubeconfig --name %q --internal > %q\n' "$cluster_name" "$output_file"
    else
      printf '+ kind get kubeconfig --name %q > %q\n' "$cluster_name" "$output_file"
    fi
    return
  fi

  if [ "$internal" = "true" ]; then
    kind get kubeconfig --name "$cluster_name" --internal > "$output_file"
  else
    kind get kubeconfig --name "$cluster_name" > "$output_file"
  fi
  chmod 600 "$output_file"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c|--config)
      [ -n "${2:-}" ] || demo_die "Missing value for $1"
      CONFIG_FILE="$2"
      shift 2
      ;;
    --config=*) CONFIG_FILE="${1#*=}"; shift ;;
    --hub-kubeconfig)
      [ -n "${2:-}" ] || demo_die "Missing value for $1"
      HUB_KUBECONFIG="$2"
      shift 2
      ;;
    --hub-kubeconfig=*) HUB_KUBECONFIG="${1#*=}"; shift ;;
    --merged-kubeconfig)
      [ -n "${2:-}" ] || demo_die "Missing value for $1"
      MERGED_KUBECONFIG="$2"
      shift 2
      ;;
    --merged-kubeconfig=*) MERGED_KUBECONFIG="${1#*=}"; shift ;;
    --hub-context)
      [ -n "${2:-}" ] || demo_die "Missing value for $1"
      HUB_CONTEXT="$2"
      shift 2
      ;;
    --hub-context=*) HUB_CONTEXT="${1#*=}"; shift ;;
    --recreate) RECREATE="true"; shift ;;
    --dry-run) DRY_RUN="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) demo_die "Unknown argument: $1" ;;
  esac
done

demo_load_config "$CONFIG_FILE"
HUB_KUBECONFIG="$(demo_resolve_input_path "$HUB_KUBECONFIG")"
MERGED_KUBECONFIG="$(demo_resolve_input_path "$MERGED_KUBECONFIG")"

if [ "$DRY_RUN" != "true" ]; then
  [ -f "$HUB_KUBECONFIG" ] || demo_die "Hub kubeconfig not found: $HUB_KUBECONFIG"
fi

if [ "$DRY_RUN" != "true" ]; then
  demo_require_cmd kind
  demo_require_cmd kubectl
  mkdir -p "$ARTIFACT_DIR"
else
  demo_run mkdir -p "$ARTIFACT_DIR"
fi

cluster_count=0
cluster_names=()
host_kubeconfigs=()

while IFS='|' read -r cluster_name kind_config; do
  [ -n "$cluster_name" ] || continue
  demo_validate_cluster_name "$cluster_name"
  [ -n "$kind_config" ] || demo_die "Missing kind_config for cluster: $cluster_name"

  kind_config_path="$(demo_resolve_kind_config_path "$kind_config")"
  [ -f "$kind_config_path" ] || demo_die "kind config not found for ${cluster_name}: $kind_config_path"

  cluster_count=$((cluster_count + 1))
  cluster_names+=("$cluster_name")

  if [ "$DRY_RUN" = "true" ]; then
    if [ "$RECREATE" = "true" ]; then
      demo_run kind delete cluster --name "$cluster_name"
    fi
    demo_run kind create cluster --name "$cluster_name" --config "$kind_config_path" --kubeconfig "${ARTIFACT_DIR}/${cluster_name}.kubeconfig"
  elif demo_cluster_exists "$cluster_name"; then
    if [ "$RECREATE" = "true" ]; then
      printf 'Recreating kind cluster: %s\n' "$cluster_name"
      demo_run kind delete cluster --name "$cluster_name"
      demo_run kind create cluster --name "$cluster_name" --config "$kind_config_path" --kubeconfig "${ARTIFACT_DIR}/${cluster_name}.kubeconfig"
    else
      printf 'kind cluster already exists, skipping: %s\n' "$cluster_name"
    fi
  else
    printf 'Creating kind cluster: %s\n' "$cluster_name"
    demo_run kind create cluster --name "$cluster_name" --config "$kind_config_path" --kubeconfig "${ARTIFACT_DIR}/${cluster_name}.kubeconfig"
  fi

  write_kubeconfig "$cluster_name" "${ARTIFACT_DIR}/${cluster_name}.kubeconfig"
  write_kubeconfig "$cluster_name" "${ARTIFACT_DIR}/${cluster_name}.internal.kubeconfig" true
  host_kubeconfigs+=("${ARTIFACT_DIR}/${cluster_name}.kubeconfig")
done < <(demo_parse_clusters)

[ "$cluster_count" -gt 0 ] || demo_die "No clusters found in config: $DEMO_CONFIG_FILE"

merge_host_kubeconfigs

printf '\nSpoke clusters configured:\n'
for cluster_name in "${cluster_names[@]}"; do
  printf '  - %s (context: kind-%s)\n' "$cluster_name" "$cluster_name"
done
printf '\nHost kubeconfigs: %s/*.kubeconfig\n' "$ARTIFACT_DIR"
printf 'Merged kubeconfig: %s\n' "$MERGED_KUBECONFIG"
printf 'Current context: %s\n' "$HUB_CONTEXT"
printf 'Next step: make -C z-demo-setup openbao-secrets\n'
