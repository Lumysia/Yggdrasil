#!/bin/sh
# Run it with dash, bash or `busybox sh`: the scripts under test run in the same shell. Under
# BusyBox it re-runs itself with only BusyBox applets and the stubs on PATH, like on a router;
# that needs a busybox built without FEATURE_SH_STANDALONE, like Debian's.
# shellcheck disable=SC2016 # command lines are single-quoted so they reach the helper unexpanded
set -u

here=$(cd "$(dirname "$0")" && pwd)
script=$here/sakina-access
stub=$here/sakina-access-openwrt
TWO_SCRIPTS_REV=328cd73

shell_bin=$(readlink -f "/proc/$$/exe")
if [ "${shell_bin##*/}" = busybox ] && [ -z "${FARM:-}" ]; then
  applets=$(mktemp -d)
  for a in $("$shell_bin" --list); do ln -s "$shell_bin" "$applets/$a"; done
  mkdir "$applets/probe"
  printf '#!%s/sh\necho stub\n' "$applets" > "$applets/probe/uname"; chmod +x "$applets/probe/uname"
  if [ "$(PATH="$applets/probe:$applets" "$shell_bin" sh -c uname)" != stub ]; then
    rm -rf "$applets"
    echo "$shell_bin runs its applets before PATH (FEATURE_SH_STANDALONE), so the stubs can't work" >&2
    exit 1
  fi
  rm -rf "$applets/probe"
  exec env FARM="$applets" HOST_PATH="$PATH" PATH="$applets" "$shell_bin" sh "$0" "$@"
fi
HOST_PATH=${HOST_PATH:-$PATH}
FARM=${FARM:-}
if [ -n "$FARM" ]; then SH=$FARM/sh; else SH=$shell_bin; fi
real() {
  (IFS=:; for d in $HOST_PATH; do if [ -x "$d/$1" ]; then echo "$d/$1"; break; fi; done)
}
BASH_BIN=$(real bash) GIT=$(real git) SSH_BIN=$(real ssh) KEYGEN=$(real ssh-keygen) PYTHON=$(real python3)
SSHD_BIN=${SSHD:-$(real sshd)}
[ -n "$SSHD_BIN" ] || { [ -x /usr/sbin/sshd ] && SSHD_BIN=/usr/sbin/sshd; }
DB=${DROPBEAR:-$(real dropbear)}
REAL_PATH=${FARM:-$PATH}
CAT=$(command -v cat)

