#!/bin/sh
# Tests for sakina-access-openwrt, run under BusyBox as a normal user with stub commands:
#   - the allow/deny rules, secret masking and source check of the sakina-ssh helper
#   - install, grants, revokes, cron, sysupgrade.conf and remove on a scratch root
#   - the self-update
#   - the key lines against a real dropbear, when one is found ($DROPBEAR or PATH, with
#     dropbearkey next to it)
# Needs busybox ($BUSYBOX or PATH); re-runs itself in `busybox sh` with only BusyBox applets
# and the stubs on PATH, like on the router.
# shellcheck disable=SC2016 # command lines are single-quoted so they reach the helper unexpanded
set -u

here=$(cd "$(dirname "$0")" && pwd)
script=$here/sakina-access-openwrt

if [ -z "${IN_BUSYBOX:-}" ]; then
  bb=${BUSYBOX:-$(command -v busybox || true)}
  [ -x "$bb" ] || { echo "busybox not found; set BUSYBOX=/path/to/busybox" >&2; exit 1; }
  applets=$(mktemp -d)
  for a in $("$bb" --list); do ln -s "$bb" "$applets/$a"; done
  printf '#!%s/sh\necho stub\n' "$applets" > "$applets/stub-probe"; chmod +x "$applets/stub-probe"
  mkdir "$applets/probe"; cp "$applets/stub-probe" "$applets/probe/uname"
  if [ "$(PATH="$applets/probe:$applets" "$bb" sh -c uname)" != stub ]; then
    rm -rf "$applets"
    echo "$bb runs its applets before PATH (FEATURE_SH_STANDALONE), so the stubs can't work; use a build without it, like Debian's busybox package" >&2
    exit 1
  fi
  rm -rf "$applets/probe" "$applets/stub-probe"
  db=${DROPBEAR:-$(command -v dropbear || true)}
  exec env IN_BUSYBOX=1 BB="$bb" FARM="$applets" DB="$db" \
    SSH_BIN="$(command -v ssh || true)" KEYGEN="$(command -v ssh-keygen || true)" \
    PYTHON="$(command -v python3 || true)" PATH="$applets" "$bb" sh "$0" "$@"
fi

work=$(mktemp -d)
trap 'rm -rf "$work" "$FARM"' EXIT
pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
check() { # check <description> <command...>
  d=$1; shift
  if "$@"; then ok; else bad "$d"; fi
}
not() { ! "$@"; }
has() { grep -qF -- "$2" "$1"; }

nl='
'

# ---------------------------------------------------------------- helper

hstub=$work/helper-bin
mkdir -p "$hstub" "$work/run"
calls=$work/calls
for c in ubus uci logread ifstatus iwinfo apk ip ss netstat df free uptime uname hostname top \
  cat head tail wc ls grep wg tailscale dmesg date; do
  printf '#!%s/sh\necho "RAN %s${*:+ $*}"\n' "$FARM" "$c" > "$hstub/$c"
