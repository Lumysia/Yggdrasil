#!/usr/bin/env bash
set -e

# --- Configuration ---
ACTION="switch"
HOSTNAME=""
PROXY_URL=""
NIX_FLAGS="--extra-experimental-features nix-command --extra-experimental-features flakes"
INSTALL_MODE=false
UPDATE_MODE=false
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$SCRIPT_DIR/nixos"

# --- Helper Functions ---
usage() {
  echo "Usage: $0 [-b] [-u] [-p <url>] [-I] [hostname]"
  echo
  echo "  A script to build or rebuild a NixOS system from the repository flake."
  echo
  echo "  Modes (choose one):"
  echo "    (default)     Use 'nixos-rebuild switch' to build and activate immediately."
  echo "    -b, --boot    Use 'nixos-rebuild boot' to make the build the default for the next boot."
  echo "    -I, --install Use 'nixos-install' for a first-time installation (overrides -b)."
  echo
  echo "  Options:"
  echo "    -u, --update       Update flake inputs and git pull before building."
  echo "    -p, --proxy <url>  Set the http/https proxy for the operation."
  echo "    -h, --help         Display this help message and exit."
  echo
  echo "  Arguments:"
  echo "    [hostname]         Optional hostname to build. Defaults to the current host."
  exit 1
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -b|--boot)
      ACTION="boot"
      shift
      ;;
    -I|--install)
      INSTALL_MODE=true
      shift
      ;;
    -u|--update)
      UPDATE_MODE=true
      shift
      ;;
    -p|--proxy)
      if [ -z "$2" ]; then
        echo "Error: Option '$1' requires a URL as an argument." >&2
        usage
      fi
      PROXY_URL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [ -n "$HOSTNAME" ]; then
        echo "Error: Multiple hostnames provided. Please specify only one." >&2
        usage
      fi
      HOSTNAME="$1"
      shift
      ;;
  esac
done

# --- Prerequisite Checks ---
if [ -z "$HOSTNAME" ]; then
  HOSTNAME="$(hostname)"
  echo "ℹ︎ No hostname provided, defaulting to current host: $HOSTNAME"
fi

if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Error: This script must be run from within the repository." >&2
  exit 1
fi

if [ ! -f "$FLAKE_DIR/flake.nix" ]; then
  echo "Error: Could not find flake at '$FLAKE_DIR/flake.nix'." >&2
  exit 1
fi

# --- Display Configuration ---
echo
echo "--- Configuration ---"
if [ "$INSTALL_MODE" = true ]; then
  echo "Mode:     Initial Build (nixos-install)"
  if [ "$ACTION" = "boot" ]; then
    echo "          (Note: --install overrides --boot)"
  fi
else
  echo "Mode:     Rebuild"
  echo "Action:   $ACTION"
fi
echo "Hostname: $HOSTNAME"
echo "Flake:    $FLAKE_DIR"
echo "Update:   $UPDATE_MODE"
if [ -n "$PROXY_URL" ]; then
  echo "Proxy:    $PROXY_URL"
fi
echo "---------------------"
echo

# --- Execution ---
if [ -n "$PROXY_URL" ]; then
  export all_proxy="$PROXY_URL"
  echo "✓ Proxy exported."
else
  echo "ℹ︎ No proxy specified."
fi

if [ "$UPDATE_MODE" = true ]; then
  echo "→ Pulling latest changes from remote..."
  git -C "$SCRIPT_DIR" pull
  echo "✓ Git pull completed."

  echo "→ Running 'nix flake update'..."
  nix $NIX_FLAGS flake update --flake "$FLAKE_DIR"
  echo "✓ Flake updated successfully."
else
  echo "ℹ︎ Skipping update (use -u to enable)."
fi

if [ "$INSTALL_MODE" = true ]; then
  echo "→ Running 'nixos-install' for flake '$FLAKE_DIR#$HOSTNAME'..."
  nixos-install --root /mnt --flake "$FLAKE_DIR#$HOSTNAME"
  echo
  echo "✅ NixOS build for '$HOSTNAME' completed successfully."
else
  echo "→ Running 'nixos-rebuild $ACTION' for flake '$FLAKE_DIR#$HOSTNAME'..."
  nixos-rebuild "$ACTION" --flake "$FLAKE_DIR#$HOSTNAME" --use-remote-sudo
  echo
  echo "✅ NixOS rebuild for '$HOSTNAME' completed successfully with action '$ACTION'."
fi
