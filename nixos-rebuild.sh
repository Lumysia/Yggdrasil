#!/usr/bin/env bash
# Build and activate a host from this repo's flake.
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 [-b] [-I] [-p <url>] [hostname]

  (default)          nixos-rebuild switch
  -b, --boot         nixos-rebuild boot (activate on next boot)
  -I, --install      nixos-install into /mnt (first install)
  -p, --proxy <url>  proxy for fetching (exported as all_proxy)
  hostname           defaults to the current host
USAGE
  exit 1
}

action=switch
host=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--boot) action=boot; shift ;;
    -I|--install) action=install; shift ;;
    -p|--proxy) [[ -n "${2:-}" ]] || usage; export all_proxy="$2"; shift 2 ;;
    -h|--help|-*) usage ;;
    *) [[ -z "$host" ]] || usage; host="$1"; shift ;;
  esac
done

host="${host:-$(hostname)}"
flake="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/nixos#$host"

if [[ "$action" == install ]]; then
  nixos-install --root /mnt --flake "$flake"
else
  nixos-rebuild "$action" --flake "$flake" --sudo
fi
