#!/usr/bin/env bash

DEMO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_SETUP_ROOT="$(cd "${DEMO_LIB_DIR}/../.." && pwd)"
DEMO_REPO_ROOT="$(cd "${DEMO_SETUP_ROOT}/.." && pwd)"
DEMO_DEFAULT_CONFIG="${DEMO_SETUP_ROOT}/config/kind-demo.yaml"

demo_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

demo_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || demo_die "Required command not found: $1"
}

demo_resolve_input_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "${PWD}/$1" ;;
  esac
}

demo_load_config() {
  DEMO_CONFIG_FILE="$(demo_resolve_input_path "$1")"
  [ -f "$DEMO_CONFIG_FILE" ] || demo_die "Config file not found: $DEMO_CONFIG_FILE"

  DEMO_CONFIG_DIR="$(cd "$(dirname "$DEMO_CONFIG_FILE")" && pwd)"
}

demo_parse_clusters() {
  awk '
    function clean(value) {
      sub(/[ \t]+#.*/, "", value)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      return value
    }

    /^[ \t]*#/ || /^[ \t]*$/ { next }

    /^[ \t]*-[ \t]*name:[ \t]*/ {
      if (name != "") {
        print name "|" kind_config
      }

      line = $0
      sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", line)
      name = clean(line)
      kind_config = ""
      next
    }

    /^[ \t]*kind_config:[ \t]*/ {
      line = $0
      sub(/^[ \t]*kind_config:[ \t]*/, "", line)
      kind_config = clean(line)
      next
    }

    END {
      if (name != "") {
        print name "|" kind_config
      }
    }
  ' "$DEMO_CONFIG_FILE"
}

demo_parse_sveltos_bootstrap() {
  awk -v target_cluster="$1" '
    function clean(value) {
      sub(/[ \t]+#.*/, "", value)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      return value
    }

    function indent(value) {
      match(value, /^[ \t]*/)
      return RLENGTH
    }

    /^[ \t]*#/ || /^[ \t]*$/ { next }

    {
      current_indent = indent($0)
    }

    /^[ \t]*-[ \t]*name:[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", line)

      current_cluster = clean(line)
      in_target_cluster = current_cluster == target_cluster
      in_bootstrap = 0
      in_sveltos = 0
      in_prerequisite_manifests = 0
      in_prerequisite_wait_for_crds = 0
      in_manifests = 0
      in_wait_for_crds = 0
      next
    }

    !in_target_cluster { next }

    /^[ \t]*bootstrap:[ \t]*$/ {
      in_bootstrap = 1
      bootstrap_indent = current_indent
      next
    }

    in_bootstrap && current_indent <= bootstrap_indent {
      in_bootstrap = 0
      in_sveltos = 0
      in_prerequisite_manifests = 0
      in_prerequisite_wait_for_crds = 0
      in_manifests = 0
      in_wait_for_crds = 0
    }

    !in_bootstrap { next }

    /^[ \t]*sveltos:[ \t]*$/ {
      in_sveltos = 1
      sveltos_indent = current_indent
      next
    }

    in_sveltos && current_indent <= sveltos_indent {
      in_sveltos = 0
      in_prerequisite_manifests = 0
      in_prerequisite_wait_for_crds = 0
      in_manifests = 0
      in_wait_for_crds = 0
    }

    !in_sveltos { next }

    /^[ \t]*enabled:[ \t]*/ {
      line = $0
      sub(/^[ \t]*enabled:[ \t]*/, "", line)
      print "enabled|" clean(line)
      next
    }

    /^[ \t]*cluster_profiles:[ \t]*/ {
      line = $0
      sub(/^[ \t]*cluster_profiles:[ \t]*/, "", line)
      print "cluster_profiles|" clean(line)
      next
    }

    /^[ \t]*prerequisite_manifests:[ \t]*$/ {
      in_prerequisite_manifests = 1
      prerequisite_manifests_indent = current_indent
      in_prerequisite_wait_for_crds = 0
      in_manifests = 0
      in_wait_for_crds = 0
      next
    }

    /^[ \t]*prerequisite_wait_for_crds:[ \t]*$/ {
      in_prerequisite_wait_for_crds = 1
      prerequisite_wait_for_crds_indent = current_indent
      in_prerequisite_manifests = 0
      in_manifests = 0
      in_wait_for_crds = 0
      next
    }

    /^[ \t]*manifests:[ \t]*$/ {
      in_manifests = 1
      manifests_indent = current_indent
      in_prerequisite_manifests = 0
      in_prerequisite_wait_for_crds = 0
      in_wait_for_crds = 0
      next
    }

    /^[ \t]*wait_for_crds:[ \t]*$/ {
      in_wait_for_crds = 1
      wait_for_crds_indent = current_indent
      in_prerequisite_manifests = 0
      in_prerequisite_wait_for_crds = 0
      in_manifests = 0
      next
    }

    in_prerequisite_manifests && current_indent > prerequisite_manifests_indent && /^[ \t]*-[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      print "prerequisite_manifest|" clean(line)
      next
    }

    in_prerequisite_wait_for_crds && current_indent > prerequisite_wait_for_crds_indent && /^[ \t]*-[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      print "prerequisite_wait_crd|" clean(line)
      next
    }

    in_manifests && current_indent > manifests_indent && /^[ \t]*-[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      print "manifest|" clean(line)
      next
    }

    in_wait_for_crds && current_indent > wait_for_crds_indent && /^[ \t]*-[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      print "wait_crd|" clean(line)
      next
    }

    in_prerequisite_manifests && current_indent <= prerequisite_manifests_indent {
      in_prerequisite_manifests = 0
    }

    in_prerequisite_wait_for_crds && current_indent <= prerequisite_wait_for_crds_indent {
      in_prerequisite_wait_for_crds = 0
    }

    in_manifests && current_indent <= manifests_indent {
      in_manifests = 0
    }

    in_wait_for_crds && current_indent <= wait_for_crds_indent {
      in_wait_for_crds = 0
    }
  ' "$DEMO_CONFIG_FILE"
}

demo_parse_cluster_registration() {
  awk -v target_cluster="$1" '
    function clean(value) {
      sub(/[ \t]+#.*/, "", value)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      return value
    }

    function indent(value) {
      match(value, /^[ \t]*/)
      return RLENGTH
    }

    /^[ \t]*#/ || /^[ \t]*$/ { next }

    {
      current_indent = indent($0)
    }

    /^[ \t]*-[ \t]*name:[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*name:[ \t]*/, "", line)

      current_cluster = clean(line)
      in_target_cluster = current_cluster == target_cluster
      in_registration = 0
      in_previous_clusters = 0
      next
    }

    !in_target_cluster { next }

    /^[ \t]*registration:[ \t]*$/ {
      in_registration = 1
      registration_indent = current_indent
      next
    }

    in_registration && current_indent <= registration_indent {
      in_registration = 0
      in_previous_clusters = 0
    }

    !in_registration { next }

    /^[ \t]*enabled:[ \t]*/ {
      line = $0
      sub(/^[ \t]*enabled:[ \t]*/, "", line)
      print "enabled|" clean(line)
      next
    }

    /^[ \t]*hub:[ \t]*/ {
      line = $0
      sub(/^[ \t]*hub:[ \t]*/, "", line)
      print "hub|" clean(line)
      next
    }

    /^[ \t]*namespace:[ \t]*/ {
      line = $0
      sub(/^[ \t]*namespace:[ \t]*/, "", line)
      print "namespace|" clean(line)
      next
    }

    /^[ \t]*cluster:[ \t]*/ {
      line = $0
      sub(/^[ \t]*cluster:[ \t]*/, "", line)
      print "cluster|" clean(line)
      next
    }

    /^[ \t]*mode:[ \t]*/ {
      line = $0
      sub(/^[ \t]*mode:[ \t]*/, "", line)
      print "mode|" clean(line)
      next
    }

    /^[ \t]*labels:[ \t]*/ {
      line = $0
      sub(/^[ \t]*labels:[ \t]*/, "", line)
      print "labels|" clean(line)
      next
    }

    /^[ \t]*refresh:[ \t]*/ {
      line = $0
      sub(/^[ \t]*refresh:[ \t]*/, "", line)
      print "refresh|" clean(line)
      next
    }

    /^[ \t]*previous_clusters:[ \t]*$/ {
      in_previous_clusters = 1
      previous_clusters_indent = current_indent
      next
    }

    in_previous_clusters && current_indent > previous_clusters_indent && /^[ \t]*-[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      print "previous_cluster|" clean(line)
      next
    }

    in_previous_clusters && current_indent <= previous_clusters_indent {
      in_previous_clusters = 0
    }
  ' "$DEMO_CONFIG_FILE"
}

demo_resolve_config_path() {
  case "$1" in
    /*)
      printf '%s\n' "$1"
      ;;
    *)
      if [ -f "${DEMO_REPO_ROOT}/$1" ]; then
        printf '%s\n' "${DEMO_REPO_ROOT}/$1"
      else
        printf '%s\n' "${DEMO_CONFIG_DIR}/$1"
      fi
      ;;
  esac
}

demo_resolve_kind_config_path() {
  demo_resolve_config_path "$1"
}

demo_validate_cluster_name() {
  [[ "$1" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || \
    demo_die "Invalid KinD cluster name: $1"
}

demo_run() {
  if [ "${DRY_RUN:-false}" = "true" ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

demo_cluster_exists() {
  kind get clusters 2>/dev/null | awk -v name="$1" '$0 == name { found = 1 } END { exit found ? 0 : 1 }'
}
