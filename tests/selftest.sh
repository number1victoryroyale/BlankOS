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
check "zram swap active"            bash -c 'swapon --show=NAME --noheadings | grep -q zram'
check "violet console palette"      bash -c 'grep -q "vt.default_red=11,239" /proc/cmdline'
check "C/C++ toolchain works"       bash -c 'cd /tmp && printf "#include <iostream>\nint main(){std::cout<<\"hi\";}\n" > t.cc && g++ -O2 t.cc -o t && [[ $(./t) == hi ]]'
if command -v python3 > /dev/null; then
	check "python with ssl/sqlite/ctypes" python3 -c 'import ssl, sqlite3, ctypes, lzma, bz2, zlib'
else
	skip "python with ssl/sqlite/ctypes (not installed)"
fi
check "https certificate store"     test -s /etc/ssl/certs/ca-certificates.crt
check "gnupg and pacman with gpgme" bash -c 'gpg --version >/dev/null && ldd /usr/bin/pacman | grep -q libgpgme'

# The system stack from [extra] (milestone 3), when installed.
if pacman -Q blankos-system > /dev/null 2>&1; then
	check "NetworkManager connected"   bash -c 'for i in $(seq 45); do [[ $(nmcli -t -f STATE general) == connected* ]] && exit 0; sleep 1; done; nmcli general; nmcli device; exit 1'
	check "systemd-networkd handed over" bash -c '! systemctl is-active -q systemd-networkd.service || { systemctl list-units "systemd-networkd*" --no-pager; exit 1; }'
	check "Wi-Fi tools and regulatory db" bash -c 'iw --version && wpa_supplicant -v | head -1 && test -e /usr/lib/firmware/regulatory.db'
	check "polkit answers"             bash -c 'pkaction | grep -q org.freedesktop.NetworkManager'
	check "Vulkan driver (lavapipe)"   bash -c 'vulkaninfo --summary 2>&1 | tee /tmp/vk.txt | grep -qi llvmpipe || { cat /tmp/vk.txt; exit 1; }'
	check "Mesa GL/EGL via libglvnd"   bash -c 'test -e /usr/lib/libEGL_mesa.so.0 && test -e /usr/lib/libGLX_mesa.so.0 && test -e /usr/lib/libEGL.so.1'
	check "GPU drivers for old and new" bash -c 'for f in /usr/share/vulkan/icd.d/{intel,radeon,lvp}_icd.x86_64.json; do test -e $f || { echo missing $f; exit 1; }; done'
	check "Bluetooth stack"            bash -c 'bluetoothctl --version && test -x /usr/libexec/bluetooth/bluetoothd && grep -qx "Experimental = true" /etc/bluetooth/main.conf'
	check "PipeWire Bluetooth codecs"  bash -c 'for c in sbc aac lc3; do ls /usr/lib/spa-0.2/bluez5/libspa-codec-bluez5-$c.so || exit 1; done'
	# PipeWire refuses to run as root: the live user's (lingering) session
	check "PipeWire and WirePlumber run" bash -c 'u=$(id -u live) || exit 1
		aslive() { su live -s /bin/bash -c "XDG_RUNTIME_DIR=/run/user/$u $*"; }
		for i in $(seq 30); do
			aslive wpctl status 2>/dev/null | grep -q Audio && aslive systemctl --user -q is-active wireplumber.service && exit 0
			sleep 1
		done
		aslive systemctl --user status pipewire wireplumber --no-pager; exit 1'
	check "Flatpak with Flathub"       bash -c 'flatpak --version && flatpak remotes --system --columns=name | grep -qx flathub'
	check "firmware and microcode"     bash -c 'ls /usr/lib/firmware/intel/iwlwifi/ /usr/lib/firmware/amdgpu/ /usr/lib/firmware/intel/sof* >/dev/null && ls /boot/intel-ucode.img /boot/amd-ucode.img || ls /run/live/medium/boot/intel-ucode.img'
	# (VMs may have no USB bus at all, so lsusb only has to be there)
	check "lspci and lsusb"            bash -c 'lspci | grep -qi "host bridge" && command -v lsusb'
fi