done
cat > "$hstub/ubus" <<EOF
#!$FARM/sh
if [ -n "\${STUB_OUT:-}" ]; then $FARM/cat "\$STUB_OUT"; else echo "RAN ubus\${*:+ \$*}"; fi
EOF
cp "$hstub/ubus" "$hstub/uci"; sed -i 's/RAN ubus/RAN uci/' "$hstub/uci"
printf '#!%s/sh\n' "$FARM" > "$hstub/logger"
printf '#!%s/sh\necho "${STUB_UID:-1000}"\n' "$FARM" > "$hstub/id"
# The root session's expiry check needs the real date.
rm -f "$hstub/date"
chmod +x "$hstub"/*

from_file=$work/from
echo '192.0.2.0/24,2001:db8::/32' > "$from_file"
"$BB" sh "$script" show | awk '/^===== \/usr\/sbin/ { f = 1; next } /^===== / { f = 0 } f' > "$work/helper.orig"
sed -e "s|^export PATH=.*|export PATH=$hstub:$FARM|" -e "s|^FROM_FILE=.*|FROM_FILE=$from_file|" \
  -e "s|^RUN_DIR=.*|RUN_DIR=$work/run|" -e "s|/bin/ash|$FARM/ash|g" "$work/helper.orig" > "$work/sakina-ssh"

client='192.0.2.10 40000 22'
run_ssh() { # run_ssh <command line> [helper args...]: prints output, returns the exit code
  l=$1; shift
  (cd "$work" && SSH_CLIENT=$client SSH_ORIGINAL_COMMAND=$l sh "$work/sakina-ssh" "$@" 2>&1)
}
allow() { # allow <command line> <expected output>
  out=$(run_ssh "$1"); rc=$?
  if [ $rc -eq 0 ] && [ "$out" = "$2" ]; then ok; else bad "should run [$1] as [$2], got rc=$rc [$out]"; fi
}
deny() { # deny <command line>
  out=$(run_ssh "$1"); rc=$?
  case $out in *RAN*) rc=99 ;; esac
  if [ $rc -eq 2 ]; then ok; else bad "should refuse [$1], got rc=$rc [$out]"; fi
}

# read-only key (not root)
export STUB_UID=1000
allow 'ubus call system board' 'RAN ubus call system board'
allow 'ubus call network.interface.wan status' 'RAN ubus call network.interface.wan status'
allow 'ubus call network.interface dump' 'RAN ubus call network.interface dump'
allow 'ubus -t 5 call hostapd.phy0-ap0 get_clients' 'RAN ubus -t 5 call hostapd.phy0-ap0 get_clients'
allow 'ubus call iwinfo assoclist '\''{"device":"phy0-ap0"}'\' 'RAN ubus call iwinfo assoclist {"device":"phy0-ap0"}'
allow 'ubus call luci-rpc getDHCPLeases' 'RAN ubus call luci-rpc getDHCPLeases'
allow 'ubus -v list network.*' 'RAN ubus -v list network.*'
deny  'ubus call network.interface.wan down'
deny  'ubus call network.interface.wan up'
deny  'ubus call network reload'
deny  'ubus call system reboot'
deny  'ubus call system sysupgrade'
deny  'ubus call uci set {}'
deny  'ubus call uci commit {}'
deny  'ubus call file exec {}'
deny  'ubus call luci setPassword {}'
deny  'ubus call network.wireless status'
deny  'ubus call hostapd.phy0-ap0 del_client {}'
deny  'ubus call "network.interface.wan;id" status'
deny  'ubus -s /tmp/other.sock call system board'
deny  'ubus -S call system board'
deny  'ubus send foo {}'
deny  'ubus monitor'
deny  'ubus call system'
allow 'logread -l 50 -e dropbear' 'RAN logread -l 50 -e dropbear'
allow 'logread -e "auth fail"' 'RAN logread -e auth fail'
deny  'logread -F /tmp/x'
deny  'logread -p /tmp/pid'
deny  'logread -r 192.0.2.1 514'
deny  'logread -s /tmp/other.sock'
allow 'ifstatus wan' 'RAN ifstatus wan'
deny  'ifstatus "wan;id"'
deny  'ifstatus wan lan'
allow 'uci show wireless' 'RAN uci show wireless'
allow 'uci -X show' 'RAN uci -X show'
deny  'uci set wireless.radio0.disabled=1'
deny  'uci commit'
deny  'uci delete network.wan'
deny  'uci get wireless.default_radio0.key'
deny  'uci export wireless'
deny  'uci -c /tmp show'
deny  'uci -P /tmp show'
deny  'uci show "x;id"'
allow 'apk list --upgradable' 'RAN apk list --upgradable'
allow 'apk info -L dropbear' 'RAN apk info -L dropbear'
deny  'apk add tcpdump'
deny  'apk del dropbear'
deny  'apk update'
deny  'apk upgrade'
deny  'apk list -U'
deny  'apk --root /tmp list'
deny  'apk list --allow-untrusted'
allow 'iwinfo' 'RAN iwinfo'
allow 'iwinfo phy0-ap0 assoclist' 'RAN iwinfo phy0-ap0 assoclist'
deny  'iwinfo phy0-ap0 scan'
allow 'ip -br addr' 'RAN ip -br addr'
allow 'ip -6 route show table all' 'RAN ip -6 route show table all'
allow 'ip route get 192.0.2.1' 'RAN ip route get 192.0.2.1'
allow 'ip neigh' 'RAN ip neigh'
deny  'ip link set eth0 down'
deny  'ip addr add 192.0.2.1/24 dev eth0'
deny  'ip route flush all'
deny  'ip netns exec x sh'
deny  'ip -batch /tmp/x'
deny  'ip -n other addr'
allow 'ss -tlnp' 'RAN ss -tlnp'
allow 'ss -tn state established' 'RAN ss -tn state established'
deny  'ss -K dst 192.0.2.1'
deny  'ss -tnK'
deny  'ss -F /tmp/filter'
deny  'ss --kill'
allow 'netstat -tln' 'RAN netstat -tln'
allow 'df -h' 'RAN df -h'
allow 'free' 'RAN free'
allow 'uptime' 'RAN uptime'
allow 'uname -a' 'RAN uname -a'
allow 'top -bn1' 'RAN top -b -n 1'
allow 'top -b -n 1' 'RAN top -b -n 1'
allow 'top' 'RAN top -b -n 1'
deny  'top -d 1'
run_ssh date >/dev/null
check "date runs" [ $? -eq 0 ]
deny  'date -s 2020-01-01'
deny  'hostname evil'
allow 'cat /proc/meminfo' 'RAN cat /proc/meminfo'
allow 'tail -n 20 /tmp/dhcp.leases' 'RAN tail -n 20 /tmp/dhcp.leases'
allow 'ls -la /sys/class' 'RAN ls -la /sys/class'
allow 'grep -i error /proc/meminfo' 'RAN grep -i error /proc/meminfo'
allow 'grep -C 3 /etc/shadow /proc/meminfo' 'RAN grep -C 3 /etc/shadow /proc/meminfo'
deny  'cat /etc/shadow'
deny  'cat /etc/config/wireless'
deny  'cat /proc/../etc/shadow'
deny  'cat /proc/self/root/etc/shadow'
deny  'cat /proc/self/cwd/sakina-ssh'
deny  'cat /proc/1/environ'
deny  'cat /proc/self/mem'
deny  'cat proc/meminfo'
deny  'cat /proc/meminfo; id'
deny  'cat /proc/meminfo && reboot'
deny  'cat $(id)'
deny  'cat `id`'
deny  'head -- -n /etc/shadow'
deny  'grep root /etc/shadow'
deny  'grep -e root /etc/shadow'
deny  'grep -f /etc/shadow /proc/meminfo'
deny  'grep -f/etc/shadow /proc/meminfo'
deny  'grep --file=/etc/shadow /proc/meminfo'
deny  'grep -rf /etc/config/wireless /proc/meminfo'
deny  'grep -R key /proc/self/root/etc'
deny  'grep -d recurse key /proc/self/root/etc'
allow 'grep -eroot /proc/meminfo' 'RAN grep -eroot /proc/meminfo'
allow 'grep -in -A 2 error /proc/meminfo' 'RAN grep -in -A 2 error /proc/meminfo'
deny  'wc --files0-from=/etc/shadow'
deny  'wg show'
deny  'tailscale status'
deny  'dmesg'
deny  'reboot'
deny  'poweroff'
deny  'sh'
deny  'ash -c id'
deny  '/bin/sh -c id'
deny  'rm -rf /'
deny  'sysupgrade -n /tmp/x.bin'
deny  'opkg install x'
deny  'echo hi > /etc/passwd'
deny  'logread -e "unterminated'
deny  "uptime${nl}reboot"
out=$(run_ssh ''); rc=$?
check "an empty command prints the usage [$rc]" [ $rc -eq 1 ]
out=$(run_ssh 'help'); rc=$?
check "help lists the ubus read methods" [ $rc -eq 0 ]
case $out in *"network.interface.* status"*) ok ;; *) bad "help lacks the ubus list" ;; esac

# priv key (root)
export STUB_UID=0
allow 'wg show' 'RAN wg show'
allow 'wg show wg0 latest-handshakes' 'RAN wg show wg0 latest-handshakes'
deny  'wg show wg0 private-key'
deny  'wg show wg0 preshared-keys'
deny  'wg show all dump'
deny  'wg showconf wg0'
deny  'wg set wg0 peer x remove'
allow 'tailscale status --json' 'RAN tailscale status --json'
allow 'tailscale ip -4' 'RAN tailscale ip -4'
deny  'tailscale up'
deny  'tailscale status --web'
deny  'tailscale logout'
allow 'dmesg' 'RAN dmesg'
deny  'dmesg -c'
deny  'dmesg -n 1'
allow 'uci show network' 'RAN uci show network'
allow 'ubus call system info' 'RAN ubus call system info'
deny  'ubus call system reboot'
deny  'cat /proc/meminfo'
deny  'grep x /proc/meminfo'
deny  'apk add x'
export STUB_UID=1000

# secret masking
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
out=$(STUB_OUT=$work/uci.out run_ssh 'uci show')
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
out=$(STUB_OUT=$work/ubus.out run_ssh 'ubus call system board')
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

# source check
from_case() { # from_case <list> <client address> <expected: yes|no>
  echo "$1" > "$from_file"
  out=$(client="$2 40000 22" run_ssh uptime); rc=$?
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
echo '192.0.2.0/24' > "$from_file"
out=$(cd "$work" && SSH_CLIENT='' SSH_ORIGINAL_COMMAND=uptime sh "$work/sakina-ssh" 2>&1); rc=$?
check "no SSH_CLIENT is refused [$rc]" [ $rc -eq 2 ]
mv "$from_file" "$from_file.x"
out=$(run_ssh uptime); rc=$?
check "a missing from list refuses everything [$rc]" [ $rc -eq 2 ]
mv "$from_file.x" "$from_file"

# temporary root session
future=$(date -u -d "@$(( $(date +%s) + 3600 ))" +%Y%m%d%H%M)
past=$(date -u -d "@$(( $(date +%s) - 60 ))" +%Y%m%d%H%M)
export STUB_UID=0
out=$(run_ssh 'echo "hi $((1+1))"' root "$future"); rc=$?
check "root session runs the command before expiry [$rc $out]" [ $rc -eq 0 ] && [ "$out" = "hi 2" ]
check "root session record is cleared when it ends" [ -z "$(ls "$work/run")" ]
out=$(run_ssh 'echo hi' root "$past"); rc=$?
check "root session after expiry is refused [$rc $out]" [ $rc -eq 2 ] && [ "${out#*hi}" = "$out" ]
out=$(run_ssh 'echo hi' root 2026); rc=$?
check "root session with a bad stamp is refused [$rc]" [ $rc -eq 2 ]
out=$(client='203.0.113.1 4000 22' run_ssh 'echo hi' root "$future"); rc=$?
check "root session from outside the list is refused [$rc]" [ $rc -eq 2 ]
export STUB_UID=1000
out=$(run_ssh 'echo hi' root "$future"); rc=$?
check "root session as a normal user is refused [$rc]" [ $rc -eq 2 ]

# ---------------------------------------------------------------- main script

mstub=$work/main-bin
mkdir -p "$mstub"
printf '#!%s/sh\n[ "$1" = -u ] && echo 0\n' "$FARM" > "$mstub/id"
for c in logger killall; do
  printf '#!%s/sh\necho "%s $*" >> "%s"\n' "$FARM" "$c" "$calls" > "$mstub/$c"
done
cat > "$mstub/uci" <<EOF
#!$FARM/sh
echo "dropbear.main=dropbear"
echo "dropbear.main.RootLogin='\${STUB_ROOTLOGIN:-1}'"
EOF
cat > "$mstub/curl" <<'EOF'
#!/bin/sh
[ -n "${STUB_DOWNLOAD:-}" ] || exit 22
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
cp "$STUB_DOWNLOAD" "$out"
EOF
sed -i "1s|.*|#!$FARM/sh|" "$mstub/curl"
chmod +x "$mstub"/*

ro_blob=$(sed -n "s/^RO_KEY='ssh-ed25519 \(.*\)'$/\1/p" "$script")
priv_blob=$(sed -n "s/^PRIV_KEY='ssh-ed25519 \(.*\)'$/\1/p" "$script")
root_blob=$(sed -n "s/^ROOT_KEY='ssh-ed25519 \(.*\)'$/\1/p" "$script")
other_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOther admin@laptop'

fresh() { # a new fake router
  h=$work/host
  rm -rf "$h"; : > "$calls"
  mkdir -p "$h/etc/dropbear" "$h/etc/crontabs" "$h/etc/init.d" "$h/usr/sbin" "$h/usr/share/acl.d" "$h/var/run"
  printf 'root:x:0:0:root:/root:/bin/ash\nnetwork:*:101:101:network:/var:/bin/false\nold:x:59000:59000::/home/old:/bin/ash\n' > "$h/etc/passwd"
  printf 'root:x:0:\nnetwork:x:101:\nold:x:59000:\n' > "$h/etc/group"
  printf 'root:$1$x$y:20000:0:99999:7:::\n' > "$h/etc/shadow"
  echo /bin/ash > "$h/etc/shells"
  printf '%s\n' "$other_key" > "$h/etc/dropbear/authorized_keys"
  chmod 600 "$h/etc/dropbear/authorized_keys"
  printf '## This file contains files and directories that should\n/etc/mything.conf' > "$h/etc/sysupgrade.conf"
  printf '#!%s/sh\necho "cron $*" >> "%s"\n' "$FARM" "$calls" > "$h/etc/init.d/cron"
  chmod +x "$h/etc/init.d/cron"
}
sa() { # sa <args...>: runs the script on the fake router
  SAKINA_ACCESS_ROOT=$h PATH="$mstub:$FARM" sh "$h/sakina-access-openwrt" "$@"
}
stage() { cp "$script" "$h/sakina-access-openwrt"; }
keys() { cat "$h/etc/dropbear/authorized_keys"; }
count() { grep -c -F -- "$1" "$h/etc/dropbear/authorized_keys"; }

# from list
fresh; stage
sa install >/dev/null 2>&1
check "install without a list is refused" [ $? -ne 0 ]
check "and writes nothing" [ ! -e "$h/etc/sakina-access" ] && [ ! -e "$h/usr/sbin/sakina-ssh" ]
sa install --from '192.0.2.1",command="/bin/sh' >/dev/null 2>&1
check "a list that could break out of the file is refused" [ $? -ne 0 ]
sa install --from '192.0.2.1 $(id)' >/dev/null 2>&1
check "a list with shell characters is refused" [ $? -ne 0 ]

# install
fresh; stage
printf 'restrict %s\n%s\n' "ssh-ed25519 $priv_blob old" "ssh-ed25519 $root_blob stale-unrestricted" >> "$h/etc/dropbear/authorized_keys"
out=$(sa install --from "192.0.2.1, 198.51.100.0/24
2001:db8::/32" 2>&1); rc=$?
check "install succeeds [$rc: $out]" [ $rc -eq 0 ]
check "the list is normalized and saved" [ "$(cat "$h/etc/sakina-access/from")" = "192.0.2.1,198.51.100.0/24,2001:db8::/32" ]
check "user added with the next free uid" grep -qx 'sakina:x:59001:59001:Sakina (read-only):/home/sakina:/bin/ash' "$h/etc/passwd"
check "group added" grep -qx 'sakina:x:59001:' "$h/etc/group"
check "no password" grep -qx 'sakina:\*:0:0:99999:7:::' "$h/etc/shadow"
check "read-only key line" [ "$(cat "$h/home/sakina/.ssh/authorized_keys")" = "restrict,command=\"/usr/sbin/sakina-ssh\" ssh-ed25519 $ro_blob sakina-readonly" ]
check "helper installed and executable" [ -x "$h/usr/sbin/sakina-ssh" ]
check "helper is the shown one" cmp -s "$h/usr/sbin/sakina-ssh" "$work/helper.orig"
check "ubus ACL installed" has "$h/usr/share/acl.d/sakina-access.json" '"user": "sakina"'
check "ubusd reloads the ACL" grep -q '^killall -HUP ubusd' "$calls"
check "priv key line" [ "$(count "restrict,command=\"/usr/sbin/sakina-ssh\" ssh-ed25519 $priv_blob sakina-access-priv")" -eq 1 ]
check "older lines with her keys are gone" [ "$(count "$root_blob")" -eq 0 ] && [ "$(count ' old')" -eq 0 ]
check "other keys are kept" [ "$(count "$other_key")" -eq 1 ]
check "key file stays 0600" [ -n "$(find "$h/etc/dropbear/authorized_keys" -perm 600)" ]
check "the script keeps a copy of itself" cmp -s "$h/usr/sbin/sakina-access" "$script"
check "daily update in root's crontab" grep -Eq '^[0-9]+ [0-9]+ \* \* \* /usr/sbin/sakina-access update >/dev/null 2>&1 # sakina-access-update$' "$h/etc/crontabs/root"
check "cron enabled and restarted" grep -q '^cron restart' "$calls"
for p in /usr/sbin/sakina-access /usr/sbin/sakina-ssh /etc/sakina-access/ /home/sakina/ /usr/share/acl.d/sakina-access.json; do
  check "sysupgrade keeps $p" grep -qxF "$p" "$h/etc/sysupgrade.conf"
done
check "sysupgrade.conf keeps its own lines" grep -qxF /etc/mything.conf "$h/etc/sysupgrade.conf"
check "install logs" grep -q '^logger -t sakina-access installed' "$calls"
case $out in *"Allowed from: 192.0.2.1,198.51.100.0/24,2001:db8::/32"*"Kept on sysupgrade: yes"*) ok ;; *) bad "status after install: $out" ;; esac
cp "$h/etc/crontabs/root" "$work/cron.before"
cp "$h/etc/sysupgrade.conf" "$work/sysupgrade.before"
cp "$h/etc/dropbear/authorized_keys" "$work/keys.before"
touch -d "2000-01-01" "$h/etc/dropbear/authorized_keys"
: > "$calls"
sa install >/dev/null 2>&1
check "reinstall reads the saved list" [ $? -eq 0 ]
check "reinstall adds no second user" [ "$(grep -c '^sakina:' "$h/etc/passwd")" -eq 1 ]
check "reinstall adds no second priv line" [ "$(count sakina-access-priv)" -eq 1 ]
check "reinstall keeps the update time" cmp -s "$h/etc/crontabs/root" "$work/cron.before"
check "reinstall adds no sysupgrade lines" cmp -s "$h/etc/sysupgrade.conf" "$work/sysupgrade.before"
check "reinstall restarts nothing" not grep -q -e '^cron' -e '^killall' "$calls"
check "reinstall leaves root's key file alone" [ -z "$(find "$h/etc/dropbear/authorized_keys" -newer "$work/keys.before")" ]

# grant, toggle, expiry
: > "$calls"
before=$(date +%s)
out=$(sa 3 2>&1); rc=$?
check "grant succeeds [$rc: $out]" [ $rc -eq 0 ]
stamp=$(sed -n "s/.*command=\"\/usr\/sbin\/sakina-ssh root \([0-9]*\)\" ssh-ed25519 $root_blob sakina-access-root-temp$/\1/p" "$h/etc/dropbear/authorized_keys")
lo=$(date -u -d "@$((before + 3 * 3600))" +%Y%m%d%H%M)
hi=$(date -u -d "@$(( $(date +%s) + 3 * 3600))" +%Y%m%d%H%M)
check "grant line expires in 3 hours [$stamp]" [ -n "$stamp" ] && [ "$stamp" -ge "$lo" ] && [ "$stamp" -le "$hi" ]
check "grant line has no forwarding" has "$h/etc/dropbear/authorized_keys" "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command=\"/usr/sbin/sakina-ssh root $stamp\""
exp_local=$(date -d "@$(( $(date -u -d "$(echo "$stamp" | sed 's/^\(....\)\(..\)\(..\)\(..\)\(..\)$/\1-\2-\3 \4:\5/')" +%s) ))" '+%M %H %d %m' 2>/dev/null)
read -r mi hh dd mo <<EOF
$exp_local
EOF
check "revoke runs at the expiry minute" grep -qx "${mi#0} ${hh#0} ${dd#0} ${mo#0} \* /usr/sbin/sakina-access off >/dev/null 2>&1 # sakina-access-expire" "$h/etc/crontabs/root"
check "update line kept" grep -q 'sakina-access-update$' "$h/etc/crontabs/root"
check "grant is logged" grep -q '^logger -t sakina-access root granted for 3h' "$calls"
case $out in *"Root: on, expires"*) ok ;; *) bad "status after grant: $out" ;; esac
sa 5 >/dev/null 2>&1
check "a second grant replaces the first" [ "$(count sakina-access-root-temp)" -eq 1 ] && [ "$(grep -c sakina-access-expire "$h/etc/crontabs/root")" -eq 1 ]

# a live root session: the helper's process and a child of it
mkdir -p "$work/sess" "$h/var/run/sakina-access"
printf 'sleep 300 &\nwait\n' > "$work/sess/sakina-ssh"
sh "$work/sess/sakina-ssh" &
sess=$!
sleep 0.3
echo "$sess" > "$h/var/run/sakina-access/root.$sess"
child=$(grep -l "^PPid:[[:space:]]*$sess$" /proc/[0-9]*/status 2>/dev/null | head -n1 | cut -d/ -f3)
: > "$calls"
out=$(sa 2>&1); rc=$?
check "toggle revokes an active grant [$rc]" [ $rc -eq 0 ] && [ "$(count root-temp)" -eq 0 ]
check "revoke removes the expiry cron line" not grep -q sakina-access-expire "$h/etc/crontabs/root"
check "revoke keeps the update line" grep -q sakina-access-update "$h/etc/crontabs/root"
check "revoke keeps the priv line" [ "$(count sakina-access-priv)" -eq 1 ]
sleep 0.2
check "revoke ends the recorded session" [ ! -d "/proc/$sess" ] || grep -q '^State:.*Z' "/proc/$sess/status"
check "and its child processes [$child]" [ -n "$child" ] && { [ ! -d "/proc/$child" ] || grep -q '^State:.*Z' "/proc/$child/status"; }
check "and its record" [ ! -e "$h/var/run/sakina-access/root.$sess" ]
kill -9 "$sess" "$child" 2>/dev/null
wait 2>/dev/null
echo 1 > "$h/var/run/sakina-access/root.1"
sa off >/dev/null 2>&1
check "a stale record never kills an unrelated process" [ -d /proc/1 ]
case $out in *"Root: off"*) ok ;; *) bad "status after revoke: $out" ;; esac
printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command="/usr/sbin/sakina-ssh root 202001010000" ssh-ed25519 %s sakina-access-root-temp\n' "$root_blob" >> "$h/etc/dropbear/authorized_keys"
sa install >/dev/null 2>&1
check "install clears an expired grant whose revoke was missed" [ "$(count root-temp)" -eq 0 ]

