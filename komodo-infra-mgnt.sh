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
-m pulls Docker Hub images through a mirror (default docker.libcuda.so).
  --mirror=<registry> also works after the variant.

Data lives in KOMODO_INFRA_DATA_DIR (default: komodo-data next to this repo).
Secrets (Core settings, TAILSCALE_AUTH_KEY) go in the git-ignored
komodo/infra/<variant>/.env, which Compose reads on its own.

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

DEFAULT_MIRROR="docker.libcuda.so"

set_mirror() {
  KOMODO_INFRA_DOCKER_IMAGE_PREFIX="${1%/}/"
  export KOMODO_INFRA_DOCKER_IMAGE_PREFIX
}

normalize_command() {
  is_command "$1" || die "unknown command '$1'."
  printf '%s\n' "$1"
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
    echo "Warning: $STACK_DIR/.secrets.env is not git-ignored; move its values into .env." >&2
    . "$STACK_DIR/.secrets.env"
  fi
  set +a

  # Next to the repo rather than $HOME, so running the script with sudo
  # still finds the existing data instead of starting from an empty dir.
  export KOMODO_INFRA_DATA_DIR="${KOMODO_INFRA_DATA_DIR:-$(dirname -- "$SCRIPT_DIR")/komodo-data}"
  export KOMODO_INFRA_DOCKER_IMAGE_PREFIX="${KOMODO_INFRA_DOCKER_IMAGE_PREFIX:-}"
}

set_disk_mounts() {
  # /etc/hostname sits on Docker's data disk, which is usually the root disk.
  # Report /data too when it is a separate filesystem; on the same one it
  # would be counted twice in Komodo's disk total.
  if [ -n "${PERIPHERY_INCLUDE_DISK_MOUNTS:-}" ]; then
    return
  fi
  PERIPHERY_INCLUDE_DISK_MOUNTS="/etc/hostname"
  if [ -d /data ] && [ "$(stat -c %d /data)" != "$(stat -c %d /)" ]; then
    PERIPHERY_INCLUDE_DISK_MOUNTS="$PERIPHERY_INCLUDE_DISK_MOUNTS,/data"
  fi
  export PERIPHERY_INCLUDE_DISK_MOUNTS
}

print_context() {
  echo "Command: $COMMAND"
  echo "Stack:   $STACK"
  echo "Host:    ${KOMODO_INFRA_HOSTNAME:-$TARGET_HOST}"
  echo "Env:     $ENV_FILE"
  echo "Data:    $KOMODO_INFRA_DATA_DIR"
  echo "Disks:   $PERIPHERY_INCLUDE_DISK_MOUNTS"
  if [ -n "$KOMODO_INFRA_DOCKER_IMAGE_PREFIX" ]; then
    echo "Images:  Docker Hub via ${KOMODO_INFRA_DOCKER_IMAGE_PREFIX%/}"
  fi

  if [ -n "${TAILSCALE_HOSTNAME:-}" ]; then
    echo "TS:      $TAILSCALE_HOSTNAME"
  fi
  if [ -n "${TAILSCALE_TAGS:-}" ]; then
    echo "Tags:    $TAILSCALE_TAGS (first login only)"
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

  if [ -n "${TAILSCALE_AUTH_KEY:-}" ] || has_tailscale_state ||
    grep -q '^TAILSCALE_AUTH_KEY=.' "$STACK_DIR/.env" 2>/dev/null; then
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
  local compose=(docker compose --project-directory "$STACK_DIR")

  case "$COMMAND" in
    up)
      mkdir -p "$KOMODO_INFRA_DATA_DIR"
      "${compose[@]}" up -d "$@"
      ;;
    logs)
      "${compose[@]}" logs -f "$@"
      ;;
    *)
      "${compose[@]}" "$COMMAND" "$@"
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    -m|--mirror)
      if [ -n "${2:-}" ] && ! is_command "$2"; then
        set_mirror "$2"
        shift
      else
        set_mirror "$DEFAULT_MIRROR"
      fi
      shift
      ;;
    --mirror=*)
      set_mirror "${1#--mirror=}"
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

case "${1:-}" in
  -m|--mirror)
    set_mirror "$DEFAULT_MIRROR"
    shift
    ;;
  --mirror=*)
    set_mirror "${1#--mirror=}"
    shift
    ;;
esac

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
set_disk_mounts
print_context
ensure_tailscale_auth_key
run_compose "$@"
