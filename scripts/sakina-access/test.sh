#!/usr/bin/env bash
# Tests for sakina-access, run as a normal user with stub commands:
#   - the allow/deny rules of the two helper scripts
#   - the from list, root's authorized_keys edits (through a symlink), grants and revokes
#   - the self-update and its timer
#   - the key lines against a real sshd, when one is found ($SSHD, PATH or /usr/sbin/sshd)
# shellcheck disable=SC2016 # command lines are single-quoted so they reach the helpers unexpanded
set -u

here=$(cd "$(dirname "$0")" && pwd)
script=$here/sakina-access
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0 fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
not() { ! "$@"; }
check() { # check <description> <command...>
  local d=$1; shift
  if "$@"; then ok; else bad "$d"; fi
}

# ---------------------------------------------------------------- helper scripts

hbin=$work/helper-bin
mkdir -p "$hbin"
for c in journalctl systemctl cat head tail ls wc stat zcat grep zgrep du ip df free uptime lsblk ps ss \
  findmnt last who sensors pveversion nixos-version uname apt date hostname smartctl nvme zpool zfs \
  qm pct pvesm pvesh dmesg ha-manager pvecm docker sudo; do
  printf '#!/bin/sh\necho "RAN %s${*:+ $*}"\n' "$c" > "$hbin/$c"