# RootLogin off
fresh; stage
STUB_ROOTLOGIN=0 sa install --from 192.0.2.1 >/dev/null 2>&1
check "with RootLogin off there is no priv line" [ "$(count sakina-access)" -eq 0 ]
STUB_ROOTLOGIN=off sa 2 >/dev/null 2>&1
check "and no temporary root" [ $? -ne 0 ] && [ "$(count sakina-access)" -eq 0 ]

# remove
fresh; stage
echo '0 5 * * * /usr/bin/other-job' > "$h/etc/crontabs/root"
cp "$h/etc/sysupgrade.conf" "$work/sysupgrade.orig"
cp "$h/etc/passwd" "$work/passwd.orig"; cp "$h/etc/group" "$work/group.orig"; cp "$h/etc/shadow" "$work/shadow.orig"
sa install --from 192.0.2.1 >/dev/null 2>&1
sa 4 >/dev/null 2>&1
: > "$calls"
out=$(sa remove 2>&1); rc=$?
check "remove succeeds [$rc: $out]" [ $rc -eq 0 ]
check "only the other key is left" [ "$(keys)" = "$other_key" ]
check "passwd restored" cmp -s "$h/etc/passwd" "$work/passwd.orig"
check "group restored" cmp -s "$h/etc/group" "$work/group.orig"
check "shadow restored" cmp -s "$h/etc/shadow" "$work/shadow.orig"
check "sysupgrade.conf restored" [ "$(cat "$h/etc/sysupgrade.conf")" = "$(cat "$work/sysupgrade.orig")" ]
check "other cron jobs kept, ours gone" [ "$(cat "$h/etc/crontabs/root")" = '0 5 * * * /usr/bin/other-job' ]
check "cron restarted" grep -q '^cron restart' "$calls"
check "ubusd reloads without the ACL" grep -q '^killall -HUP ubusd' "$calls"
for p in /home/sakina /usr/sbin/sakina-ssh /usr/sbin/sakina-access /usr/share/acl.d/sakina-access.json /etc/sakina-access /var/run/sakina-access; do
  check "remove deletes $p" [ ! -e "$h$p" ]
