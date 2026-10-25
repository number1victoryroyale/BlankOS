#!/bin/bash
# Stage 0 of the BlankOS build: LFS chapters 4-7 plus the pacman bootstrap.
#
# Produces $OUT/builder-rootfs.tar.zst, a chroot-able temporary system with
# gcc, makepkg and pacman, which is what every package build runs inside.
# Re-running resumes from the last finished step (stamps in $LFS/.stamps).
#
# Usage: sudo toolchain/build-toolchain.sh
set -euo pipefail
source "$(dirname "$0")/../config/blankos.conf"
source "$BLANKOS_ROOT/tools/lib.sh"
need_root
umask 022

TC=$BLANKOS_ROOT/toolchain

host_check() {
	msg "Checking host requirements (LFS 2.2)"
	local missing=() t
	for t in bash bison gawk gcc g++ m4 make makeinfo patch perl python3 tar xz gzip; do
		command -v "$t" >/dev/null || missing+=("$t")
	done
	((${#missing[@]} == 0)) || die "missing host tools: ${missing[*]}"
	[[ $(readlink -f /bin/sh) == */bash ]] || die "/bin/sh must point to bash (LFS 2.2): ln -sf bash /bin/sh"
	echo 'int main(){}' | g++ -x c++ - -o /dev/null || die "host g++ is not working"
}

prepare_lfs() {
	msg "Preparing $LFS (LFS 4.2-4.3)"
	mkdir -pv "$LFS"/{etc,var} "$LFS"/usr/{bin,lib,sbin}
	for i in bin lib sbin; do
		[[ -e $LFS/$i ]] || ln -sv usr/$i "$LFS/$i"
	done
	mkdir -pv "$LFS/lib64" "$LFS/tools" "$LFS/.stamps" "$LFS/build/logs" "$LFS/blankos-toolchain"
	getent group lfs >/dev/null || groupadd lfs
	getent passwd lfs >/dev/null || useradd -s /bin/bash -g lfs -m -k /dev/null lfs
	chown -v lfs "$LFS"/{usr{,/*},var,etc,tools,lib64,.stamps,build,build/logs}
	install -m755 "$TC/stage-cross.sh" "$LFS/blankos-toolchain/"
}

run_cross() {
	msg "LFS chapters 5-6 (as user lfs)"
	runuser -u lfs -- env -i \
		HOME=/home/lfs TERM="${TERM:-xterm}" \
		LFS="$LFS" LC_ALL=POSIX LFS_TGT="$LFS_TGT" \
		PATH="$LFS/tools/bin:/usr/bin:/usr/sbin" \
		CONFIG_SITE="$LFS/usr/share/config.site" \
		MAKEFLAGS="-j$JOBS" \
		SRC="$SRC" WORK="$LFS/build/cross-work" \
		LOGS="$LFS/build/logs" STAMPS="$LFS/.stamps" \
		bash "$LFS/blankos-toolchain/stage-cross.sh"
}

run_chroot() {
	msg "LFS chapter 7 + pacman bootstrap (in chroot)"
	# 7.2: hand everything to root.
	chown --from lfs -R root:root "$LFS"/{usr,var,etc,tools,lib64,.stamps,build}
	install -m644 "$TC"/{chroot-lib.sh,chroot-ch7.sh,chroot-bootstrap.sh} "$LFS/blankos-toolchain/"
	install -m644 "$BLANKOS_ROOT/config/makepkg.conf" "$BLANKOS_ROOT/config/pacman-builder.conf" \
		"$LFS/blankos-toolchain/"

	mount_vkfs "$LFS"
	mkdir -p "$LFS/sources"
	mountpoint -q "$LFS/sources" || mount --bind -o ro "$SRC" "$LFS/sources"
	in_chroot "$LFS" /bin/bash /blankos-toolchain/chroot-ch7.sh
	in_chroot "$LFS" /bin/bash /blankos-toolchain/chroot-bootstrap.sh
	umount_vkfs "$LFS"
}

save_builder() {
	msg "Saving builder root filesystem"
	mkdir -p "$OUT"
	rm -rf "$LFS/build/work" "$LFS/build/cross-work"
	tar --zstd -cpf "$OUT/builder-rootfs.tar.zst.part" -C "$LFS" \
		--exclude=./sources --exclude=./proc/* --exclude=./sys/* \
		--exclude=./dev/* --exclude=./run/* .
	mv "$OUT/builder-rootfs.tar.zst.part" "$OUT/builder-rootfs.tar.zst"
	msg "Builder saved: $(du -h "$OUT/builder-rootfs.tar.zst" | cut -f1)"
}

trap 'umount_vkfs "$LFS"' EXIT

host_check
bash "$TC/fetch-sources.sh"
prepare_lfs
run_cross
run_chroot
save_builder