work=$(mktemp -d)
trap 'rm -rf "$work" ${FARM:+"$FARM"}' EXIT
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
check() {
  d=$1; shift
  if "$@"; then ok; else bad "$d"; fi
}
not() { ! "$@"; }
between() { [ -n "$1" ] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
gone() { [ -n "$1" ] && { [ ! -d "/proc/$1" ] || grep -q '^State:.*Z' "/proc/$1/status"; }; }
has() { grep -qF -- "$2" "$1"; }

nl='
'
DEFAULTS=$(sed -n 's/^DEFAULT_FROM=//p' "$script")
ro_blob=$(sed -n "s/^RO_KEY='ssh-ed25519 \(.*\)'$/\1/p" "$script")
priv_blob=$(sed -n "s/^PRIV_KEY='ssh-ed25519 \(.*\)'$/\1/p" "$script")
root_blob=$(sed -n "s/^ROOT_KEY='ssh-ed25519 \(.*\)'$/\1/p" "$script")
other_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOther admin@laptop'

hstub=$work/helper-bin
mkdir -p "$hstub" "$work/run"
calls=$work/calls
for c in journalctl systemctl cat head tail ls wc stat zcat grep zgrep du ip df free uptime lsblk ps ss \
  findmnt last who sensors pveversion nixos-version uname apt hostname smartctl nvme zpool zfs qm pct \
  pvesm pvesh dmesg ha-manager pvecm docker sudo logread ifstatus iwinfo apk netstat top wg tailscale; do
  printf '#!%s\necho "RAN %s${*:+ $*}"\n' "$SH" "$c" > "$hstub/$c"
done
for c in ubus uci; do
  printf '#!%s\nif [ -n "${STUB_OUT:-}" ]; then %s "$STUB_OUT"; else echo "RAN %s${*:+ $*}"; fi\n' "$SH" "$CAT" "$c" > "$hstub/$c"
done
# The root session's expiry check needs the real date.
printf '#!%s\nif [ $# -eq 0 ]; then echo "RAN date"; else PATH=%s exec date "$@"; fi\n' "$SH" "$REAL_PATH" > "$hstub/date"
printf '#!%s\n' "$SH" > "$hstub/logger"
printf '#!%s\necho "${STUB_UID:-1000}"\n' "$SH" > "$hstub/id"
chmod +x "$hstub"/*

show_helper() {
  SAKINA_ACCESS_ROOT=$1 "$SH" "$script" show | awk '/^===== / { n++; next } n == 1'
}
mkdir -p "$work/lx-root" "$work/ow-root/etc"
touch "$work/ow-root/etc/openwrt_release"
show_helper "$work/lx-root" > "$work/helper-linux.orig"
show_helper "$work/ow-root" > "$work/helper-openwrt.orig"
from_file=$work/from
sudo_rule=$work/sudo-rule
helper_on_stubs() {
  sed -e "s|^export PATH=[^ ]*|export PATH=$hstub:$REAL_PATH|" -e "s|^FROM_FILE=.*|FROM_FILE=$from_file|" \
    -e "s|^RUN_DIR=.*|RUN_DIR=$work/run|" -e "s|^ROOT_SHELL=.*|ROOT_SHELL=$SH|" -e "s|^SUDO_RULE=.*|SUDO_RULE=$sudo_rule|" "$1"
}
mkdir -p "$work/h"
helper_on_stubs "$work/helper-linux.orig" > "$work/h/sakina-ro"
cp "$work/h/sakina-ro" "$work/h/sakina-ro-priv"
helper_on_stubs "$work/helper-openwrt.orig" > "$work/h/sakina-ssh"

client='192.0.2.10 40000 22'
run_ssh() {
  hp=$1 l=$2; shift 2
  (cd "$work" && SSH_CLIENT=$client SSH_ORIGINAL_COMMAND=$l "$SH" "$work/h/$hp" "$@" 2>&1)
}
allow() {
  out=$(run_ssh "$1" "$2"); rc=$?
  if [ $rc -eq 0 ] && [ "$out" = "$3" ]; then ok; else bad "$1 should run [$2] as [$3], got rc=$rc [$out]"; fi
}
deny() {
  out=$(run_ssh "$1" "$2"); rc=$?
  case $out in *RAN*) rc=99 ;; esac
  if [ $rc -eq 2 ]; then ok; else bad "$1 should refuse [$2], got rc=$rc [$out]"; fi
}

export STUB_UID=1000
H=sakina-ro
allow $H 'journalctl -u ssh -n 20' 'RAN journalctl --no-pager -u ssh -n 20'
allow $H 'journalctl -u "$(id)"' 'RAN journalctl --no-pager -u $(id)'
allow $H 'journalctl -u x;id' 'RAN journalctl --no-pager -u x;id'
deny  $H 'journalctl --vacuum-size=1M'
deny  $H 'journalctl --vacuum-time 1d'
deny  $H 'journalctl --rotate'
deny  $H 'journalctl --flush'
deny  $H 'journalctl --pager-end'
allow $H 'systemctl status nginx' 'RAN systemctl --no-pager status nginx'
allow $H 'systemctl' 'RAN systemctl --no-pager'
allow $H 'systemctl --failed list-units' 'RAN systemctl --no-pager --failed list-units'
deny  $H 'systemctl stop nginx'
deny  $H 'systemctl --no-block restart nginx'
deny  $H 'systemctl -H otherhost status'
deny  $H 'systemctl --machine=x status'
allow $H 'cat /var/log/syslog' 'RAN cat /var/log/syslog'
allow $H 'tail -n 50 /var/log/syslog' 'RAN tail -n 50 /var/log/syslog'
allow $H 'tail -n +5 /var/log/syslog' 'RAN tail -n +5 /var/log/syslog'
allow $H 'cat /etc/pve/qemu-server/100.conf' 'RAN cat /etc/pve/qemu-server/100.conf'
allow $H 'ls -la -- /proc/1' 'RAN ls -la -- /proc/1'
deny  $H 'cat /etc/shadow'
deny  $H 'cat /var/log/../../etc/shadow'
deny  $H 'cat /var/log/../etc/shadow'
deny  $H 'cat /var/log/missing/../../../etc/shadow'
deny  $H 'cat var/log/syslog'
deny  $H 'cat /etc/pve/priv/authkey.key'
deny  $H 'cat /etc/pve/priv'
deny  $H 'cat /etc/pve/local/pve-ssl.key'
deny  $H 'cat /var/log/syslog; id'
deny  $H 'cat /var/log/syslog && id'
deny  $H 'cat $(id)'
deny  $H 'cat `id`'
deny  $H 'head -- -n /etc/shadow'
deny  $H 'wc --files0-from=/etc/shadow'
deny  $H 'du --exclude-from=/etc/shadow /var/log'
allow $H 'grep -i error /var/log/syslog' 'RAN grep -i error /var/log/syslog'
allow $H 'grep -C 3 /etc/shadow /var/log/syslog' 'RAN grep -C 3 /etc/shadow /var/log/syslog'
allow $H 'grep -e root /var/log/auth.log' 'RAN grep -e root /var/log/auth.log'
deny  $H 'grep root /etc/shadow'
deny  $H 'grep -e root /etc/shadow'
deny  $H 'grep -f /etc/shadow /var/log/syslog'
deny  $H 'grep --file=/etc/shadow /var/log/syslog'
deny  $H 'grep -f/etc/shadow /var/log/syslog'
deny  $H 'grep -if /etc/shadow /var/log/syslog'
deny  $H 'grep -r x /proc/1'
allow $H 'ip -br addr' 'RAN ip -br addr'
deny  $H 'ip netns exec x sh'
deny  $H 'ip -batch /tmp/x'
allow $H 'apt list --upgradable' 'RAN apt list --upgradable'
allow $H 'apt policy openssh-server' 'RAN apt policy openssh-server'
deny  $H 'apt install curl'
deny  $H 'apt-get install curl'
allow $H 'lsblk -f' 'RAN lsblk -f'
allow $H 'date' 'RAN date'
deny  $H 'date -s 2020-01-01'
deny  $H 'hostname evil'
deny  $H 'bash'
deny  $H 'sh -c id'
deny  $H 'rm -rf /'
deny  $H 'sudo -n /usr/local/sbin/sakina-ro-priv docker ps'
deny  $H 'docker ps'
touch "$sudo_rule"
allow $H 'docker ps -a' 'RAN sudo -n /usr/local/sbin/sakina-ro-priv docker ps -a'
rm -f "$sudo_rule"

export STUB_UID=0
H=sakina-ro-priv
allow $H 'docker ps -a' 'RAN docker ps -a'
allow $H 'docker logs --tail 20 web' 'RAN docker logs --tail 20 web'
allow $H 'docker logs "$(id)"' 'RAN docker logs $(id)'
allow $H 'docker stats' 'RAN docker stats --no-stream'
allow $H 'docker system df' 'RAN docker system df'
allow $H 'docker compose ls' 'RAN docker compose ls'
deny  $H 'docker exec web sh'
deny  $H 'docker run --rm alpine'
deny  $H 'docker inspect web'
deny  $H 'docker system prune -af'
deny  $H 'docker image prune'
deny  $H 'docker compose up -d'
deny  $H 'docker ps -H tcp://192.0.2.1:2375'
deny  $H 'docker logs --host=tcp://192.0.2.1 web'
deny  $H 'docker ps --context other'
deny  $H 'docker ps; id'
allow $H 'smartctl --scan' 'RAN smartctl --scan'
allow $H 'smartctl -a /dev/sda' 'RAN smartctl -a /dev/sda'
allow $H 'smartctl -l selftest -d nvme /dev/nvme0n1' 'RAN smartctl -l selftest -d nvme /dev/nvme0n1'
allow $H 'smartctl -x /dev/disk/by-id/ata-X_Y-1' 'RAN smartctl -x /dev/disk/by-id/ata-X_Y-1'
deny  $H 'smartctl -t long /dev/sda'
deny  $H 'smartctl -a /etc/shadow'
deny  $H 'smartctl -a /dev/sda /dev/sdb'
deny  $H 'smartctl -a /dev/disk/by-id/../../sda'
allow $H 'nvme smart-log /dev/nvme0' 'RAN nvme smart-log /dev/nvme0'
deny  $H 'nvme format /dev/nvme0'
deny  $H 'nvme smart-log /dev/nvme0nn1'
allow $H 'zpool status -v tank' 'RAN zpool status -v tank'
allow $H 'zpool events -v' 'RAN zpool events -v'
deny  $H 'zpool scrub tank'
deny  $H 'zpool events -c'
deny  $H 'zpool events -vc'
deny  $H 'zpool events -f'
deny  $H 'zpool iostat 5'
deny  $H 'zpool status tank 1'
deny  $H 'zpool status --long'
allow $H 'zfs list -o name,used' 'RAN zfs list -o name,used'
deny  $H 'zfs destroy tank/x'
deny  $H 'zfs set compression=off tank'
allow $H 'qm list' 'RAN qm list'
allow $H 'qm config 100' 'RAN qm config 100'
allow $H 'pct status 101 --verbose' 'RAN pct status 101 --verbose'
deny  $H 'qm stop 100'
deny  $H 'qm guest exec 100 id'
deny  $H 'pct exec 101 id'
deny  $H 'qm config 100;id'
allow $H 'pvesm status' 'RAN pvesm status'
deny  $H 'pvesm free local:100/x.qcow2'
allow $H 'pvesh get /nodes --output-format json' 'RAN pvesh get /nodes --output-format json'
deny  $H 'pvesh set /nodes/x/config'
deny  $H 'pvesh create /nodes/x/qemu'
deny  $H 'pvesh delete /nodes/x/qemu/100'
deny  $H 'pvesh get nodes'
deny  $H 'pvesh get /nodes;id'
deny  $H 'pvesh get /nodes $(id)'
allow $H 'dmesg -T -l err,warn' 'RAN dmesg --nopager -T -l err,warn'
deny  $H 'dmesg -H'
deny  $H 'dmesg -c'
deny  $H 'dmesg -C'
deny  $H 'dmesg -l "err;id"'
allow $H 'ha-manager status' 'RAN ha-manager status'
deny  $H 'ha-manager set vm:100 --state stopped'
deny  $H 'pvecm expected 1'
deny  $H 'cat /etc/shadow'
deny  $H 'journalctl -n 5'
deny  $H 'bash'
deny  $H ''
out=$("$SH" "$work/h/sakina-ro-priv" docker ps 2>&1)
check "the priv helper takes its command as arguments (the sudo route)" [ "$out" = "RAN docker ps" ]
out=$("$SH" "$work/h/sakina-ro-priv" docker exec web sh 2>&1); rc=$?
check "and refuses through the sudo route too" [ $rc -eq 2 ]
out=$(cd "$work" && SSH_ORIGINAL_COMMAND='echo hi' "$SH" "$work/h/sakina-ro-priv" root 209901010000 2>&1); rc=$?
check "arguments never start a root session outside OpenWrt [$rc $out]" [ $rc -eq 2 ]
cp "$work/h/sakina-ro" "$work/h/sakina-root-session"
out=$(run_ssh sakina-root-session 'echo "hi $((1+1))"'); rc=$?
check "the root session helper runs the command [$rc $out]" eval '[ $rc -eq 0 ] && [ "$out" = "hi 2" ]'
check "and clears its record when it ends" [ -z "$(ls "$work/run")" ]

export STUB_UID=1000
H=sakina-ssh
echo '192.0.2.0/24,2001:db8::/32' > "$from_file"
allow $H 'ubus call system board' 'RAN ubus call system board'
allow $H 'ubus call network.interface.wan status' 'RAN ubus call network.interface.wan status'
allow $H 'ubus call network.interface dump' 'RAN ubus call network.interface dump'
allow $H 'ubus -t 5 call hostapd.phy0-ap0 get_clients' 'RAN ubus -t 5 call hostapd.phy0-ap0 get_clients'
allow $H 'ubus call iwinfo assoclist '\''{"device":"phy0-ap0"}'\' 'RAN ubus call iwinfo assoclist {"device":"phy0-ap0"}'
allow $H 'ubus call luci-rpc getDHCPLeases' 'RAN ubus call luci-rpc getDHCPLeases'
allow $H 'ubus -v list network.*' 'RAN ubus -v list network.*'
deny  $H 'ubus call network.interface.wan down'
deny  $H 'ubus call network.interface.wan up'
deny  $H 'ubus call network reload'
deny  $H 'ubus call system reboot'
deny  $H 'ubus call system sysupgrade'
deny  $H 'ubus call uci set {}'
deny  $H 'ubus call uci commit {}'
deny  $H 'ubus call file exec {}'
deny  $H 'ubus call luci setPassword {}'
deny  $H 'ubus call network.wireless status'
deny  $H 'ubus call hostapd.phy0-ap0 del_client {}'
deny  $H 'ubus call "network.interface.wan;id" status'
deny  $H 'ubus -s /tmp/other.sock call system board'
deny  $H 'ubus -S call system board'
deny  $H 'ubus send foo {}'
deny  $H 'ubus monitor'
deny  $H 'ubus call system'
allow $H 'logread -l 50 -e dropbear' 'RAN logread -l 50 -e dropbear'
allow $H 'logread -e "auth fail"' 'RAN logread -e auth fail'
deny  $H 'logread -F /tmp/x'
deny  $H 'logread -p /tmp/pid'
deny  $H 'logread -r 192.0.2.1 514'
deny  $H 'logread -s /tmp/other.sock'
allow $H 'ifstatus wan' 'RAN ifstatus wan'
deny  $H 'ifstatus "wan;id"'
deny  $H 'ifstatus wan lan'
allow $H 'uci show wireless' 'RAN uci show wireless'
allow $H 'uci -X show' 'RAN uci -X show'
deny  $H 'uci set wireless.radio0.disabled=1'
deny  $H 'uci commit'
deny  $H 'uci delete network.wan'
deny  $H 'uci get wireless.default_radio0.key'
deny  $H 'uci export wireless'
deny  $H 'uci -c /tmp show'
deny  $H 'uci -P /tmp show'
deny  $H 'uci show "x;id"'
allow $H 'apk list --upgradable' 'RAN apk list --upgradable'
allow $H 'apk info -L dropbear' 'RAN apk info -L dropbear'
deny  $H 'apk add tcpdump'
deny  $H 'apk del dropbear'
deny  $H 'apk update'
deny  $H 'apk upgrade'
deny  $H 'apk list -U'
deny  $H 'apk --root /tmp list'
deny  $H 'apk list --allow-untrusted'
allow $H 'iwinfo' 'RAN iwinfo'
allow $H 'iwinfo phy0-ap0 assoclist' 'RAN iwinfo phy0-ap0 assoclist'
deny  $H 'iwinfo phy0-ap0 scan'
allow $H 'ip -br addr' 'RAN ip -br addr'
allow $H 'ip -6 route show table all' 'RAN ip -6 route show table all'
allow $H 'ip route get 192.0.2.1' 'RAN ip route get 192.0.2.1'
allow $H 'ip neigh' 'RAN ip neigh'
deny  $H 'ip link set eth0 down'
deny  $H 'ip addr add 192.0.2.1/24 dev eth0'
deny  $H 'ip route flush all'
deny  $H 'ip netns exec x sh'
deny  $H 'ip -batch /tmp/x'
deny  $H 'ip -n other addr'
allow $H 'ss -tlnp' 'RAN ss -tlnp'
allow $H 'ss -tn state established' 'RAN ss -tn state established'
deny  $H 'ss -K dst 192.0.2.1'
deny  $H 'ss -tnK'
deny  $H 'ss -F /tmp/filter'
deny  $H 'ss --kill'
allow $H 'netstat -tln' 'RAN netstat -tln'
allow $H 'df -h' 'RAN df -h'
allow $H 'free' 'RAN free'
allow $H 'uptime' 'RAN uptime'
allow $H 'uname -a' 'RAN uname -a'
allow $H 'top -bn1' 'RAN top -b -n 1'
allow $H 'top -b -n 1' 'RAN top -b -n 1'
allow $H 'top' 'RAN top -b -n 1'
deny  $H 'top -d 1'
allow $H 'date' 'RAN date'
deny  $H 'date -s 2020-01-01'
deny  $H 'hostname evil'
allow $H 'cat /proc/meminfo' 'RAN cat /proc/meminfo'
allow $H 'tail -n 20 /tmp/dhcp.leases' 'RAN tail -n 20 /tmp/dhcp.leases'
allow $H 'ls -la /sys/class' 'RAN ls -la /sys/class'
allow $H 'grep -i error /proc/meminfo' 'RAN grep -i error /proc/meminfo'
allow $H 'grep -C 3 /etc/shadow /proc/meminfo' 'RAN grep -C 3 /etc/shadow /proc/meminfo'
deny  $H 'cat /etc/shadow'
deny  $H 'cat /etc/config/wireless'
deny  $H 'cat /proc/../etc/shadow'
deny  $H 'cat /proc/self/root/etc/shadow'
deny  $H 'cat /proc/self/cwd/sakina-ssh'
deny  $H 'cat /proc/1/environ'
deny  $H 'cat /proc/self/mem'
deny  $H 'cat proc/meminfo'
deny  $H 'cat /var/log/../../etc/pve/x'
deny  $H 'cat /proc/meminfo; id'
deny  $H 'cat /proc/meminfo && reboot'
deny  $H 'cat $(id)'
deny  $H 'cat `id`'
deny  $H 'head -- -n /etc/shadow'
deny  $H 'grep root /etc/shadow'
deny  $H 'grep -e root /etc/shadow'
deny  $H 'grep -f /etc/shadow /proc/meminfo'
deny  $H 'grep -f/etc/shadow /proc/meminfo'
deny  $H 'grep --file=/etc/shadow /proc/meminfo'
deny  $H 'grep -rf /etc/config/wireless /proc/meminfo'
deny  $H 'grep -R key /proc/self/root/etc'
deny  $H 'grep -d recurse key /proc/self/root/etc'
allow $H 'grep -eroot /proc/meminfo' 'RAN grep -eroot /proc/meminfo'
allow $H 'grep -in -A 2 error /proc/meminfo' 'RAN grep -in -A 2 error /proc/meminfo'
deny  $H 'wc --files0-from=/etc/shadow'
deny  $H 'wg show'
deny  $H 'tailscale status'
deny  $H 'dmesg'
deny  $H 'journalctl --vacuum-size=1M'
deny  $H 'reboot'
deny  $H 'poweroff'
deny  $H 'sh'
deny  $H 'ash -c id'
deny  $H '/bin/sh -c id'
deny  $H 'rm -rf /'
deny  $H 'sysupgrade -n /tmp/x.bin'
deny  $H 'opkg install x'
deny  $H 'echo hi > /etc/passwd'
deny  $H 'logread -e "unterminated'
deny  $H "uptime${nl}reboot"
out=$(run_ssh $H ''); rc=$?
check "an empty command prints the usage [$rc]" [ $rc -eq 1 ]
out=$(run_ssh $H 'help'); rc=$?
check "help lists the ubus read methods" [ $rc -eq 0 ]
case $out in *"network.interface.* status"*) ok ;; *) bad "help lacks the ubus list" ;; esac

export STUB_UID=0
allow $H 'wg show' 'RAN wg show'
allow $H 'wg show wg0 latest-handshakes' 'RAN wg show wg0 latest-handshakes'
deny  $H 'wg show wg0 private-key'
deny  $H 'wg show wg0 preshared-keys'
deny  $H 'wg show all dump'
deny  $H 'wg showconf wg0'
deny  $H 'wg set wg0 peer x remove'
allow $H 'tailscale status --json' 'RAN tailscale status --json'
allow $H 'tailscale ip -4' 'RAN tailscale ip -4'
deny  $H 'tailscale up'
deny  $H 'tailscale status --web'
deny  $H 'tailscale logout'
allow $H 'dmesg' 'RAN dmesg'
deny  $H 'dmesg -c'
deny  $H 'dmesg -n 1'
allow $H 'uci show network' 'RAN uci show network'
allow $H 'ubus call system info' 'RAN ubus call system info'
deny  $H 'ubus call system reboot'
deny  $H 'cat /proc/meminfo'
deny  $H 'grep x /proc/meminfo'
deny  $H 'apk add x'
export STUB_UID=1000

cat > "$work/uci.out" <<'EOF'
wireless.default_radio0=wifi-iface
wireless.default_radio0.ssid='Home'
wireless.default_radio0.key='hunter2'
wireless.default_radio0.encryption='psk2'
wireless.default_radio0.key1='s:wep'
wireless.default_radio0.sae_password='sae'
network.wg0.private_key='PRIVATE='
network.peer1.public_key='PUBLIC='
network.peer1.preshared_key='PSK='
network.wan.password='line1
network.fake.ssid=leaked'
network.wan.username='me'
network.wan.list_token='a' 'b'
ddns.x.lookup_host='a.b'
system.@system[0].hostname='OpenWrt'
acme.x.api_key='it'\''s'
network.lan.ipaddr='192.0.2.1'
EOF
out=$(STUB_OUT=$work/uci.out run_ssh $H 'uci show')
expected="wireless.default_radio0=wifi-iface
wireless.default_radio0.ssid='Home'
wireless.default_radio0.key='***'
wireless.default_radio0.encryption='psk2'
wireless.default_radio0.key1='***'
wireless.default_radio0.sae_password='***'
network.wg0.private_key='***'
network.peer1.public_key='PUBLIC='
network.peer1.preshared_key='***'
network.wan.password='***'
network.wan.username='me'
network.wan.list_token='***'
ddns.x.lookup_host='a.b'
system.@system[0].hostname='OpenWrt'
acme.x.api_key='***'
network.lan.ipaddr='192.0.2.1'"
check "uci show masks secrets, multi-line values included" [ "$out" = "$expected" ]
[ "$out" = "$expected" ] || printf '%s\n' "$out"

cat > "$work/ubus.out" <<'EOF'
{
	"up": true,
	"config": {
		"key": "hunter2",
		"ssid": "Home",
		"sae_password": [
			"a",
			"b"
		],
		"auth_secret": {
			"x": [
				1
			]
		},
		"public_key": "PUB"
	},
	"token": "t"
}
EOF
out=$(STUB_OUT=$work/ubus.out run_ssh $H 'ubus call system board')
expected='{
	"up": true,
	"config": {
		"key": "***",
		"ssid": "Home",
		"sae_password": "***",
		"auth_secret": "***",
		"public_key": "PUB"
	},
	"token": "***"
}'
check "ubus replies are masked" [ "$out" = "$expected" ]
[ "$out" = "$expected" ] || printf '%s\n' "$out"
if [ -n "$PYTHON" ]; then
  printf '%s\n' "$out" | "$PYTHON" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
  check "the masked reply is still JSON" [ $? -eq 0 ]
fi

from_case() {
  echo "$1" > "$from_file"
  out=$(client="$2 40000 22" run_ssh $H uptime); rc=$?
  if [ "$3" = yes ]; then got=$([ $rc -eq 0 ] && echo yes || echo no); else got=$([ $rc -eq 2 ] && echo no || echo yes); fi
  if [ "$got" = "$3" ]; then ok; else bad "from [$1] client [$2]: want $3, got rc=$rc [$out]"; fi
}
from_case '192.0.2.0/24' 192.0.2.10 yes
from_case '192.0.2.0/24' 192.0.3.10 no
from_case '192.0.2.0/25' 192.0.2.200 no
from_case '198.51.100.0/22' 198.51.103.255 yes
from_case '198.51.100.0/22' 198.51.104.0 no
from_case '0.0.0.0/0' 203.0.113.9 yes
from_case '192.0.2.10' 192.0.2.10 yes
from_case '192.0.2.10' 192.0.2.100 no
from_case '192.0.2.*' 192.0.2.77 yes
from_case '192.0.2.?' 192.0.2.77 no
from_case '192.0.2.?' 192.0.2.7 yes
from_case '!192.0.2.7,192.0.2.0/24' 192.0.2.7 no
from_case '!192.0.2.7,192.0.2.0/24' 192.0.2.8 yes
from_case '192.0.2.0/24' ::ffff:192.0.2.10 yes
from_case '2001:db8::/32' 2001:db8:0:1::5 yes
from_case '2001:db8::/32' 2001:db9::1 no
from_case '2001:db8:a::/48' 2001:db8:a:ffff::1 yes
from_case '2001:db8:a::/48' 2001:db8:b::1 no
from_case '2001:db8::1' 2001:0db8:0000:0000:0000:0000:0000:0001 yes
from_case '2001:DB8::1' 2001:db8::1 yes
from_case 'fe80::/10' fe80::1%br-lan yes
from_case '2001:db8::/32' 192.0.2.10 no
from_case '192.0.2.0/24' 2001:db8::1 no
from_case '192.0.2.0/33' 192.0.2.10 no
from_case '192.0.2.0/24' 'not-an-ip' no
from_case '' 192.0.2.10 no
for a in 10.1.2.3 172.16.0.1 172.31.255.254 192.168.1.20 100.64.0.1 100.127.255.254 fd7a:115c:a1e0::1 fd7a:115c:a1e0:ab12::5; do
  from_case "$DEFAULTS" "$a" yes
done
for a in 8.8.8.8 172.32.0.1 192.169.0.1 100.128.0.1 127.0.0.1 fd7a:115c:a1e1::1 2001:db8::1; do
  from_case "$DEFAULTS" "$a" no
done
echo '192.0.2.0/24' > "$from_file"
out=$(cd "$work" && SSH_CLIENT='' SSH_ORIGINAL_COMMAND=uptime "$SH" "$work/h/sakina-ssh" 2>&1); rc=$?
check "no SSH_CLIENT is refused [$rc]" [ $rc -eq 2 ]
mv "$from_file" "$from_file.x"
out=$(run_ssh $H uptime); rc=$?
check "a missing from list refuses everything [$rc]" [ $rc -eq 2 ]
mv "$from_file.x" "$from_file"

future=$(date -u -d "@$(( $(date +%s) + 3600 ))" +%Y%m%d%H%M)
past=$(date -u -d "@$(( $(date +%s) - 60 ))" +%Y%m%d%H%M)
export STUB_UID=0
out=$(run_ssh $H 'echo "hi $((1+1))"' root "$future"); rc=$?
check "root session runs the command before expiry [$rc $out]" eval '[ $rc -eq 0 ] && [ "$out" = "hi 2" ]'
check "root session record is cleared when it ends" [ -z "$(ls "$work/run")" ]
out=$(run_ssh $H 'echo hi' root "$past"); rc=$?
check "root session after expiry is refused [$rc $out]" eval '[ $rc -eq 2 ] && [ "${out#*hi}" = "$out" ]'
out=$(run_ssh $H 'echo hi' root 2026); rc=$?
check "root session with a bad stamp is refused [$rc]" [ $rc -eq 2 ]
out=$(client='203.0.113.1 4000 22' run_ssh $H 'echo hi' root "$future"); rc=$?
check "root session from outside the list is refused [$rc]" [ $rc -eq 2 ]
export STUB_UID=1000
out=$(run_ssh $H 'echo hi' root "$future"); rc=$?
check "root session as a normal user is refused [$rc]" [ $rc -eq 2 ]

mstub=$work/main-bin
mkdir -p "$mstub"
printf '#!%s\n[ "$1" = -u ] && echo 0\n' "$SH" > "$mstub/id"
for c in logger killall systemctl systemd-run visudo chown passwd usermod userdel; do
  printf '#!%s\necho "%s $*" >> "%s"\n' "$SH" "$c" "$calls" > "$mstub/$c"
done
cat > "$mstub/useradd" <<EOF
#!$SH
echo "useradd \$*" >> "$calls"
echo "sakina:x:59001:59001:Sakina (read-only):/home/sakina:/bin/bash" >> "\$SAKINA_ACCESS_ROOT/etc/passwd"
mkdir -p "\$SAKINA_ACCESS_ROOT/home/sakina"
EOF
cat > "$mstub/sshd" <<EOF
#!$SH
[ "\$1" = -T ] && echo "permitrootlogin \${STUB_PERMIT_ROOT:-prohibit-password}"
EOF
cat > "$mstub/uci" <<EOF
#!$SH
echo "dropbear.main=dropbear"
echo "dropbear.main.RootLogin='\${STUB_ROOTLOGIN:-1}'"
EOF
cat > "$mstub/curl" <<EOF
#!$SH
while [ \$# -gt 0 ]; do case \$1 in -o) out=\$2; shift ;; https://*) url=\$1 ;; esac; shift; done
if [ -n "\${STUB_DOWNLOAD:-}" ]; then src=\$STUB_DOWNLOAD
else src=\${STUB_REPO:-/nonexistent}/\${url##*/}; fi
[ -f "\$src" ] || exit 22
cp "\$src" "\$out"
EOF
chmod +x "$mstub"/*
ln -s "$SH" "$mstub/sh"
mkdir -p "$work/repo"
cp "$script" "$stub" "$work/repo/"

host_tree() {
  rm -rf "$1"; : > "$calls"
  mkdir -p "$1/etc" "$1/home" "$1/usr/sbin" "$1/var/run"
  printf 'root:x:0:0:root:/root:/bin/sh\nold:x:59000:59000::/home/old:/bin/sh\n' > "$1/etc/passwd"
  printf 'root:x:0:\nadm:x:4:\nold:x:59000:\n' > "$1/etc/group"
  printf 'root:$1$x$y:20000:0:99999:7:::\n' > "$1/etc/shadow"
}
fresh_linux() { # root's key file is a symlink, like on Proxmox
  h=$work/host
  host_tree "$h"
  mkdir -p "$h/root/.ssh" "$h/etc/pve/priv" "$h/usr/local/sbin" "$h/etc/systemd/system" "$h/etc/sudoers.d"
  printf '%s' "$other_key" > "$h/etc/pve/priv/authorized_keys"
  ln -s "$h/etc/pve/priv/authorized_keys" "$h/root/.ssh/authorized_keys"
  printf '@includedir /etc/sudoers.d\n' > "$h/etc/sudoers"
  keyfile=$h/etc/pve/priv/authorized_keys
  self=$h/usr/local/sbin/sakina-access
}
fresh_router() {
  h=$work/host
  host_tree "$h"
  mkdir -p "$h/etc/dropbear" "$h/etc/crontabs" "$h/etc/init.d" "$h/usr/share/acl.d"
  touch "$h/etc/openwrt_release"
  echo /bin/ash > "$h/etc/shells"
  printf '%s\n' "$other_key" > "$h/etc/dropbear/authorized_keys"
  chmod 600 "$h/etc/dropbear/authorized_keys"
  printf '## This file contains files and directories that should\n/etc/mything.conf' > "$h/etc/sysupgrade.conf"
  printf '#!%s\necho "cron $*" >> "%s"\n' "$SH" "$calls" > "$h/etc/init.d/cron"
  chmod +x "$h/etc/init.d/cron"
  keyfile=$h/etc/dropbear/authorized_keys
  self=$h/usr/sbin/sakina-access
}
stage() { cp "$script" "$h/sakina-access"; }
sa() {
  SAKINA_ACCESS_ROOT=$h STUB_REPO=$work/repo PATH="$mstub:$REAL_PATH" "$SH" "$h/sakina-access" "$@"
}
upd() { SAKINA_ACCESS_ROOT=$h STUB_REPO=$work/repo PATH="$mstub:$REAL_PATH" "$SH" "${1:-$h/sakina-access}" update; }
keys() { cat "$keyfile"; }
count() { grep -c -F -- "$1" "$keyfile"; }
still_link() { [ -L "$h/root/.ssh/authorized_keys" ]; }
from_now() { cat "$h/etc/sakina-access/from"; }
stamp_in() { date -u -d "@$(( $(date +%s) + $1 ))" +%Y%m%d%H%M; }

fresh_linux; stage
out=$(sa install --from "192.0.2.1, 198.51.100.0/24
2001:db8::/32" 2>&1); rc=$?
check "linux: install succeeds [$rc: $out]" [ $rc -eq 0 ]
check "linux: the list is normalized and saved" [ "$(from_now)" = "192.0.2.1,198.51.100.0/24,2001:db8::/32" ]
sa install >/dev/null 2>&1
check "linux: later runs read the saved list, single addresses included" [ "$(from_now)" = "192.0.2.1,198.51.100.0/24,2001:db8::/32" ]
fresh_linux; stage
sa install >/dev/null 2>&1
check "linux: install without a list uses the default ranges" [ "$(from_now)" = "$DEFAULTS" ]
check "linux: the key lines carry the default ranges" has "$keyfile" "restrict,from=\"$DEFAULTS\",command="
fresh_linux; stage
sa install --from '192.0.2.1",command="/bin/sh' >/dev/null 2>&1
check "linux: a list that could break out of from=\"...\" is refused" [ $? -ne 0 ]
check "linux: and writes no list" [ ! -e "$h/etc/sakina-access/from" ]

fresh_linux; stage
mkdir -p "$h/etc/sakina-access"
echo 192.0.2.7,198.51.100.9 > "$h/etc/sakina-access/from"
sa install >/dev/null 2>&1
check "linux: an older version's single-address list gives way to the defaults" [ "$(from_now)" = "$DEFAULTS" ]
check "linux: and that is logged" grep -q "^logger -t sakina-access from list 192.0.2.7,198.51.100.9 replaced by the default ranges" "$calls"
sa install --from 192.0.2.5 >/dev/null 2>&1
sa install >/dev/null 2>&1
check "linux: a single address chosen with --from stays" [ "$(from_now)" = 192.0.2.5 ]
fresh_linux; stage
mkdir -p "$h/etc/sakina-access"
echo 192.0.2.7,198.51.100.0/24 > "$h/etc/sakina-access/from"
sa install >/dev/null 2>&1
check "linux: an older version's list with a range stays" [ "$(from_now)" = 192.0.2.7,198.51.100.0/24 ]
fresh_linux; stage
mkdir -p "$h/home/sakina/.ssh"
printf 'restrict,from="192.0.2.7,198.51.100.0/24",command="/usr/local/sbin/sakina-ro" ssh-ed25519 %s sakina-cat-readonly\n' "$ro_blob" > "$h/home/sakina/.ssh/authorized_keys"
sa install >/dev/null 2>&1
check "linux: the list is taken over from an old read-only key line" [ "$(from_now)" = "192.0.2.7,198.51.100.0/24" ]
check "linux: and that line is rewritten" [ "$(cat "$h/home/sakina/.ssh/authorized_keys")" = "restrict,from=\"192.0.2.7,198.51.100.0/24\",command=\"/usr/local/sbin/sakina-ro\" ssh-ed25519 $ro_blob sakina-readonly" ]
fresh_linux; stage
printf '%s\nrestrict,from="192.0.2.0/28",command="/usr/local/sbin/sakina-ro-priv" ssh-ed25519 %s sakina-cat-priv\n' "$other_key" "$priv_blob" > "$keyfile"
sa install >/dev/null 2>&1
check "linux: the list is taken over from an old priv line in root's keys" [ "$(from_now)" = "192.0.2.0/28" ]
fresh_linux; stage
printf '%s\nrestrict,from="192.0.2.8",command="/usr/local/sbin/sakina-ro-priv" ssh-ed25519 %s sakina-cat-priv\n' "$other_key" "$priv_blob" > "$keyfile"
sa install >/dev/null 2>&1
check "linux: a single address taken over from a key line gives way to the defaults" [ "$(from_now)" = "$DEFAULTS" ]

fresh_linux; stage
live=$(stamp_in 7200)
printf '%s\nrestrict,from="192.0.2.8",command="/usr/local/sbin/sakina-ro-priv" ssh-ed25519 %s sakina-cat-priv\nfrom="192.0.2.8",expiry-time="%sZ",command="/usr/local/sbin/sakina-root-session" ssh-ed25519 %s sakina-cat-root-temp' \
  "$other_key" "$priv_blob" "$live" "$root_blob" > "$keyfile"
out=$(sa install --from 192.0.2.9 2>&1); rc=$?
check "linux: install succeeds [$rc: $out]" [ $rc -eq 0 ]
check "linux: user added" grep -q '^useradd --system --create-home --home-dir /home/sakina ' "$calls"
check "linux: no password" grep -q '^passwd -l sakina' "$calls"
check "linux: in the log groups that exist" grep -qx 'usermod -aG adm sakina' "$calls"
check "linux: read-only key line" [ "$(cat "$h/home/sakina/.ssh/authorized_keys")" = "restrict,from=\"192.0.2.9\",command=\"/usr/local/sbin/sakina-ro\" ssh-ed25519 $ro_blob sakina-readonly" ]
check "linux: root owns the read-only key directory" grep -q "^chown 0:0 $h/home/sakina/.ssh" "$calls"
for p in sakina-ro sakina-ro-priv sakina-root-session; do
  check "linux: $p installed and executable" [ -x "$h/usr/local/sbin/$p" ]
  check "linux: $p is the shown helper" cmp -s "$h/usr/local/sbin/$p" "$work/helper-linux.orig"
done
check "linux: old priv line is replaced" [ "$(count sakina-cat-priv)" -eq 0 ]
check "linux: exactly one new priv line" [ "$(count "restrict,from=\"192.0.2.9\",command=\"/usr/local/sbin/sakina-ro-priv\" ssh-ed25519 $priv_blob sakina-access-priv")" -eq 1 ]
check "linux: other keys are kept" [ "$(count "$other_key")" -eq 1 ]
check "linux: the old live grant is kept in the current form" eval '[ "$(count sakina-cat-root-temp)" -eq 0 ] && [ "$(count "from=\"192.0.2.9\",expiry-time=\"${live}Z\"")" -eq 1 ]'
check "linux: the symlink is written through, not replaced" still_link
check "linux: the script keeps a copy of itself" cmp -s "$self" "$script"
check "linux: install logs" grep -q '^logger -t sakina-access installed' "$calls"
case $out in *"Root: on, expires"*"Allowed from: 192.0.2.9"*) ok ;; *) bad "linux: status after install: $out" ;; esac
cp "$keyfile" "$work/keys.before"
sa install >/dev/null 2>&1
check "linux: reinstall changes no key" cmp -s "$keyfile" "$work/keys.before"
check "linux: reinstall adds no user" [ "$(grep -c '^useradd' "$calls")" -eq 1 ]
: > "$calls"
out=$(sa 4 2>&1); rc=$?
check "linux: grant succeeds [$rc: $out]" [ $rc -eq 0 ]
check "linux: grant adds one temporary line" eval '[ "$(count "$root_blob")" -eq 1 ] && [ "$(count sakina-access-root-temp)" -eq 1 ]'
stamp=$(sed -n 's/^from="192.0.2.9",expiry-time="\([0-9]*\)Z".*/\1/p' "$keyfile")
check "linux: the grant line pins the source and expires in 4 hours [$stamp]" between "$stamp" "$(stamp_in 14000)" "$(stamp_in 14400)"
check "linux: the grant line runs the root session" has "$keyfile" "Z\",command=\"/usr/local/sbin/sakina-root-session\",no-agent-forwarding,no-X11-forwarding ssh-ed25519 $root_blob sakina-access-root-temp"
check "linux: grant starts the revoke timer" grep -q "^systemd-run --quiet --unit=sakina-access-expire --on-active=4h .* /usr/local/sbin/sakina-access off" "$calls"
check "linux: symlink kept after grant" still_link
case $out in *"Root: on, expires"*) ok ;; *) bad "linux: status after grant: $out" ;; esac
mkdir -p "$h/run/sakina-access"
echo 999999 > "$h/run/sakina-access/root.999999"
: > "$calls"
sa off >/dev/null 2>&1
check "linux: revoke removes the temporary line" [ "$(count "$root_blob")" -eq 0 ]
check "linux: revoke stops the revoke timer" grep -q '^systemctl stop sakina-access-expire.timer' "$calls"
check "linux: revoke keeps the priv line" [ "$(count sakina-access-priv)" -eq 1 ]
check "linux: revoke keeps other keys" [ "$(count "$other_key")" -eq 1 ]
check "linux: revoke clears recorded sessions" [ ! -e "$h/run/sakina-access/root.999999" ]
check "linux: symlink kept after revoke" still_link
printf 'from="192.0.2.9",expiry-time="202001010000Z",command="/usr/local/sbin/sakina-root-session",no-agent-forwarding,no-X11-forwarding ssh-ed25519 %s sakina-access-root-temp\n' "$root_blob" >> "$keyfile"
out=$(sa status 2>&1)
case $out in *"Root: off"*) ok ;; *) bad "linux: an expired grant is not active: $out" ;; esac
sa install >/dev/null 2>&1
check "linux: install clears an expired grant" [ "$(count "$root_blob")" -eq 0 ]