done
fresh; stage
sa install --from 192.0.2.1 >/dev/null 2>&1
sa remove >/dev/null 2>&1
check "a crontab with only our line is removed" [ ! -e "$h/etc/crontabs/root" ]

# ---------------------------------------------------------------- self-update

version() { # version <file> <name> [exit code of its install]
  printf '#!/bin/sh\n%s\necho "%s $*" >> "%s"\nexit %s\n' "$(sed -n 2p "$script")" "$2" "$calls" "${3:-0}" > "$1"
}
fresh; stage
sa install --from 192.0.2.1 >/dev/null 2>&1
version "$h/usr/sbin/sakina-access" OLD
cp "$h/usr/sbin/sakina-access" "$work/old"
: > "$calls"
upd() { SAKINA_ACCESS_ROOT=$h PATH="$mstub:$FARM" sh "$h/sakina-access-openwrt" update; }
upd >/dev/null 2>&1
check "failed download fails the update" [ $? -ne 0 ]
check "failed download keeps the current version" cmp -s "$h/usr/sbin/sakina-access" "$work/old"
check "failed download is logged" grep -q 'update: download failed' "$calls"
printf '#!/bin/sh\n%s\nif then\n' "$(sed -n 2p "$script")" > "$work/broken"
STUB_DOWNLOAD=$work/broken upd >/dev/null 2>&1
check "a download that fails sh -n is not installed" [ $? -ne 0 ] && cmp -s "$h/usr/sbin/sakina-access" "$work/old"
printf '<html>rate limited</html>\n' > "$work/html"
STUB_DOWNLOAD=$work/html upd >/dev/null 2>&1
check "a download without the header is not installed" [ $? -ne 0 ] && cmp -s "$h/usr/sbin/sakina-access" "$work/old"
sed 2d "$script" > "$work/noheader"
STUB_DOWNLOAD=$work/noheader upd >/dev/null 2>&1
check "the Linux script's header is not accepted" cmp -s "$h/usr/sbin/sakina-access" "$work/old"
out=$(STUB_DOWNLOAD=$work/old upd)
check "same version is left alone [$out]" [ "$out" = "Already up to date." ]
check "same version runs no install" not grep -q "OLD install" "$calls"
version "$work/new" NEW
STUB_DOWNLOAD=$work/new upd >/dev/null
check "new version is installed" cmp -s "$h/usr/sbin/sakina-access" "$work/new"
check "new version's install runs" grep -q "^NEW install$" "$calls"
check "new version is logged" grep -q 'update: installed the new version' "$calls"
version "$h/usr/sbin/sakina-access" OLD
version "$work/new" NEW 1
: > "$calls"
STUB_DOWNLOAD=$work/new upd >/dev/null 2>&1
check "a failed install fails the update" [ $? -ne 0 ]
check "a new version whose install fails is rolled back" cmp -s "$h/usr/sbin/sakina-access" "$work/old"
check "and the old version's install runs again" grep -q "^OLD install$" "$calls"
cp "$script" "$work/real"
STUB_DOWNLOAD=$work/real upd >/dev/null 2>&1
check "the real script passes the update checks and installs" [ $? -eq 0 ] && cmp -s "$h/usr/sbin/sakina-access" "$script"