done
printf '#!/bin/sh\n' > "$hbin/logger"
chmod +x "$hbin"/*
for c in realpath xargs printf; do ln -s "$(type -P "$c")" "$hbin/$c"; done

sudo_rule=$work/sudo-rule
helper() { # helper <writer function> <output file>: the helper with the stub PATH
  bash -c 'source "$1"; "$2"' _ "$script" "$1" |
    sed -e "s|^export PATH=[^ ]*|export PATH=$hbin|" -e "s|/etc/sudoers.d/sakina-ro|$sudo_rule|" > "$2"
}
helper write_ro_cmd "$work/sakina-ro"
helper write_priv_cmd "$work/sakina-ro-priv"

run_ssh() { # run_ssh <helper> <command line>: prints output, returns the exit code
  (cd "$work" && SSH_ORIGINAL_COMMAND=$2 bash "$work/$1" 2>&1)
}
allow() { # allow <helper> <command line> <expected output>
  local out rc
  out=$(run_ssh "$1" "$2"); rc=$?
  if [ $rc -eq 0 ] && [ "$out" = "$3" ]; then ok; else bad "$1 should run [$2] as [$3], got rc=$rc [$out]"; fi
}
deny() { # deny <helper> <command line>
  local out rc
  out=$(run_ssh "$1" "$2"); rc=$?
  if [ $rc -eq 2 ] && [[ $out != *RAN* ]]; then ok; else bad "$1 should refuse [$2], got rc=$rc [$out]"; fi
}

allow sakina-ro 'journalctl -u ssh -n 20' 'RAN journalctl --no-pager -u ssh -n 20'
allow sakina-ro 'journalctl -u "$(id)"' 'RAN journalctl --no-pager -u $(id)'
allow sakina-ro 'journalctl -u x;id' 'RAN journalctl --no-pager -u x;id'
deny  sakina-ro 'journalctl --vacuum-size=1M'
deny  sakina-ro 'journalctl --vacuum-time 1d'
deny  sakina-ro 'journalctl --rotate'
deny  sakina-ro 'journalctl --flush'
deny  sakina-ro 'journalctl --pager-end'
allow sakina-ro 'systemctl status nginx' 'RAN systemctl --no-pager status nginx'
allow sakina-ro 'systemctl' 'RAN systemctl --no-pager'
allow sakina-ro 'systemctl --failed list-units' 'RAN systemctl --no-pager --failed list-units'
deny  sakina-ro 'systemctl stop nginx'
deny  sakina-ro 'systemctl --no-block restart nginx'
deny  sakina-ro 'systemctl -H otherhost status'
deny  sakina-ro 'systemctl --machine=x status'
allow sakina-ro 'cat /var/log/syslog' 'RAN cat /var/log/syslog'
allow sakina-ro 'tail -n 50 /var/log/syslog' 'RAN tail -n 50 /var/log/syslog'
allow sakina-ro 'cat /etc/pve/qemu-server/100.conf' 'RAN cat /etc/pve/qemu-server/100.conf'
allow sakina-ro 'ls -la -- /proc/1' 'RAN ls -la -- /proc/1'
deny  sakina-ro 'cat /etc/shadow'
deny  sakina-ro 'cat /var/log/../../etc/shadow'
deny  sakina-ro 'cat /var/log/../etc/shadow'
deny  sakina-ro 'cat var/log/syslog'
deny  sakina-ro 'cat /etc/pve/priv/authkey.key'
deny  sakina-ro 'cat /etc/pve/priv'
deny  sakina-ro 'cat /etc/pve/local/pve-ssl.key'
deny  sakina-ro 'cat /var/log/syslog; id'
deny  sakina-ro 'cat /var/log/syslog && id'
deny  sakina-ro 'cat $(id)'
deny  sakina-ro 'cat `id`'
deny  sakina-ro 'head -- -n /etc/shadow'
allow sakina-ro 'grep -i error /var/log/syslog' 'RAN grep -i error /var/log/syslog'
allow sakina-ro 'grep -C 3 /etc/shadow /var/log/syslog' 'RAN grep -C 3 /etc/shadow /var/log/syslog'
allow sakina-ro 'grep -e root /var/log/auth.log' 'RAN grep -e root /var/log/auth.log'
deny  sakina-ro 'grep root /etc/shadow'
deny  sakina-ro 'grep -e root /etc/shadow'
deny  sakina-ro 'grep -f /etc/shadow /var/log/syslog'
deny  sakina-ro 'grep --file=/etc/shadow /var/log/syslog'
deny  sakina-ro 'grep -f/etc/shadow /var/log/syslog'
allow sakina-ro 'ip -br addr' 'RAN ip -br addr'
deny  sakina-ro 'ip netns exec x sh'
deny  sakina-ro 'ip -batch /tmp/x'
allow sakina-ro 'apt list --upgradable' 'RAN apt list --upgradable'
allow sakina-ro 'apt policy openssh-server' 'RAN apt policy openssh-server'
deny  sakina-ro 'apt install curl'
deny  sakina-ro 'apt-get install curl'
allow sakina-ro 'date' 'RAN date'
deny  sakina-ro 'date -s 2020-01-01'
deny  sakina-ro 'hostname evil'
deny  sakina-ro 'bash'
deny  sakina-ro 'sh -c id'
deny  sakina-ro 'rm -rf /'
deny  sakina-ro 'sudo -n /usr/local/sbin/sakina-ro-priv docker ps'
deny  sakina-ro 'docker ps'
touch "$sudo_rule"
allow sakina-ro 'docker ps -a' 'RAN sudo -n /usr/local/sbin/sakina-ro-priv docker ps -a'
rm -f "$sudo_rule"

allow sakina-ro-priv 'docker ps -a' 'RAN docker ps -a'
allow sakina-ro-priv 'docker logs --tail 20 web' 'RAN docker logs --tail 20 web'
allow sakina-ro-priv 'docker logs "$(id)"' 'RAN docker logs $(id)'
allow sakina-ro-priv 'docker stats' 'RAN docker stats --no-stream'
allow sakina-ro-priv 'docker system df' 'RAN docker system df'
allow sakina-ro-priv 'docker compose ls' 'RAN docker compose ls'
deny  sakina-ro-priv 'docker exec web sh'
deny  sakina-ro-priv 'docker run --rm alpine'
deny  sakina-ro-priv 'docker inspect web'
deny  sakina-ro-priv 'docker system prune -af'
deny  sakina-ro-priv 'docker image prune'
deny  sakina-ro-priv 'docker compose up -d'
deny  sakina-ro-priv 'docker ps -H tcp://192.0.2.1:2375'
deny  sakina-ro-priv 'docker logs --host=tcp://192.0.2.1 web'
deny  sakina-ro-priv 'docker ps --context other'
deny  sakina-ro-priv 'docker ps; id'
allow sakina-ro-priv 'smartctl --scan' 'RAN smartctl --scan'
allow sakina-ro-priv 'smartctl -a /dev/sda' 'RAN smartctl -a /dev/sda'
allow sakina-ro-priv 'smartctl -l selftest -d nvme /dev/nvme0n1' 'RAN smartctl -l selftest -d nvme /dev/nvme0n1'
deny  sakina-ro-priv 'smartctl -t long /dev/sda'
deny  sakina-ro-priv 'smartctl -a /etc/shadow'
deny  sakina-ro-priv 'smartctl -a /dev/sda /dev/sdb'
allow sakina-ro-priv 'nvme smart-log /dev/nvme0' 'RAN nvme smart-log /dev/nvme0'
deny  sakina-ro-priv 'nvme format /dev/nvme0'
allow sakina-ro-priv 'zpool status -v tank' 'RAN zpool status -v tank'
allow sakina-ro-priv 'zpool events -v' 'RAN zpool events -v'
deny  sakina-ro-priv 'zpool scrub tank'
deny  sakina-ro-priv 'zpool events -c'
deny  sakina-ro-priv 'zpool events -vc'
deny  sakina-ro-priv 'zpool events -f'
deny  sakina-ro-priv 'zpool iostat 5'
deny  sakina-ro-priv 'zpool status tank 1'
deny  sakina-ro-priv 'zpool status --long'
allow sakina-ro-priv 'zfs list -o name,used' 'RAN zfs list -o name,used'
deny  sakina-ro-priv 'zfs destroy tank/x'
deny  sakina-ro-priv 'zfs set compression=off tank'
allow sakina-ro-priv 'qm list' 'RAN qm list'
allow sakina-ro-priv 'qm config 100' 'RAN qm config 100'
allow sakina-ro-priv 'pct status 101 --verbose' 'RAN pct status 101 --verbose'
deny  sakina-ro-priv 'qm stop 100'
deny  sakina-ro-priv 'qm guest exec 100 id'
deny  sakina-ro-priv 'pct exec 101 id'
deny  sakina-ro-priv 'qm config 100;id'
allow sakina-ro-priv 'pvesm status' 'RAN pvesm status'
deny  sakina-ro-priv 'pvesm free local:100/x.qcow2'
allow sakina-ro-priv 'pvesh get /nodes --output-format json' 'RAN pvesh get /nodes --output-format json'
deny  sakina-ro-priv 'pvesh set /nodes/x/config'
deny  sakina-ro-priv 'pvesh create /nodes/x/qemu'
deny  sakina-ro-priv 'pvesh delete /nodes/x/qemu/100'
deny  sakina-ro-priv 'pvesh get nodes'
deny  sakina-ro-priv 'pvesh get /nodes;id'
deny  sakina-ro-priv 'pvesh get /nodes $(id)'
allow sakina-ro-priv 'dmesg -T -l err,warn' 'RAN dmesg --nopager -T -l err,warn'
deny  sakina-ro-priv 'dmesg -H'
deny  sakina-ro-priv 'dmesg -c'
deny  sakina-ro-priv 'dmesg -C'
deny  sakina-ro-priv 'dmesg -l "err;id"'
allow sakina-ro-priv 'ha-manager status' 'RAN ha-manager status'
deny  sakina-ro-priv 'ha-manager set vm:100 --state stopped'
deny  sakina-ro-priv 'pvecm expected 1'
deny  sakina-ro-priv 'cat /etc/shadow'
deny  sakina-ro-priv 'bash'
deny  sakina-ro-priv ''

out=$(bash "$work/sakina-ro-priv" docker ps 2>&1)
check "sakina-ro-priv takes its command as arguments (the sudo route)" [ "$out" = "RAN docker ps" ]
out=$(bash "$work/sakina-ro-priv" docker exec web sh 2>&1); rc=$?
check "sakina-ro-priv refuses through the sudo route too" [ $rc -eq 2 ]

# ---------------------------------------------------------------- main script

sbin=$work/bin
mkdir -p "$sbin"
calls=$work/calls
cat > "$sbin/sshd" <<'EOF'
#!/bin/sh
[ "$1" = -T ] && echo "permitrootlogin ${STUB_PERMIT_ROOT:-prohibit-password}"
EOF
cat > "$sbin/install" <<'EOF'
#!/bin/sh
# drop the owner and group, which need root
n=0
for a in "$@"; do
  shift
  case "$n:$a" in 1:*) n=0; continue ;; *:-o|*:-g) n=1; continue ;; esac
  set -- "$@" "$a"
done
exec /usr/bin/install "$@"
EOF
for c in systemctl systemd-run visudo logger chown pkill; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$calls" > "$sbin/$c"
done
cat > "$sbin/curl" <<'EOF'
#!/bin/sh
[ -n "${STUB_DOWNLOAD:-}" ] || exit 22
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
cp "$STUB_DOWNLOAD" "$out"
EOF
chmod +x "$sbin"/*

ro_blob=$(sed -n "s/^RO_KEY='\(.*\)'$/\1/p" "$script")
priv_blob=$(sed -n "s/^PRIV_KEY='\(.*\)'$/\1/p" "$script")
root_blob=$(sed -n "s/^ROOT_KEY='\(.*\)'$/\1/p" "$script")
other_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOther admin@laptop'

fresh() { # a new fake host: root's authorized_keys is a symlink, like on Proxmox
  h=$work/host
  rm -rf "$h"; : > "$calls"
  mkdir -p "$h/root/.ssh" "$h/pve/priv" "$h/home/sakina/.ssh" "$h/units" "$h/run" "$h/sbin"
  printf '%s' "$other_key" > "$h/pve/priv/authorized_keys"
  ln -s "$h/pve/priv/authorized_keys" "$h/root/.ssh/authorized_keys"
  printf '@includedir /etc/sudoers.d\n' > "$h/sudoers"
}

# Runs the given shell code with the script's functions loaded and paths pointed at the fake host.
in_script() {
  PATH="$sbin:$PATH" bash -c '
    source "$1"; set +e
    h=$2
    ROOT_KEYS=$h/root/.ssh/authorized_keys USER_HOME=$h/home/sakina
    CONF_DIR=$h/conf FROM_FILE=$h/conf/from SUDOERS=$h/sudoers.d/sakina-ro SUDOERS_MAIN=$h/sudoers
    UNIT_DIR=$h/units NIXOS_MARK=$h/NIXOS RUN_DIR=$h/run SELF=$h/sbin/sakina-access
    eval "$3"' _ "$script" "$h" "$1"
}
keys() { cat "$h/pve/priv/authorized_keys"; }
count() { grep -c -F -- "$1" "$h/pve/priv/authorized_keys"; }
still_link() { [ -L "$h/root/.ssh/authorized_keys" ]; }

# from list
fresh
out=$(in_script 'load_from "192.0.2.1, 198.51.100.0/24
2001:db8::/32"; echo "$FROM"; cat "$FROM_FILE"')
check "--from list is normalized and saved" [ "$out" = $'192.0.2.1,198.51.100.0/24,2001:db8::/32\n192.0.2.1,198.51.100.0/24,2001:db8::/32' ]
out=$(in_script 'load_from; echo "$FROM"')
check "later runs read the saved list" [ "$out" = "192.0.2.1,198.51.100.0/24,2001:db8::/32" ]
fresh
in_script 'load_from' >/dev/null 2>&1
check "install without a list is refused" [ $? -ne 0 ]
check "and writes no list" [ ! -e "$h/conf/from" ]
in_script 'load_from "192.0.2.1\",command=\"/bin/sh"' >/dev/null 2>&1
check "a list that could break out of from=\"...\" is refused" [ $? -ne 0 ]

# migration from an install that had the list built in
fresh
printf 'restrict,from="192.0.2.7,198.51.100.9",command="/usr/local/sbin/sakina-ro" %s sakina-cat-readonly\n' "$ro_blob" > "$h/home/sakina/.ssh/authorized_keys"
out=$(in_script 'load_from; echo "$FROM"; cat "$FROM_FILE"')
check "the list is taken over from the read-only key line" [ "$out" = $'192.0.2.7,198.51.100.9\n192.0.2.7,198.51.100.9' ]
fresh
printf '%s\nrestrict,from="192.0.2.8",command="/usr/local/sbin/sakina-ro-priv" %s sakina-cat-priv\n' "$other_key" "$priv_blob" > "$h/pve/priv/authorized_keys"
out=$(in_script 'load_from; echo "$FROM"')
check "the list is taken over from the old priv line in root's keys" [ "$out" = "192.0.2.8" ]

# root's key file: priv key, grants, revokes
fresh
printf '%s\nrestrict,from="192.0.2.8",command="/usr/local/sbin/sakina-ro-priv" %s sakina-cat-priv\nfrom="192.0.2.8",expiry-time="203001010000Z",command="/usr/local/sbin/sakina-root-session" %s sakina-cat-root-temp' \
  "$other_key" "$priv_blob" "$root_blob" > "$h/pve/priv/authorized_keys"
in_script 'load_from "192.0.2.9"; install_priv_access; install_priv_access'
check "old priv line is replaced" [ "$(count sakina-cat-priv)" -eq 0 ]
check "exactly one new priv line" [ "$(count 'restrict,from="192.0.2.9",command="/usr/local/sbin/sakina-ro-priv" '"$priv_blob"' sakina-access-priv')" -eq 1 ]
check "other keys are kept" [ "$(count "$other_key")" -eq 1 ]
check "the old grant is still found as active" in_script 'root_active'
check "the symlink is written through, not replaced" still_link
in_script 'load_from; grant_root 4' >/dev/null
check "grant replaces the old temporary line" [ "$(count sakina-cat-root-temp)" -eq 0 ]
check "grant adds one temporary line" [ "$(count sakina-access-root-temp)" -eq 1 ]
check "the grant has a future expiry-time" in_script 'root_active'
check "the grant line pins the session command and source" grep -qF "from=\"192.0.2.9\",expiry-time=\"" "$h/pve/priv/authorized_keys"
check "grant starts the revoke timer" grep -q "systemd-run --quiet --unit=sakina-access-expire --on-active=4h .* $h/sbin/sakina-access off" "$calls"
check "symlink kept after grant" still_link
echo 999999 > "$h/run/root.999999"
in_script 'revoke_root' >/dev/null
check "revoke removes the temporary line" [ "$(count root-temp)" -eq 0 ]
check "revoke keeps the priv line" [ "$(count sakina-access-priv)" -eq 1 ]
check "revoke keeps other keys" [ "$(count "$other_key")" -eq 1 ]
check "revoke clears recorded sessions" [ ! -e "$h/run/root.999999" ]
check "symlink kept after revoke" still_link
in_script 'FROM=192.0.2.9; append_root_key "$(root_line 202001010000)"'
check "an expired grant is not active" in_script '! root_active'
check "an expired grant still reports its stamp" [ "$(in_script root_expiry)" = 202001010000 ]

# PermitRootLogin no
fresh
export STUB_PERMIT_ROOT=no
in_script 'FROM=192.0.2.9; grant_root 2' >/dev/null 2>&1
check "no temporary root when sshd refuses root logins" [ $? -ne 0 ]
check "and no key line is added" [ "$(count sakina-access)" -eq 0 ]
mkdir -p "$h/sudoers.d"
in_script 'FROM=192.0.2.9; install_priv_access'
check "root reads move to a sudo rule" [ "$(cat "$h/sudoers.d/sakina-ro" 2>/dev/null)" = "sakina ALL=(root) NOPASSWD: /usr/local/sbin/sakina-ro-priv" ]
check "the sudo rule is checked with visudo" grep -q "^visudo -cqf" "$calls"
check "no priv key line then" [ "$(count sakina-access-priv)" -eq 0 ]
: > "$h/sudoers"
in_script 'FROM=192.0.2.9; install_priv_access' 2>/dev/null
check "no sudo rule when sudoers has no drop-in directory" [ ! -e "$h/sudoers.d/sakina-ro" ]
unset STUB_PERMIT_ROOT

# update timer
fresh
in_script 'install_update_timer'
check "update service is written" grep -q "^ExecStart=$h/sbin/sakina-access update$" "$h/units/sakina-access-update.service"
check "update timer is daily with a random delay" grep -q '^RandomizedDelaySec=' "$h/units/sakina-access-update.timer"
check "timer enabled" grep -q "^systemctl enable --now sakina-access-update.timer" "$calls"
: > "$calls"
in_script 'install_update_timer'
check "unchanged units need no daemon-reload" not grep -q daemon-reload "$calls"
fresh
touch "$h/NIXOS"
in_script 'install_update_timer'
check "no unit files on NixOS" [ -z "$(ls "$h/units")" ]

# self-update
version() { # version <file> <name> [exit code of its install]
  printf '#!/usr/bin/env bash\n%s\necho "%s $*" >> "%s"\nexit %s\n' \
    "$(sed -n 2p "$script")" "$2" "$calls" "${3:-0}" > "$1"
}
fresh
version "$h/sbin/sakina-access" OLD
cp "$h/sbin/sakina-access" "$work/old"
in_script 'update_self' >/dev/null 2>&1
check "failed download fails the update" [ $? -ne 0 ]
check "failed download keeps the current version" cmp -s "$h/sbin/sakina-access" "$work/old"
printf '#!/usr/bin/env bash\n%s\nif then\n' "$(sed -n 2p "$script")" > "$work/broken"
STUB_DOWNLOAD=$work/broken in_script 'update_self' >/dev/null 2>&1
check "a download that fails bash -n is not installed" cmp -s "$h/sbin/sakina-access" "$work/old"
printf '<html>rate limited</html>\n' > "$work/html"
STUB_DOWNLOAD=$work/html in_script 'update_self' >/dev/null 2>&1
check "a download without the header is not installed" cmp -s "$h/sbin/sakina-access" "$work/old"
out=$(STUB_DOWNLOAD=$work/old in_script 'update_self')
check "same version is left alone" [ "$out" = "Already up to date." ]
check "same version runs no install" not grep -q "OLD install" "$calls"
version "$work/new" NEW
STUB_DOWNLOAD=$work/new in_script 'update_self' >/dev/null
check "new version is installed" cmp -s "$h/sbin/sakina-access" "$work/new"
check "new version's install runs" grep -q "^NEW install$" "$calls"
fresh
version "$h/sbin/sakina-access" OLD
cp "$h/sbin/sakina-access" "$work/old"
version "$work/new" NEW 1
STUB_DOWNLOAD=$work/new in_script 'update_self' >/dev/null 2>&1
check "a new version whose install fails is rolled back" cmp -s "$h/sbin/sakina-access" "$work/old"
check "and the old version's install runs again" grep -q "^OLD install$" "$calls"

# ---------------------------------------------------------------- real sshd

sshd_bin=${SSHD:-$(command -v sshd || echo /usr/sbin/sshd)}
if [ -x "$sshd_bin" ]; then
  s=$work/sshd
  mkdir -p "$s"
  for k in host ro priv root expired stranger; do ssh-keygen -q -t ed25519 -N '' -C "$k" -f "$s/$k"; done
  pub() { cut -d' ' -f1,2 "$s/$1.pub"; }
  printf '#!/bin/sh\necho "ROOT $SSH_ORIGINAL_COMMAND"\n' > "$s/root-session"
  chmod +x "$s/root-session"
  install -m 0755 "$work/sakina-ro" "$work/sakina-ro-priv" "$s/"
  bash -c '
    source "$1"; s=$2; FROM="127.0.0.1,::1"
    RO_CMD=$s/sakina-ro PRIV_CMD=$s/sakina-ro-priv ROOT_SESSION=$s/root-session
    RO_KEY=$3 PRIV_KEY=$4 ROOT_KEY=$5; ro_line; echo; priv_line; echo
    root_line "$(date -u -d "+1 hour" +%Y%m%d%H%M)"; echo
    ROOT_KEY=$6; root_line "$(date -u -d "-1 hour" +%Y%m%d%H%M)"; echo
    FROM=192.0.2.1 ROOT_KEY=$7; priv_line; echo
  ' _ "$script" "$s" "$(pub ro)" "$(pub priv)" "$(pub root)" "$(pub expired)" "$(pub stranger)" > "$s/authorized_keys"
  port=$((20000 + RANDOM % 20000))
  cat > "$s/sshd_config" <<EOF
Port $port
ListenAddress 127.0.0.1
HostKey $s/host
AuthorizedKeysFile $s/authorized_keys
PidFile $s/sshd.pid
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
  session_bin=$(dirname "$sshd_bin")/../lib/openssh/sshd-session
  [ -x "$session_bin" ] && echo "SshdSessionPath $session_bin" >> "$s/sshd_config"
  over_ssh() { # over_ssh <key> <command>: one connection to a fresh sshd -d, stdout only
    "$sshd_bin" -d -r -f "$s/sshd_config" > "$s/sshd.log" 2>&1 &
    local pid=$!
    for _ in $(seq 50); do grep -q "Server listening" "$s/sshd.log" && break; sleep 0.1; done
    ssh -F /dev/null -p "$port" -i "$s/$1" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$(id -un)@127.0.0.1" "$2" 2>/dev/null
    local rc=$?
    wait "$pid" 2>/dev/null
    return $rc
  }
  out=$(over_ssh ro uptime)
  check "sshd: read-only key runs its forced command [$out]" [ "$out" = "RAN uptime" ]
  out=$(over_ssh ro 'systemctl stop ssh'); rc=$?
  check "sshd: read-only key refuses a write [$rc $out]" [ $rc -eq 2 ]
  out=$(over_ssh priv 'docker ps')
  check "sshd: priv key runs the priv helper [$out]" [ "$out" = "RAN docker ps" ]
  out=$(over_ssh root 'echo hi')
  check "sshd: temporary root key works before its expiry [$out]" [ "$out" = "ROOT echo hi" ]
  over_ssh expired 'echo hi' >/dev/null; rc=$?
  check "sshd: expired temporary root key is refused [$rc]" [ $rc -eq 255 ]
  grep -q "expired" "$s/sshd.log" || bad "sshd: log does not say the key expired"
  over_ssh stranger 'docker ps' >/dev/null; rc=$?
  check "sshd: a key used from outside its from= list is refused [$rc]" [ $rc -eq 255 ]
elif [ -n "${SSHD:-}" ]; then
  bad "SSHD=$SSHD is not executable"
else
  echo "SKIP: no sshd found, set SSHD=/path/to/sshd for the real sshd checks"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
