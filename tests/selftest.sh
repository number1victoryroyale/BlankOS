#!/bin/bash
# BlankOS in-guest self test. Installed into --test images as
# /usr/local/bin/blankos-selftest and driven by tests/boot-test.py over the
# serial console. Prints one PASS/FAIL line per check and a final
# "SELFTEST-DONE failures=N" marker.
fails=0
check() {
	local name=$1; shift
	local out
	if out=$("$@" 2>&1); then
		echo "PASS $name"
	else
		echo "FAIL $name"
		printf '%s\n' "$out" | sed 's/^/     | /' | head -n 20
		fails=$((fails + 1))
	fi
}

skip() { echo "SKIP $1"; }
live=0
[[ $(findmnt -no FSTYPE /) == overlay ]] && live=1

check "os-release is BlankOS"       grep -q '^ID=blankos$' /etc/os-release
check "kernel is the BlankOS kernel" bash -c '[[ $(uname -r) == *-blankos ]]'
check "systemd reached running"     bash -c 'state=$(systemctl is-system-running --wait); echo "$state"; systemctl --failed --no-legend; [[ $state == running ]]'
check "root fs mounted rw"          bash -c 'findmnt -no OPTIONS / | grep -qw rw'
if ((live)); then
	check "live medium mounted"     findmnt /run/live/medium
	check "live squashfs mounted"   bash -c '[[ $(findmnt -no FSTYPE /run/live/sfs) == squashfs ]]'
else
	check "ESP mounted"             findmnt /boot/efi
fi
check "pacman database intact"      bash -c 'pacman -Q base linux systemd pacman >/dev/null && [[ -z $(pacman -Qkq 2>/dev/null) ]]'
check "dhcp address on ethernet"    bash -c 'for i in $(seq 30); do ip -4 -o addr show scope global | grep -q inet && exit 0; sleep 1; done; ip addr; exit 1'
check "en_US.UTF-8 locale"          bash -c 'locale -a | grep -qi "^en_US.utf8$"'
check "gaming sysctls applied"      bash -c '[[ $(sysctl -n vm.max_map_count) == 2147483642 ]]'
check "ntsync module available"     modinfo ntsync
check "violet console palette"      bash -c 'grep -q "vt.default_red=11,239" /proc/cmdline'
check "C/C++ toolchain works"       bash -c 'cd /tmp && printf "#include <iostream>\nint main(){std::cout<<\"hi\";}\n" > t.cc && g++ -O2 t.cc -o t && [[ $(./t) == hi ]]'
if command -v python3 > /dev/null; then
	check "python with ssl/sqlite/ctypes" python3 -c 'import ssl, sqlite3, ctypes, lzma, bz2, zlib'
else
	skip "python with ssl/sqlite/ctypes (not installed)"
fi
check "https certificate store"     test -s /etc/ssl/certs/ca-certificates.crt

echo "SELFTEST-DONE failures=$fails"
exit $((fails > 0))