# ---------------------------------------------------------------- real dropbear

if [ -n "$DB" ] && [ -x "$DB" ] && [ -n "$SSH_BIN" ] && [ -n "$KEYGEN" ]; then
  # dropbear refuses an authorized_keys file below a world-writable directory such as /tmp.
  s=$(mktemp -d "$HOME/.sakina-access-test.XXXXXX")
  trap 'rm -rf "$work" "$FARM" "$s"' EXIT
  for k in ro priv root expired; do "$KEYGEN" -q -t ed25519 -N '' -C "$k" -f "$s/$k"; done
  pub() { cut -d' ' -f2 "$s/$1.pub"; }
  echo '127.0.0.1,::1' > "$s/from"
  sed -e "s|^FROM_FILE=.*|FROM_FILE=$s/from|" -e "s|^RUN_DIR=.*|RUN_DIR=$s/run|" -e "s|/bin/ash|$FARM/ash|g" \
    -e "s|^export PATH=.*|export PATH=$hstub:$FARM|" "$work/helper.orig" > "$s/ro-helper"
  sed -e 's|^me=.*|me=0|' "$s/ro-helper" > "$s/root-helper"
  sed -e "s|^FROM_FILE=.*|FROM_FILE=$s/from-other|" "$s/ro-helper" > "$s/other-helper"
  echo '192.0.2.1' > "$s/from-other"

  # The key lines exactly as the script writes them, with test keys and helper paths.
  fresh; stage
  sa install --from 192.0.2.1 >/dev/null 2>&1
  sa 1 >/dev/null 2>&1
  ro_line=$(cat "$h/home/sakina/.ssh/authorized_keys")
  priv_line=$(grep sakina-access-priv "$h/etc/dropbear/authorized_keys")
  root_line=$(grep sakina-access-root-temp "$h/etc/dropbear/authorized_keys")
  expired_stamp=$(date -u -d "@$(( $(date +%s) - 120 ))" +%Y%m%d%H%M)
  {
    printf '%s\n' "$ro_line" | sed -e "s|$ro_blob|$(pub ro)|" -e "s|/usr/sbin/sakina-ssh|$BB sh $s/ro-helper|"
    printf '%s\n' "$priv_line" | sed -e "s|$priv_blob|$(pub priv)|" -e "s|/usr/sbin/sakina-ssh|$BB sh $s/other-helper|"
    printf '%s\n' "$root_line" | sed -e "s|$root_blob|$(pub root)|" -e "s|/usr/sbin/sakina-ssh|$BB sh $s/root-helper|"
    printf '%s\n' "$root_line" | sed -e "s|$root_blob|$(pub expired)|" -e "s|/usr/sbin/sakina-ssh|$BB sh $s/root-helper|" \
      -e "s|root [0-9]*\"|root $expired_stamp\"|"
  } > "$s/authorized_keys"
  chmod 600 "$s/authorized_keys"
  port=$((20000 + $(date +%s) % 20000))
  "$(dirname "$DB")/dropbearkey" -t ed25519 -f "$s/hostkey" >/dev/null 2>&1
  "$DB" -F -E -s -D "$s" -r "$s/hostkey" -p "127.0.0.1:$port" -P "$s/pid" > "$s/log" 2>&1 &
  dbpid=$!
  sleep 0.5
  over_ssh() { # over_ssh <key> <command> [ssh options...]: stdout only
    k=$1 c=$2; shift 2
    "$SSH_BIN" -F /dev/null -p "$port" -i "$s/$k" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 "$@" "$(id -un)@127.0.0.1" "$c" 2>/dev/null
  }
  out=$(over_ssh ro uptime)
  check "dropbear: read-only key runs its forced command [$out]" [ "$out" = "RAN uptime" ]
  out=$(over_ssh ro 'ubus call network.interface.wan down'); rc=$?
  check "dropbear: read-only key refuses a write [$rc $out]" [ $rc -eq 2 ]
  out=$(over_ssh ro '') ; rc=$?
  check "dropbear: no shell without a command [$rc]" [ $rc -eq 1 ]
  out=$(over_ssh priv uptime); rc=$?
  check "dropbear: a client outside the from list is refused [$rc $out]" [ $rc -eq 2 ]
  out=$(over_ssh root 'echo hi')
  check "dropbear: temporary root runs commands before expiry [$out]" [ "$out" = "hi" ]
  out=$(over_ssh expired 'echo hi'); rc=$?
  check "dropbear: temporary root after expiry is refused [$rc $out]" [ $rc -eq 2 ]
  over_ssh ro x -N -W 127.0.0.1:"$port" </dev/null >/dev/null; rc=$?
  check "dropbear: restrict blocks forwarding [$rc]" [ $rc -ne 0 ]
  out=$(printf 'SSH-2.0-x\n' | over_ssh root x -W 127.0.0.1:"$port" | head -c 7); rc=$?
  check "dropbear: no forwarding on the root key [$out]" [ "$out" != "SSH-2.0" ]
  # dropbear does not know from= and refuses the whole line, which is why the helper checks.
  printf 'from="127.0.0.1",command="%s sh %s/ro-helper" ssh-ed25519 %s from-test\n' "$BB" "$s" "$(pub ro)" > "$s/authorized_keys"
  over_ssh ro uptime >/dev/null; rc=$?
  check "dropbear: a from= option makes it refuse the key [$rc]" [ $rc -eq 255 ]
  grep -q "Bad public key options" "$s/log" || bad "dropbear: log does not show the refused from= option"
  kill "$dbpid" 2>/dev/null
  wait "$dbpid" 2>/dev/null
elif [ -n "${DROPBEAR:-}" ]; then
  bad "DROPBEAR=$DROPBEAR is not executable, or ssh/ssh-keygen are missing"
else
  echo "SKIP: no dropbear found, set DROPBEAR=/path/to/dropbear for the real dropbear checks"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