# The desktop (milestone 4), when installed: SDDM logs the live user into
# Plasma on Wayland.
if pacman -Q blankos-desktop > /dev/null 2>&1; then
	check "boots to graphical.target"  bash -c '[[ $(systemctl get-default) == graphical.target ]] && systemctl is-active -q graphical.target'
	check "SDDM running"               systemctl is-active -q sddm.service
	check "Plasma session for live"    bash -c 'for i in $(seq 120); do
			loginctl list-sessions --no-legend | grep -q " live " &&
				s=$(loginctl list-sessions --no-legend | awk "\$3 == \"live\" { print \$1; exit }") &&
				[[ $(loginctl show-session "$s" -p Type --value) == wayland ]] && exit 0
			sleep 1
		done; loginctl list-sessions; journalctl -b -u sddm --no-pager | tail -n 30; exit 1'
	check "KWin (Wayland) running"     bash -c 'for i in $(seq 120); do pgrep -u live -x kwin_wayland > /dev/null && exit 0; sleep 1; done; ps -u live -o pid,args; exit 1'
	check "Plasma shell running"       bash -c 'for i in $(seq 180); do pgrep -u live -x plasmashell > /dev/null && exit 0; sleep 1; done; ps -u live -o pid,args; journalctl -b --user-unit plasma-plasmashell --no-pager 2>/dev/null | tail -n 30; exit 1'
	check "KDE apps start"             bash -c 'su live -s /bin/bash -c "QT_QPA_PLATFORM=offscreen dolphin --version && QT_QPA_PLATFORM=offscreen konsole --version && QT_QPA_PLATFORM=offscreen kate --version"'
	check "Firefox installed"          bash -c '/usr/lib/firefox/firefox --version'
	check "default browser is Firefox" bash -c 'grep -qx "x-scheme-handler/https=firefox.desktop" /etc/xdg/mimeapps.list'
	check "xdg-desktop-portal-kde"     test -x /usr/lib/xdg-desktop-portal-kde
fi

# The gaming layer (milestone 5), when installed.
if pacman -Q blankos-gaming > /dev/null 2>&1; then
	check "Wine 64-bit WoW64 build"    bash -c 'wine --version | grep -q "^wine-" && test -d /usr/lib/wine/x86_64-windows && test -d /usr/lib/wine/i386-windows'
	check "NTSYNC device for Wine"     bash -c 'test -c /dev/ntsync && [[ $(stat -c %a /dev/ntsync) == 666 ]]'
	# starting a Wine prefix takes too long under plain emulation (no KVM)
	if [[ $(systemd-detect-virt) != qemu ]]; then
		check "Wine runs 64- and 32-bit"   bash -c 'su live -s /bin/bash -c "export WINEPREFIX=/tmp/wine-test WINEDEBUG=-all
			timeout 300 wineboot -i > /dev/null 2>&1
			timeout 120 wine cmd /c echo wine64-ok && timeout 120 wine C:/windows/syswow64/cmd.exe /c echo wine32-ok" 2>&1 | tee /tmp/wine.txt | grep -q wine32-ok || { cat /tmp/wine.txt; exit 1; }'
	else
		skip "Wine runs 64- and 32-bit (no KVM)"
	fi
	check "DXVK and VKD3D-Proton"      bash -c 'test -f /usr/share/dxvk/x64/d3d11.dll && test -f /usr/share/dxvk/x32/d3d9.dll && test -f /usr/share/vkd3d-proton/x64/d3d12.dll && command -v blankos-wine-dx'
	check "winetricks and cabextract"  bash -c 'winetricks --version && cabextract --version && 7z i > /dev/null'
	check "GameMode and MangoHud"      bash -c 'gamemoded --version && command -v gamemoderun && command -v mangohud && ls /usr/share/vulkan/implicit_layer.d/MangoHud*.json'
	check "controller drivers and rules" bash -c 'modinfo hid_xpadneo > /dev/null && ls /usr/lib/udev/rules.d/71-valve-gdu.rules && modinfo uinput > /dev/null'
	check "Game Hub self test"         bash -c 'su live -s /bin/bash -c "QT_QPA_PLATFORM=offscreen blankos-game-hub --self-test"'
fi

echo "SELFTEST-DONE failures=$fails"
exit $((fails > 0))