fresh_linux; stage
STUB_PERMIT_ROOT=no sa 2 >/dev/null 2>&1
check "linux: no temporary root when sshd refuses root logins" [ $? -ne 0 ]
check "linux: and no key line is added" [ "$(count sakina-access)" -eq 0 ]
check "linux: root reads move to a sudo rule" [ "$(cat "$h/etc/sudoers.d/sakina-ro" 2>/dev/null)" = "sakina ALL=(root) NOPASSWD: /usr/local/sbin/sakina-ro-priv" ]
check "linux: the sudo rule is checked with visudo" grep -q "^visudo -cqf" "$calls"
check "linux: the sudo rule is 0440" [ -n "$(find "$h/etc/sudoers.d/sakina-ro" -perm 440)" ]
out=$(STUB_PERMIT_ROOT=no sa status 2>&1)
case $out in *"root reads: sudo rule"*) ok ;; *) bad "linux: status with the sudo rule: $out" ;; esac
sa install >/dev/null 2>&1
check "linux: the sudo rule goes once root logins are allowed" eval '[ ! -e "$h/etc/sudoers.d/sakina-ro" ] && [ "$(count sakina-access-priv)" -eq 1 ]'
: > "$h/etc/sudoers"
STUB_PERMIT_ROOT=no sa install >/dev/null 2>&1
check "linux: no sudo rule when sudoers has no drop-in directory" [ ! -e "$h/etc/sudoers.d/sakina-ro" ]
check "linux: and no priv line" [ "$(count sakina-access-priv)" -eq 0 ]

