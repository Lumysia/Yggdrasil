#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/komodo/infra"

usage() {
  cat <<'USAGE'
Usage: ./komodo-infra-mgnt.sh [-m [registry]] <command> <variant> [hostname] [-- compose args...]

Commands: up, down, restart, ps, logs, config, pull
Variants: core|c, periphery-only|peripheryonly|po, periphery-tailscale|peripherytailscale|pt
Hostname defaults to current host.

Examples:
  ./komodo-infra-mgnt.sh up core
  ./komodo-infra-mgnt.sh -m up po
  ./komodo-infra-mgnt.sh -m registry.example.com up po
  ./komodo-infra-mgnt.sh down po
  ./komodo-infra-mgnt.sh up pt
  ./komodo-infra-mgnt.sh logs pt cator-oracle-01 -- --tail=100
USAGE
  exit 1
}

die() {
  echo "Error: $*" >&2
  exit 1
}

normalize_command() {
  case "$1" in
    up|down|restart|ps|logs|config|pull)
      printf '%s\n' "$1"
      ;;
    *)
      die "unknown command '$1'."
      ;;
  esac
}

normalize_stack() {
  case "$1" in
    core|c)
      printf '%s\n' "core"
      ;;
    periphery-only|peripheryonly|po)
      printf '%s\n' "periphery-only"
      ;;
    periphery-tailscale|peripherytailscale|pt)
      printf '%s\n' "periphery-tailscale"
      ;;
    *)
      die "unknown variant '$1'."
      ;;
  esac
}

is_command() {
  case "${1:-}" in
    up|down|restart|ps|logs|config|pull)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

list_hosts() {
  local host_env_dir="$1"
  local env_file

  for env_file in "$host_env_dir"/*.env; do
    [ -e "$env_file" ] || return 0
    printf '  %s\n' "$(basename "$env_file" .env)"
  done
}

resolve_host_env() {
  local stack_dir="$1"
  local host_name="$2"
  local env_file="$stack_dir/host-env/$host_name.env"

  if [ ! -f "$env_file" ] && [[ "$host_name" == *.* ]]; then
    env_file="$stack_dir/host-env/${host_name%%.*}.env"
  fi

  if [ ! -f "$env_file" ]; then
    echo "Error: no env file found for stack '$STACK' and host '$host_name'." >&2
    echo "Available hosts:" >&2
    list_hosts "$stack_dir/host-env" >&2
    exit 1
  fi

  printf '%s\n' "$env_file"
}

load_env() {
  set -a
  . "$ENV_FILE"
  if [ -f "$STACK_DIR/.secrets.env" ]; then
    . "$STACK_DIR/.secrets.env"
  fi
  set +a

  export KOMODO_INFRA_DATA_DIR="${KOMODO_INFRA_DATA_DIR:-$HOME/komodo-data}"
  export KOMODO_INFRA_IMAGE_PREFIX="${KOMODO_INFRA_IMAGE_PREFIX:-}"
}

print_context() {
  echo "Command: $COMMAND"
  echo "Stack:   $STACK"
  echo "Host:    ${KOMODO_INFRA_HOSTNAME:-$TARGET_HOST}"
  echo "Env:     $ENV_FILE"
  echo "Data:    $KOMODO_INFRA_DATA_DIR"
  if [ -n "$KOMODO_INFRA_IMAGE_PREFIX" ]; then
    echo "Images:  ${KOMODO_INFRA_IMAGE_PREFIX%/}"
  fi

  if [ -n "${TAILSCALE_HOSTNAME:-}" ]; then
    echo "TS:      $TAILSCALE_HOSTNAME"
  fi
  if [ -n "${TAILSCALE_TAGS:-}" ]; then
    echo "Tags:    $TAILSCALE_TAGS"
  fi
  if [ -n "${TS_RELAY_SERVER_PORT:-}" ]; then
    echo "Relay:   UDP $TS_RELAY_SERVER_PORT"
  fi
}

has_tailscale_state() {
  local state_dir="$KOMODO_INFRA_DATA_DIR/tailscale"

  [ -d "$state_dir/state" ] || { [ -r "$state_dir" ] && [ -n "$(find "$state_dir" -maxdepth 1 -mindepth 1 -print -quit)" ]; }
}

ensure_tailscale_auth_key() {
  if [ "$COMMAND" != "up" ] || [ "$STACK" != "periphery-tailscale" ]; then
    return
  fi

  if [ -n "${TAILSCALE_AUTH_KEY:-}" ] || has_tailscale_state; then
    return
  fi

  if [ ! -t 0 ]; then
    die "TAILSCALE_AUTH_KEY is required for first periphery-tailscale startup without existing state."
  fi

  read -r -s -p "Tailscale auth key: " TAILSCALE_AUTH_KEY
  echo

  if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    die "Tailscale auth key cannot be empty on first startup."
  fi

  export TAILSCALE_AUTH_KEY
}

run_compose() {
  local compose_args=(--project-directory "$STACK_DIR")

  case "$COMMAND" in
    up)
      mkdir -p "$KOMODO_INFRA_DATA_DIR"
      docker compose "${compose_args[@]}" up -d "$@"
      ;;
    down)
      docker compose "${compose_args[@]}" down "$@"
      ;;
    restart)
      docker compose "${compose_args[@]}" restart "$@"
      ;;
    ps)
      docker compose "${compose_args[@]}" ps "$@"
      ;;
    logs)
      docker compose "${compose_args[@]}" logs -f "$@"
      ;;
    config)
      docker compose "${compose_args[@]}" config "$@"
      ;;
    pull)
      docker compose "${compose_args[@]}" pull "$@"
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    -m|--mirror)
      mirror_registry="docker.libcuda.so"
      if [ -n "${2:-}" ] && ! is_command "$2"; then
        mirror_registry="$2"
        shift
      fi
      KOMODO_INFRA_IMAGE_PREFIX="${mirror_registry%/}/"
      export KOMODO_INFRA_IMAGE_PREFIX
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -lt 2 ]; then
  usage
fi

COMMAND="$(normalize_command "$1")"
STACK="$(normalize_stack "$2")"
shift 2

if [ "${1:-}" = "--" ]; then
  TARGET_HOST="$(hostname)"
  echo "No hostname provided, defaulting to current host: $TARGET_HOST"
  shift
elif [ -n "${1:-}" ]; then
  TARGET_HOST="$1"
  shift
else
  TARGET_HOST="$(hostname)"
  echo "No hostname provided, defaulting to current host: $TARGET_HOST"
fi

if [ "${1:-}" = "--" ]; then
  shift
fi

STACK_DIR="$INFRA_DIR/$STACK"
ENV_FILE="$(resolve_host_env "$STACK_DIR" "$TARGET_HOST")"

load_env
print_context
ensure_tailscale_auth_key
run_compose "$@"
