# shellcheck shell=bash
# Shared helpers for BlankOS build scripts. Source after config/blankos.conf.

msg()  { printf '\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
msg2() { printf '\033[1;35m  ->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [[ $EUID -eq 0 ]] || die "this script must run as root"; }

# download URL DEST: fetch with retries (no-op if DEST already exists).
download() {
	local url=$1 dest=$2
	[[ -s $dest ]] && return 0
	local tries=0
	until curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 -o "$dest.part" "$url"; do
		tries=$((tries + 1))
		[[ $tries -ge 4 ]] && { rm -f "$dest.part"; return 1; }
		sleep $((2 ** tries))
	done
	mv "$dest.part" "$dest"
}

# Mount the virtual kernel filesystems into a root (LFS 7.3).
mount_vkfs() {
	local root=$1
	mkdir -p "$root"/{dev,proc,sys,run}
	mountpoint -q "$root/dev"  || mount --bind /dev "$root/dev"
	mountpoint -q "$root/dev/pts" || mount -t devpts devpts -o gid=5,mode=0620 "$root/dev/pts"
	mountpoint -q "$root/proc" || mount -t proc proc "$root/proc"
	mountpoint -q "$root/sys"  || mount -t sysfs sysfs "$root/sys"
	mountpoint -q "$root/run"  || mount -t tmpfs tmpfs "$root/run"
	if [[ -h $root/dev/shm ]]; then
		install -d -m 1777 "$root$(realpath /dev/shm)"
	else
		mountpoint -q "$root/dev/shm" || mount -t tmpfs -o nosuid,nodev tmpfs "$root/dev/shm"
	fi
}

umount_vkfs() {
	local root=$1 m
	# Unmount everything below $root, deepest first.
	for m in $(findmnt -rno TARGET | grep "^$root/" | sort -r); do
		umount -l "$m" 2>/dev/null || true
	done
}

# Run a command inside the chroot with a clean environment.
in_chroot() {
	local root=$1; shift
	chroot "$root" /usr/bin/env -i \
		HOME=/root TERM="${TERM:-xterm}" \
		PATH=/usr/bin:/usr/sbin \
		MAKEFLAGS="-j$JOBS" NINJAJOBS="$JOBS" \
		"$@"
}