fresh_linux; stage
sa install >/dev/null 2>&1
check "linux: update service is written" grep -q "^ExecStart=/usr/local/sbin/sakina-access update$" "$h/etc/systemd/system/sakina-access-update.service"
check "linux: update timer is daily with a random delay" grep -q '^RandomizedDelaySec=' "$h/etc/systemd/system/sakina-access-update.timer"
check "linux: timer enabled" grep -q "^systemctl enable --now sakina-access-update.timer" "$calls"
: > "$calls"
sa install >/dev/null 2>&1
check "linux: unchanged units need no daemon-reload" not grep -q daemon-reload "$calls"
fresh_linux; stage
touch "$h/etc/NIXOS"
sa install >/dev/null 2>&1
check "nixos: no unit files" [ -z "$(ls "$h/etc/systemd/system")" ]
check "nixos: install works" [ "$(count sakina-access-priv)" -eq 1 ]

fresh_linux; stage
sa install >/dev/null 2>&1
sa 3 >/dev/null 2>&1
: > "$calls"
out=$(sa remove 2>&1); rc=$?
check "linux: remove succeeds [$rc: $out]" [ $rc -eq 0 ]
check "linux: only the other key is left" [ "$(keys)" = "$other_key" ]
check "linux: symlink kept after remove" still_link
check "linux: user deleted" grep -q '^userdel -r sakina' "$calls"
check "linux: timer disabled" grep -q '^systemctl disable --now sakina-access-update.timer' "$calls"
for p in /usr/local/sbin/sakina-ro /usr/local/sbin/sakina-ro-priv /usr/local/sbin/sakina-root-session /usr/local/sbin/sakina-access /etc/sakina-access /etc/systemd/system/sakina-access-update.timer; do
  check "linux: remove deletes $p" [ ! -e "$h$p" ]
