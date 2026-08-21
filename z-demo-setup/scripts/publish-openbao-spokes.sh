#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/kind-demo-common.sh"

CONFIG_FILE="$DEMO_DEFAULT_CONFIG"
HUB_KUBECONFIG="${DEMO_REPO_ROOT}/.local/kind.kubeconfig"
OPENBAO_NAMESPACE="openbao"
OPENBAO_MOUNT="kv"
PLATFORM_CONFIG="${DEMO_REPO_ROOT}/config.yaml"
ARTIFACT_DIR="${DEMO_REPO_ROOT}/.local/kind-demo"

usage() {
  cat <<USAGE
Usage: $0 [options]

Publish the Docker-internal kind kubeconfig for each spoke to OpenBao KV v2.
kubara ExternalSecrets reads the field "kubeconfig" from:
  <mount>/<hub>/<hub-stage>/argocd/<spoke>-<spoke-stage>

Options:
  -c, --config <file>          Demo environment YAML
      --hub-kubeconfig <file>  Hub kubeconfig (default: .local/kind.kubeconfig)
      --namespace <name>       OpenBao namespace (default: openbao)
      --mount <name>           OpenBao KV v2 mount (default: kv)
      --kubara-config <file>   kubara config with hub/spoke stages (default: config.yaml)
  -h, --help                   Show this help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c|--config) [ -n "${2:-}" ] || demo_die "Missing value for $1"; CONFIG_FILE="$2"; shift 2 ;;
    --hub-kubeconfig) [ -n "${2:-}" ] || demo_die "Missing value for $1"; HUB_KUBECONFIG="$2"; shift 2 ;;
    --namespace) [ -n "${2:-}" ] || demo_die "Missing value for $1"; OPENBAO_NAMESPACE="$2"; shift 2 ;;
    --mount) [ -n "${2:-}" ] || demo_die "Missing value for $1"; OPENBAO_MOUNT="$2"; shift 2 ;;
    --kubara-config) [ -n "${2:-}" ] || demo_die "Missing value for $1"; PLATFORM_CONFIG="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) demo_die "Unknown argument: $1" ;;
  esac
done

demo_load_config "$CONFIG_FILE"
HUB_KUBECONFIG="$(demo_resolve_input_path "$HUB_KUBECONFIG")"
PLATFORM_CONFIG="$(demo_resolve_input_path "$PLATFORM_CONFIG")"

demo_require_cmd kubectl
demo_require_cmd curl
demo_require_cmd jq
[ -f "$HUB_KUBECONFIG" ] || demo_die "Hub kubeconfig not found: $HUB_KUBECONFIG"
[ -f "$PLATFORM_CONFIG" ] || demo_die "kubara config not found: $PLATFORM_CONFIG"
[[ "$OPENBAO_MOUNT" =~ ^[a-zA-Z0-9_-]+$ ]] || demo_die "Invalid OpenBao mount: $OPENBAO_MOUNT"

parse_kubara_clusters() {
  awk '
    function clean(value) {
      sub(/[ \t]+#.*/, "", value)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }
    function emit() {
      if (name != "") print name "|" stage "|" type
    }
    /^  - name:[ \t]*/ {
      emit()
      line = $0
      sub(/^  - name:[ \t]*/, "", line)
      name = clean(line)
      stage = ""
      type = ""
      next
    }
    name != "" && /^    stage:[ \t]*/ {
      line = $0
      sub(/^    stage:[ \t]*/, "", line)
      stage = clean(line)
      next
    }
    name != "" && /^    type:[ \t]*/ {
      line = $0
      sub(/^    type:[ \t]*/, "", line)
      type = clean(line)
      next
    }
    END { emit() }
  ' "$PLATFORM_CONFIG"
}

parse_demo_cluster_stage() {
  local target_cluster="$1"

  awk -v target="$target_cluster" '
    function clean(value) {
      sub(/[ \t]+#.*/, "", value)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }
    /^[ \t]*-[ \t]*name:[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", line)
      current = clean(line)
      next
    }
    current == target && /^[ \t]*stage:[ \t]*/ {
      line = $0
      sub(/^[ \t]*stage:[ \t]*/, "", line)
      print clean(line)
      exit
    }
  ' "$DEMO_CONFIG_FILE"
}

hub_record="$(parse_kubara_clusters | awk -F '|' '$3 == "hub" { print; exit }')"
[ -n "$hub_record" ] || demo_die "No hub cluster found in $PLATFORM_CONFIG"
IFS='|' read -r kubara_hub kubara_hub_stage _hub_type <<< "$hub_record"
demo_validate_cluster_name "$kubara_hub"
demo_validate_cluster_name "$kubara_hub_stage"

ingress_host="$(kubectl --kubeconfig "$HUB_KUBECONFIG" -n "$OPENBAO_NAMESPACE" \
  get ingress openbao -o jsonpath='{.spec.rules[0].host}')"
[ -n "$ingress_host" ] || demo_die "OpenBao ingress host not found"

root_token="$(kubectl --kubeconfig "$HUB_KUBECONFIG" -n "$OPENBAO_NAMESPACE" \
  exec openbao-0 -c openbao -- sh -c \
  "tr -d '\n\r' < /openbao/data/local-bootstrap/init.json | sed -n 's/.*\"root_token\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p'")"
[ -n "$root_token" ] || demo_die "Could not read the OpenBao root token"

openbao_addr="http://${ingress_host}"
curl -fsS --header "X-Vault-Token: ${root_token}" "${openbao_addr}/v1/sys/health" >/dev/null
printf 'OpenBao: %s\n' "$openbao_addr"

while IFS='|' read -r cluster_name _kind_config; do
  [ -n "$cluster_name" ] || continue
  demo_validate_cluster_name "$cluster_name"

  spoke_stage="$(parse_kubara_clusters | awk -F '|' -v cluster="$cluster_name" '$1 == cluster && $3 == "spoke" { print $2; exit }')"
  if [ -z "$spoke_stage" ]; then
    spoke_stage="$(parse_demo_cluster_stage "$cluster_name")"
  fi
  [ -n "$spoke_stage" ] || demo_die "Stage for spoke ${cluster_name} not found in $PLATFORM_CONFIG or $DEMO_CONFIG_FILE"
  demo_validate_cluster_name "$spoke_stage"

  internal_kubeconfig="${ARTIFACT_DIR}/${cluster_name}.internal.kubeconfig"
  [ -f "$internal_kubeconfig" ] || demo_die "Internal kubeconfig not found: $internal_kubeconfig (run make -C z-demo-setup kind-up first)"

  secret_path="${kubara_hub}/${kubara_hub_stage}/argocd/${cluster_name}-${spoke_stage}"
  api_url="${openbao_addr}/v1/${OPENBAO_MOUNT}/data/${secret_path}"

  jq -Rs '{data: {kubeconfig: .}}' "$internal_kubeconfig" |
    curl -fsS \
      --header "X-Vault-Token: ${root_token}" \
      --header 'Content-Type: application/json' \
      --request POST \
      --data-binary @- \
      "$api_url" >/dev/null

  curl -fsS --header "X-Vault-Token: ${root_token}" "$api_url" |
    jq -e '.data.data.kubeconfig | type == "string" and length > 0' >/dev/null

  printf 'Published %s/%s (field: kubeconfig)\n' "$OPENBAO_MOUNT" "$secret_path"
done < <(demo_parse_clusters)

unset root_token
