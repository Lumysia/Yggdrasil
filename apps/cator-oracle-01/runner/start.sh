#!/bin/sh
# Starts one Forgejo runner. Registers on first start, then runs the daemon with
# the connection passed as flags, because the runner ignores runner.fetch_interval
# for connections loaded from .runner (it falls back to polling every 2s).
set -eu

: "${FORGEJO_DOMAIN:?}" "${FORGEJO_RUNNER_NAME:?}"
labels="${FORGEJO_RUNNER_LABELS:-ubuntu-latest:docker://node:16-bullseye,docker:docker://node:16-bullseye}"
reg=/data/.runner

if [ ! -f "$reg" ]; then
  echo "Registering ${FORGEJO_RUNNER_NAME}..."
  cd /data
  forgejo-runner register --no-interactive --instance "https://${FORGEJO_DOMAIN}" \
    --token "${FORGEJO_RUNNER_REGISTRATION_TOKEN:?}" --name "$FORGEJO_RUNNER_NAME" --labels "$labels"
fi

field() { sed -n "s/^ *\"$1\": *\"\([^\"]*\)\".*/\1/p" "$reg" | head -n 1; }

umask 077
field token > /tmp/runner-token

set -- --url "$(field address)" --uuid "$(field uuid)" --token-url file:///tmp/runner-token \
  --fetch-interval "${FORGEJO_RUNNER_FETCH_INTERVAL:-60s}"
old_ifs=$IFS; IFS=,
for l in $labels; do set -- "$@" --label "$l"; done
IFS=$old_ifs

# Run from / so the daemon doesn't also load ./.runner, which would conflict with the flags.
cd /
echo "Starting daemon..."
exec forgejo-runner daemon "$@"