done

fresh_router; stage
sa install >/dev/null 2>&1
check "openwrt: install without a list uses the default ranges" [ "$(from_now)" = "$DEFAULTS" ]
fresh_router; stage
sa install --from '192.0.2.1",command="/bin/sh' >/dev/null 2>&1
check "openwrt: a list that could break out of the file is refused" [ $? -ne 0 ]
check "openwrt: and writes nothing" eval '[ ! -e "$h/etc/sakina-access" ] && [ ! -e "$h/usr/sbin/sakina-ssh" ]'
sa install --from '192.0.2.1 $(id)' >/dev/null 2>&1
check "openwrt: a list with shell characters is refused" [ $? -ne 0 ]
fresh_router; stage
mkdir -p "$h/etc/sakina-access"
echo 192.0.2.7 > "$h/etc/sakina-access/from"
sa install >/dev/null 2>&1
check "openwrt: an older version's single-address list gives way to the defaults" [ "$(from_now)" = "$DEFAULTS" ]
check "openwrt: and that is logged" grep -q "^logger -t sakina-access from list 192.0.2.7 replaced by the default ranges" "$calls"
fresh_router; stage
mkdir -p "$h/etc/sakina-access"
echo 192.0.2.0/24 > "$h/etc/sakina-access/from"
sa install >/dev/null 2>&1
check "openwrt: an older version's list with a range stays" [ "$(from_now)" = 192.0.2.0/24 ]

fresh_router; stage
printf 'restrict %s\n%s\n' "ssh-ed25519 $priv_blob old" "ssh-ed25519 $root_blob stale-unrestricted" >> "$keyfile"
out=$(sa install --from "192.0.2.1, 198.51.100.0/24
2001:db8::/32" 2>&1); rc=$?
check "openwrt: install succeeds [$rc: $out]" [ $rc -eq 0 ]
check "openwrt: the list is normalized and saved" [ "$(from_now)" = "192.0.2.1,198.51.100.0/24,2001:db8::/32" ]
check "openwrt: user added with the next free uid" grep -qx 'sakina:x:59001:59001:Sakina (read-only):/home/sakina:/bin/ash' "$h/etc/passwd"
check "openwrt: group added" grep -qx 'sakina:x:59001:' "$h/etc/group"
check "openwrt: no password" grep -qx 'sakina:\*:0:0:99999:7:::' "$h/etc/shadow"
check "openwrt: read-only key line" [ "$(cat "$h/home/sakina/.ssh/authorized_keys")" = "restrict,command=\"/usr/sbin/sakina-ssh\" ssh-ed25519 $ro_blob sakina-readonly" ]
check "openwrt: helper installed and executable" [ -x "$h/usr/sbin/sakina-ssh" ]
check "openwrt: helper is the shown one" cmp -s "$h/usr/sbin/sakina-ssh" "$work/helper-openwrt.orig"
check "openwrt: ubus ACL installed" has "$h/usr/share/acl.d/sakina-access.json" '"user": "sakina"'
check "openwrt: ubusd reloads the ACL" grep -q '^killall -HUP ubusd' "$calls"
check "openwrt: priv key line" [ "$(count "restrict,command=\"/usr/sbin/sakina-ssh\" ssh-ed25519 $priv_blob sakina-access-priv")" -eq 1 ]
check "openwrt: older lines with her keys are gone" eval '[ "$(count "$root_blob")" -eq 0 ] && [ "$(count " old")" -eq 0 ]'
check "openwrt: other keys are kept" [ "$(count "$other_key")" -eq 1 ]
check "openwrt: key file stays 0600" [ -n "$(find "$keyfile" -perm 600)" ]
check "openwrt: the script keeps a copy of itself" cmp -s "$self" "$script"
check "openwrt: daily update in root's crontab" grep -Eq '^[0-9]+ [0-9]+ \* \* \* /usr/sbin/sakina-access update >/dev/null 2>&1 # sakina-access-update$' "$h/etc/crontabs/root"
check "openwrt: cron enabled and restarted" grep -q '^cron restart' "$calls"
for p in /usr/sbin/sakina-access /usr/sbin/sakina-ssh /etc/sakina-access/ /home/sakina/ /usr/share/acl.d/sakina-access.json; do
  check "openwrt: sysupgrade keeps $p" grep -qxF "$p" "$h/etc/sysupgrade.conf"
done
check "openwrt: sysupgrade.conf keeps its own lines" grep -qxF /etc/mything.conf "$h/etc/sysupgrade.conf"
check "openwrt: install logs" grep -q '^logger -t sakina-access installed' "$calls"
case $out in *"Allowed from: 192.0.2.1,198.51.100.0/24,2001:db8::/32"*"Kept on sysupgrade: yes"*) ok ;; *) bad "openwrt: status after install: $out" ;; esac
cp "$h/etc/crontabs/root" "$work/cron.before"
cp "$h/etc/sysupgrade.conf" "$work/sysupgrade.before"
cp "$keyfile" "$work/keys.before"
touch -d "2000-01-01" "$keyfile"
: > "$calls"
sa install >/dev/null 2>&1
rc=$?
check "openwrt: reinstall reads the saved list" eval '[ $rc -eq 0 ] && [ "$(from_now)" = "192.0.2.1,198.51.100.0/24,2001:db8::/32" ]'
check "openwrt: reinstall adds no second user" [ "$(grep -c '^sakina:' "$h/etc/passwd")" -eq 1 ]
check "openwrt: reinstall adds no second priv line" [ "$(count sakina-access-priv)" -eq 1 ]
check "openwrt: reinstall keeps the update time" cmp -s "$h/etc/crontabs/root" "$work/cron.before"
check "openwrt: reinstall adds no sysupgrade lines" cmp -s "$h/etc/sysupgrade.conf" "$work/sysupgrade.before"
check "openwrt: reinstall restarts nothing" not grep -q -e '^cron' -e '^killall' "$calls"
check "openwrt: reinstall leaves root's key file alone" [ -z "$(find "$keyfile" -newer "$work/keys.before")" ]

: > "$calls"
before=$(date +%s)
out=$(sa 3 2>&1); rc=$?
check "openwrt: grant succeeds [$rc: $out]" [ $rc -eq 0 ]
stamp=$(sed -n "s/.*command=\"\/usr\/sbin\/sakina-ssh root \([0-9]*\)\" ssh-ed25519 $root_blob sakina-access-root-temp$/\1/p" "$keyfile")
lo=$(date -u -d "@$((before + 3 * 3600))" +%Y%m%d%H%M)
hi=$(stamp_in 10800)
check "openwrt: grant line expires in 3 hours [$stamp]" between "$stamp" "$lo" "$hi"
check "openwrt: grant line has no forwarding" has "$keyfile" "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command=\"/usr/sbin/sakina-ssh root $stamp\""
exp_local=$(date -d "@$(date -u -d "$(echo "$stamp" | sed 's/^\(....\)\(..\)\(..\)\(..\)\(..\)$/\1-\2-\3 \4:\5/')" +%s)" '+%M %H %d %m' 2>/dev/null)
read -r mi hh dd mo <<EOF
$exp_local
EOF
check "openwrt: revoke runs at the expiry minute" grep -qx "${mi#0} ${hh#0} ${dd#0} ${mo#0} \* /usr/sbin/sakina-access off >/dev/null 2>&1 # sakina-access-expire" "$h/etc/crontabs/root"
check "openwrt: update line kept" grep -q 'sakina-access-update$' "$h/etc/crontabs/root"
check "openwrt: grant is logged" grep -q '^logger -t sakina-access root granted for 3h' "$calls"
case $out in *"Root: on, expires"*) ok ;; *) bad "openwrt: status after grant: $out" ;; esac
sa 5 >/dev/null 2>&1
check "openwrt: a second grant replaces the first" eval '[ "$(count sakina-access-root-temp)" -eq 1 ] && [ "$(grep -c sakina-access-expire "$h/etc/crontabs/root")" -eq 1 ]'

# a live root session, the helper's process and a child of it, outside this shell's process tree
mkdir -p "$work/sess" "$h/var/run/sakina-access"
printf 'sleep 300 &\nwait\n' > "$work/sess/sakina-ssh"
( "$SH" "$work/sess/sakina-ssh" </dev/null >/dev/null 2>&1 & echo $! > "$work/sess/pid" )
sleep 1
sess=$(cat "$work/sess/pid")
echo "$sess" > "$h/var/run/sakina-access/root.$sess"
child=$(grep -l "^PPid:[[:space:]]*$sess$" /proc/[0-9]*/status 2>/dev/null | head -n1 | cut -d/ -f3)
: > "$calls"
out=$(sa 2>&1); rc=$?
check "openwrt: toggle revokes an active grant [$rc]" eval '[ $rc -eq 0 ] && [ "$(count root-temp)" -eq 0 ]'
check "openwrt: revoke removes the expiry cron line" not grep -q sakina-access-expire "$h/etc/crontabs/root"
check "openwrt: revoke keeps the update line" grep -q sakina-access-update "$h/etc/crontabs/root"
check "openwrt: revoke keeps the priv line" [ "$(count sakina-access-priv)" -eq 1 ]
sleep 0.3
check "openwrt: revoke ends the recorded session" gone "$sess"
check "openwrt: and its child processes [$child]" gone "$child"
check "openwrt: and its record" [ ! -e "$h/var/run/sakina-access/root.$sess" ]
kill -9 "$sess" "$child" 2>/dev/null
echo 1 > "$h/var/run/sakina-access/root.1"
sa off >/dev/null 2>&1
check "openwrt: a stale record never kills an unrelated process" [ -d /proc/1 ]
case $out in *"Root: off"*) ok ;; *) bad "openwrt: status after revoke: $out" ;; esac
printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="/usr/sbin/sakina-ssh root 202001010000" ssh-ed25519 %s sakina-access-root-temp\n' "$root_blob" >> "$keyfile"
sa install >/dev/null 2>&1
check "openwrt: install clears an expired grant whose revoke was missed" [ "$(count root-temp)" -eq 0 ]

fresh_router; stage
STUB_ROOTLOGIN=0 sa install --from 192.0.2.1 >/dev/null 2>&1
check "openwrt: with RootLogin off there is no priv line" [ "$(count sakina-access)" -eq 0 ]
STUB_ROOTLOGIN=off sa 2 >/dev/null 2>&1
rc=$?
check "openwrt: and no temporary root" eval '[ $rc -ne 0 ] && [ "$(count sakina-access)" -eq 0 ]'

fresh_router; stage
echo '0 5 * * * /usr/bin/other-job' > "$h/etc/crontabs/root"
cp "$h/etc/sysupgrade.conf" "$work/sysupgrade.orig"
cp "$h/etc/passwd" "$work/passwd.orig"; cp "$h/etc/group" "$work/group.orig"; cp "$h/etc/shadow" "$work/shadow.orig"
sa install --from 192.0.2.1 >/dev/null 2>&1
sa 4 >/dev/null 2>&1
: > "$calls"
out=$(sa remove 2>&1); rc=$?
check "openwrt: remove succeeds [$rc: $out]" [ $rc -eq 0 ]
check "openwrt: only the other key is left" [ "$(keys)" = "$other_key" ]
check "openwrt: passwd restored" cmp -s "$h/etc/passwd" "$work/passwd.orig"
check "openwrt: group restored" cmp -s "$h/etc/group" "$work/group.orig"
check "openwrt: shadow restored" cmp -s "$h/etc/shadow" "$work/shadow.orig"
check "openwrt: sysupgrade.conf restored" [ "$(cat "$h/etc/sysupgrade.conf")" = "$(cat "$work/sysupgrade.orig")" ]
check "openwrt: other cron jobs kept, ours gone" [ "$(cat "$h/etc/crontabs/root")" = '0 5 * * * /usr/bin/other-job' ]
check "openwrt: cron restarted" grep -q '^cron restart' "$calls"
check "openwrt: ubusd reloads without the ACL" grep -q '^killall -HUP ubusd' "$calls"
for p in /home/sakina /usr/sbin/sakina-ssh /usr/sbin/sakina-access /usr/share/acl.d/sakina-access.json /etc/sakina-access /var/run/sakina-access; do
  check "openwrt: remove deletes $p" [ ! -e "$h$p" ]
done
fresh_router; stage
sa install --from 192.0.2.1 >/dev/null 2>&1
sa remove >/dev/null 2>&1
check "openwrt: a crontab with only our line is removed" [ ! -e "$h/etc/crontabs/root" ]

version() {
  printf '#!/bin/sh\n%s\necho "%s $*" >> "%s"\nexit %s\n' "$(sed -n 2p "$script")" "$2" "$calls" "${3:-0}" > "$1"
}
for kind in linux router; do
  "fresh_$kind"; stage
  sa install >/dev/null 2>&1
  version "$self" OLD
  cp "$self" "$work/old"
  : > "$calls"
  STUB_DOWNLOAD=/nonexistent upd >/dev/null 2>&1
  check "$kind: failed download fails the update" [ $? -ne 0 ]
  check "$kind: failed download keeps the current version" cmp -s "$self" "$work/old"
  check "$kind: failed download is logged" grep -q 'update: download failed' "$calls"
  printf '#!/bin/sh\n%s\nif then\n' "$(sed -n 2p "$script")" > "$work/broken"
  STUB_DOWNLOAD=$work/broken upd >/dev/null 2>&1
  rc=$?
  check "$kind: a download that fails sh -n is not installed" eval '[ $rc -ne 0 ] && cmp -s "$self" "$work/old"'
  printf '<html>rate limited</html>\n' > "$work/html"
  STUB_DOWNLOAD=$work/html upd >/dev/null 2>&1
  rc=$?
  check "$kind: a download without the header is not installed" eval '[ $rc -ne 0 ] && cmp -s "$self" "$work/old"'
  sed 2d "$script" > "$work/noheader"
  STUB_DOWNLOAD=$work/noheader upd >/dev/null 2>&1
  check "$kind: a script with another second line is not accepted" cmp -s "$self" "$work/old"
  out=$(STUB_DOWNLOAD=$work/old upd)
  check "$kind: same version is left alone [$out]" [ "$out" = "Already up to date." ]
  check "$kind: same version runs no install" not grep -q "OLD install" "$calls"
  version "$work/new" NEW
  STUB_DOWNLOAD=$work/new upd >/dev/null
  check "$kind: new version is installed" cmp -s "$self" "$work/new"
  check "$kind: new version's install runs" grep -q "^NEW install$" "$calls"
  check "$kind: new version is logged" grep -q 'update: installed the new version' "$calls"
  version "$self" OLD
  version "$work/new" NEW 1
  : > "$calls"
  STUB_DOWNLOAD=$work/new upd >/dev/null 2>&1
  check "$kind: a failed install fails the update" [ $? -ne 0 ]
  check "$kind: a new version whose install fails is rolled back" cmp -s "$self" "$work/old"
  check "$kind: and the old version's install runs again" grep -q "^OLD install$" "$calls"
  upd >/dev/null 2>&1
  rc=$?
  check "$kind: the real script passes the update checks and installs" eval '[ $rc -eq 0 ] && cmp -s "$self" "$script"'
done

old_dir=$work/old-layout
mkdir -p "$old_dir"
if [ -n "$GIT" ] && "$GIT" -C "$here" show "$TWO_SCRIPTS_REV:scripts/sakina-access/sakina-access-openwrt" > "$old_dir/openwrt" 2>/dev/null &&
  "$GIT" -C "$here" show "$TWO_SCRIPTS_REV:scripts/sakina-access/sakina-access" > "$old_dir/linux" 2>/dev/null; then
  helper_now() { show_helper "$h"; }

  old_router() {
    fresh_router
    cp "$old_dir/openwrt" "$h/sakina-access-openwrt"
    SAKINA_ACCESS_ROOT=$h PATH="$mstub:$REAL_PATH" "$SH" "$h/sakina-access-openwrt" install --from "$1" >/dev/null 2>&1 &&
      SAKINA_ACCESS_ROOT=$h PATH="$mstub:$REAL_PATH" "$SH" "$self" 3 >/dev/null 2>&1
  }
  snap_files() { echo "$keyfile $h/etc/crontabs/root $h/etc/sysupgrade.conf $h/etc/passwd $h/etc/shadow $h/usr/share/acl.d/sakina-access.json $h/home/sakina/.ssh/authorized_keys"; }
  snapshot() { i=0; for f in $(snap_files); do i=$((i + 1)); cp "$f" "$work/snap.$i"; done; }
  same_as_snapshot() {
    i=0
    for f in $(snap_files); do
      i=$((i + 1))
      cmp -s "$f" "$work/snap.$i" || { echo "changed: $f"; diff "$work/snap.$i" "$f"; return 1; }
    done
  }

  old_router 192.0.2.0/24
  check "old openwrt: installs and grants" [ "$(count sakina-access-root-temp)" -eq 1 ]
  snapshot
  cp "$self" "$work/old-self"
  : > "$calls"
  out=$(SAKINA_ACCESS_ROOT=$h STUB_REPO=$work/repo PATH="$mstub:$REAL_PATH" "$SH" "$self" update 2>&1); rc=$?
  check "old openwrt -> new: the old update succeeds [$rc: $out]" [ $rc -eq 0 ]
  check "old openwrt -> new: the shared script is installed" cmp -s "$self" "$script"
  helper_now > "$work/hn"
  check "old openwrt -> new: the helper is the new one" cmp -s "$h/usr/sbin/sakina-ssh" "$work/hn"
  check "old openwrt -> new: keys, grant, crontab, sysupgrade.conf, user and ACL unchanged" same_as_snapshot
  check "old openwrt -> new: a list with a range stays" [ "$(from_now)" = 192.0.2.0/24 ]
  check "old openwrt -> new: logged" grep -q 'update: installed the new version' "$calls"
  out=$(upd "$self" 2>&1)
  check "old openwrt -> new: the next update finds nothing new [$out]" [ "$out" = "Already up to date." ]
  out=$(SAKINA_ACCESS_ROOT=$h PATH="$mstub:$REAL_PATH" "$SH" "$self" status 2>&1)
  case $out in *"Root: on"*"Auto-update: daily"*"Kept on sysupgrade: yes"*) ok ;; *) bad "old openwrt -> new: status: $out" ;; esac

  old_router 192.0.2.10
  SAKINA_ACCESS_ROOT=$h STUB_REPO=$work/repo PATH="$mstub:$REAL_PATH" "$SH" "$self" update >/dev/null 2>&1
  check "old openwrt -> new: a single-address list gives way to the defaults" [ "$(from_now)" = "$DEFAULTS" ]
  check "old openwrt -> new: the grant survives" [ "$(count sakina-access-root-temp)" -eq 1 ]

  old_router 192.0.2.10
  mkdir -p "$work/repo-stub-only"
  cp "$stub" "$work/repo-stub-only/"
  snapshot
  SAKINA_ACCESS_ROOT=$h STUB_REPO=$work/repo-stub-only PATH="$mstub:$REAL_PATH" "$SH" "$self" update >/dev/null 2>&1
  check "old openwrt -> new: when the hand-over can't download, the update fails" [ $? -ne 0 ]
  check "old openwrt -> new: and the old script is back" cmp -s "$self" "$old_dir/openwrt"
  check "old openwrt -> new: with nothing else changed" same_as_snapshot
  check "old openwrt -> new: and its list kept" [ "$(from_now)" = 192.0.2.10 ]

  if [ -n "$BASH_BIN" ]; then
    oldstub=$work/old-bin
    mkdir -p "$oldstub"
    cat > "$oldstub/install" <<EOF
#!$SH
n=0
for a in "\$@"; do
  shift
  case "\$n:\$a" in 1:*) n=0; continue ;; *:-o|*:-g) n=1; continue ;; esac
  set -- "\$@" "\$a"
done
PATH=$HOST_PATH exec install "\$@"
EOF
    chmod +x "$oldstub/install"
    old_linux() {
      SAKINA_ACCESS_ROOT=$h STUB_REPO=${OLD_REPO:-$work/repo} PATH="$oldstub:$mstub:$HOST_PATH" "$BASH_BIN" -c '
        source "$1"; set +e
        h=$2
        ROOT_KEYS=$h/root/.ssh/authorized_keys USER_HOME=$h/home/sakina CONF_DIR=$h/etc/sakina-access
        FROM_FILE=$h/etc/sakina-access/from SUDOERS=$h/etc/sudoers.d/sakina-ro SUDOERS_MAIN=$h/etc/sudoers
        UNIT_DIR=$h/etc/systemd/system NIXOS_MARK=$h/etc/NIXOS RUN_DIR=$h/run/sakina-access
        SELF=$h/usr/local/sbin/sakina-access
        eval "$3"' _ "$old_dir/linux" "$h" "$1"
    }
    old_host() {
      fresh_linux
      echo "sakina:x:59001:59001:Sakina (read-only):/home/sakina:/bin/bash" >> "$h/etc/passwd"
      mkdir -p "$h/home/sakina/.ssh"
      old_linux '
        load_from "'"$1"'"
        write_ro_cmd > "$h/usr/local/sbin/sakina-ro"; write_priv_cmd > "$h/usr/local/sbin/sakina-ro-priv"
        write_root_session > "$h/usr/local/sbin/sakina-root-session"
        chmod 0755 "$h"/usr/local/sbin/sakina-*
        ro_line > "$USER_HOME/.ssh/authorized_keys"; echo >> "$USER_HOME/.ssh/authorized_keys"
        install_priv_access
        cp "$1" "$SELF"
        (SELF=/usr/local/sbin/sakina-access; install_update_timer)
        grant_root 2' >/dev/null 2>&1
    }
    old_host 192.0.2.0/24
    check "old linux: installs and grants" eval '[ "$(count sakina-access-root-temp)" -eq 1 ] && [ "$(count sakina-access-priv)" -eq 1 ]'
    cp "$keyfile" "$work/snap.keys"
    cp "$h/home/sakina/.ssh/authorized_keys" "$work/snap.ro"
    cp "$h/etc/systemd/system/sakina-access-update.service" "$work/snap.service"
    cp "$h/etc/systemd/system/sakina-access-update.timer" "$work/snap.timer"
    : > "$calls"
    out=$(old_linux update_self 2>&1); rc=$?
    check "old linux -> new: the old update succeeds [$rc: $out]" [ $rc -eq 0 ]
    check "old linux -> new: the shared script is installed" cmp -s "$self" "$script"
    helper_now > "$work/hn"
    for p in sakina-ro sakina-ro-priv sakina-root-session; do
      check "old linux -> new: $p is the new helper" cmp -s "$h/usr/local/sbin/$p" "$work/hn"
    done
    check "old linux -> new: root's keys unchanged, live grant included" cmp -s "$keyfile" "$work/snap.keys"
    check "old linux -> new: the read-only key line unchanged" cmp -s "$h/home/sakina/.ssh/authorized_keys" "$work/snap.ro"
    check "old linux -> new: the update units unchanged" eval 'cmp -s "$h/etc/systemd/system/sakina-access-update.service" "$work/snap.service" && cmp -s "$h/etc/systemd/system/sakina-access-update.timer" "$work/snap.timer"'
    check "old linux -> new: the symlink is kept" still_link
    check "old linux -> new: logged" grep -q 'update: installed the new version' "$calls"
    out=$(upd "$self" 2>&1)
    check "old linux -> new: the next update finds nothing new [$out]" [ "$out" = "Already up to date." ]

    old_host 192.0.2.10
    expiry=$(sed -n 's/.*expiry-time="\([0-9]*\)Z".*/\1/p' "$keyfile")
    old_linux update_self >/dev/null 2>&1
    check "old linux -> new: a single-address list gives way to the defaults" [ "$(from_now)" = "$DEFAULTS" ]
    check "old linux -> new: the key lines carry the defaults" [ "$(count "from=\"$DEFAULTS\"")" -eq 2 ]
    check "old linux -> new: the grant keeps its expiry" [ "$(count "expiry-time=\"${expiry}Z\"")" -eq 1 ]

    old_host 192.0.2.10
    snap_keys=$(keys)
    OLD_REPO=/nonexistent old_linux update_self >/dev/null 2>&1
    check "old linux: a failed download keeps the old version" cmp -s "$self" "$old_dir/linux" && [ "$(keys)" = "$snap_keys" ]
  else
    echo "SKIP: no bash, so no update test from the old Linux script"
  fi
else
  echo "SKIP: no git history with $TWO_SCRIPTS_REV, so no update tests from the old scripts"
fi

real_helper() {
  sed -e "s|^export PATH=[^ ]*|export PATH=$hstub:$REAL_PATH|" -e "s|^RUN_DIR=.*|RUN_DIR=$s/run|" \
    -e "s|^ROOT_SHELL=.*|ROOT_SHELL=$SH|" -e "s|^FROM_FILE=.*|FROM_FILE=$s/from|" "$1" > "$2"
}

if [ -n "$SSHD_BIN" ] && [ -x "$SSHD_BIN" ] && [ -n "$SSH_BIN" ] && [ -n "$KEYGEN" ]; then
  s=$(mktemp -d)
  trap 'rm -rf "$work" ${FARM:+"$FARM"} "$s"' EXIT
  for k in host ro priv root expired stranger; do "$KEYGEN" -q -t ed25519 -N '' -C "$k" -f "$s/$k"; done
  pub() { cut -d' ' -f2 "$s/$1.pub"; }
  real_helper "$work/helper-linux.orig" "$s/sakina-ro"
  sed 's|^me=.*|me=0|' "$s/sakina-ro" > "$s/sakina-ro-priv"
  cp "$s/sakina-ro-priv" "$s/sakina-root-session"

  fresh_linux; stage
  sa install --from "$DEFAULTS,127.0.0.0/8,::1" >/dev/null 2>&1
  sa 1 >/dev/null 2>&1
  ro_line=$(cat "$h/home/sakina/.ssh/authorized_keys")
  priv_line=$(grep sakina-access-priv "$keyfile")
  root_line=$(grep sakina-access-root-temp "$keyfile")
  fresh_linux; stage
  sa install >/dev/null 2>&1
  default_priv_line=$(grep sakina-access-priv "$keyfile")
  paths() { sed -e "s|/usr/local/sbin/|$SH $s/|"; }
  {
    printf '%s\n' "$ro_line" | sed "s|$ro_blob|$(pub ro)|" | paths
    printf '%s\n' "$priv_line" | sed "s|$priv_blob|$(pub priv)|" | paths
    printf '%s\n' "$root_line" | sed "s|$root_blob|$(pub root)|" | paths
    printf '%s\n' "$root_line" | sed -e "s|$root_blob|$(pub expired)|" -e "s|expiry-time=\"[0-9]*Z\"|expiry-time=\"$(stamp_in -3600)Z\"|" | paths
    printf '%s\n' "$default_priv_line" | sed "s|$priv_blob|$(pub stranger)|" | paths
  } > "$s/authorized_keys"
  port=$(( 20000 + ($$ + $(date +%s)) % 20000 ))
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
  session_bin=$(dirname "$SSHD_BIN")/../lib/openssh/sshd-session
  [ -x "$session_bin" ] && echo "SshdSessionPath $session_bin" >> "$s/sshd_config"
  over_ssh() {
    "$SSHD_BIN" -d -r -f "$s/sshd_config" > "$s/sshd.log" 2>&1 &
    spid=$!
    i=0
    while [ $i -lt 50 ] && ! grep -q "Server listening" "$s/sshd.log"; do sleep 0.1; i=$((i + 1)); done
    "$SSH_BIN" -F /dev/null -p "$port" -i "$s/$1" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$(id -un)@127.0.0.1" "$2" 2>/dev/null
    src=$?
    wait "$spid" 2>/dev/null
    return $src
  }
  out=$(over_ssh ro uptime)
  check "sshd: read-only key runs its forced command, with the default ranges in from= [$out]" [ "$out" = "RAN uptime" ]
  out=$(over_ssh ro 'systemctl stop ssh'); rc=$?
  check "sshd: read-only key refuses a write [$rc $out]" [ $rc -eq 2 ]
  out=$(over_ssh priv 'docker ps')
  check "sshd: priv key runs the priv helper [$out]" [ "$out" = "RAN docker ps" ]
  out=$(over_ssh root 'echo hi')
  check "sshd: temporary root key works before its expiry [$out]" [ "$out" = "hi" ]
  over_ssh expired 'echo hi' >/dev/null; rc=$?
  check "sshd: expired temporary root key is refused [$rc]" [ $rc -eq 255 ]
  grep -q "expired" "$s/sshd.log" || bad "sshd: log does not say the key expired"
  over_ssh stranger 'docker ps' >/dev/null; rc=$?
  check "sshd: a key used from outside the default ranges is refused [$rc]" [ $rc -eq 255 ]
  rm -rf "$s"
elif [ -n "${SSHD:-}" ]; then
  bad "SSHD=$SSHD is not executable, or ssh/ssh-keygen are missing"
else
  echo "SKIP: no sshd found, set SSHD=/path/to/sshd for the real sshd checks"
fi

if [ -n "$DB" ] && [ -x "$DB" ] && [ -n "$SSH_BIN" ] && [ -n "$KEYGEN" ]; then
  # dropbear refuses an authorized_keys file below a world-writable directory such as /tmp.
  s=$(mktemp -d "$HOME/.sakina-access-test.XXXXXX")
  trap 'rm -rf "$work" ${FARM:+"$FARM"} "$s"' EXIT
  for k in ro priv root expired; do "$KEYGEN" -q -t ed25519 -N '' -C "$k" -f "$s/$k"; done
  pub() { cut -d' ' -f2 "$s/$1.pub"; }
  echo "$DEFAULTS,127.0.0.1,::1" > "$s/from"
  echo "$DEFAULTS" > "$s/from-other"
  real_helper "$work/helper-openwrt.orig" "$s/ro-helper"
  sed -e 's|^me=.*|me=0|' "$s/ro-helper" > "$s/root-helper"
  sed -e "s|^FROM_FILE=.*|FROM_FILE=$s/from-other|" "$s/ro-helper" > "$s/other-helper"

  fresh_router; stage
  sa install >/dev/null 2>&1
  sa 1 >/dev/null 2>&1
  ro_line=$(cat "$h/home/sakina/.ssh/authorized_keys")
  priv_line=$(grep sakina-access-priv "$keyfile")
  root_line=$(grep sakina-access-root-temp "$keyfile")
  {
    printf '%s\n' "$ro_line" | sed -e "s|$ro_blob|$(pub ro)|" -e "s|/usr/sbin/sakina-ssh|$SH $s/ro-helper|"
    printf '%s\n' "$priv_line" | sed -e "s|$priv_blob|$(pub priv)|" -e "s|/usr/sbin/sakina-ssh|$SH $s/other-helper|"
    printf '%s\n' "$root_line" | sed -e "s|$root_blob|$(pub root)|" -e "s|/usr/sbin/sakina-ssh|$SH $s/root-helper|"
    printf '%s\n' "$root_line" | sed -e "s|$root_blob|$(pub expired)|" -e "s|/usr/sbin/sakina-ssh|$SH $s/root-helper|" \
      -e "s|root [0-9]*\"|root $(stamp_in -120)\"|"
  } > "$s/authorized_keys"
  chmod 600 "$s/authorized_keys"
  port=$(( 20000 + ($$ + $(date +%s)) % 20000 ))
  "$(dirname "$DB")/dropbearkey" -t ed25519 -f "$s/hostkey" >/dev/null 2>&1
  "$DB" -F -E -s -D "$s" -r "$s/hostkey" -p "127.0.0.1:$port" -P "$s/pid" > "$s/log" 2>&1 &
  dbpid=$!
  sleep 0.5
  over_ssh() {
    k=$1 c=$2; shift 2
    "$SSH_BIN" -F /dev/null -p "$port" -i "$s/$k" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 "$@" "$(id -un)@127.0.0.1" "$c" 2>/dev/null
  }
  out=$(over_ssh ro uptime)
  check "dropbear: read-only key runs its forced command [$out]" [ "$out" = "RAN uptime" ]
  out=$(over_ssh ro 'ubus call network.interface.wan down'); rc=$?
  check "dropbear: read-only key refuses a write [$rc $out]" [ $rc -eq 2 ]
  out=$(over_ssh ro ''); rc=$?
  check "dropbear: no shell without a command [$rc]" [ $rc -eq 1 ]
  out=$(over_ssh priv uptime); rc=$?
  check "dropbear: a client outside the default ranges is refused [$rc $out]" [ $rc -eq 2 ]
  out=$(over_ssh root 'echo hi')
  check "dropbear: temporary root runs commands before expiry [$out]" [ "$out" = "hi" ]
  out=$(over_ssh expired 'echo hi'); rc=$?
  check "dropbear: temporary root after expiry is refused [$rc $out]" [ $rc -eq 2 ]
  over_ssh ro x -N -W 127.0.0.1:"$port" </dev/null >/dev/null; rc=$?
  check "dropbear: restrict blocks forwarding [$rc]" [ $rc -ne 0 ]
  out=$(printf 'SSH-2.0-x\n' | over_ssh root x -W 127.0.0.1:"$port" | head -c 7); rc=$?
  check "dropbear: no forwarding on the root key [$out]" [ "$out" != "SSH-2.0" ]
  # dropbear does not know from= and refuses the whole line, which is why the helper checks.
  printf 'from="127.0.0.1",command="%s %s/ro-helper" ssh-ed25519 %s from-test\n' "$SH" "$s" "$(pub ro)" > "$s/authorized_keys"
  over_ssh ro uptime >/dev/null; rc=$?
  check "dropbear: a from= option makes it refuse the key [$rc]" [ $rc -eq 255 ]
  grep -q "Bad public key options" "$s/log" || bad "dropbear: log does not show the refused from= option"
  kill "$dbpid" 2>/dev/null
  wait "$dbpid" 2>/dev/null
  rm -rf "$s"
elif [ -n "${DROPBEAR:-}" ]; then
  bad "DROPBEAR=$DROPBEAR is not executable, or ssh/ssh-keygen are missing"
else
  echo "SKIP: no dropbear found, set DROPBEAR=/path/to/dropbear for the real dropbear checks"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
