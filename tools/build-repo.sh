#!/bin/bash
# Build a BlankOS pacman repository inside the builder chroot.
#
#   sudo tools/build-repo.sh core [pkg ...]
#
# Packages are built in pkgs/<repo>/ORDER order with makepkg (as the
# unprivileged 'builder' user), written to $REPO_OUT/<repo>, added to the
# repo database, and installed into the builder so later packages build
# against them -- the same sequential flow as LFS chapter 8.
#
# A package whose exact pkgver-pkgrel already exists in $REPO_OUT/<repo>
# is not rebuilt, only (re)installed, so re-running after a failure or
# with a prefetched repo resumes where it left off.
#
# The builder root is $LFS (created by toolchain/build-toolchain.sh or
# extracted from builder-rootfs.tar.zst).
set -euo pipefail
source "$(dirname "$0")/../config/blankos.conf"
source "$BLANKOS_ROOT/tools/lib.sh"
need_root

repo=${1:?usage: build-repo.sh REPO [PKG...]}
shift
pkgroot=$BLANKOS_ROOT/pkgs/$repo
[[ -f $pkgroot/ORDER ]] || die "no $pkgroot/ORDER"
[[ -x $LFS/usr/bin/makepkg ]] || die "$LFS is not a builder root (no makepkg)"

if (($#)); then
	pkgs=("$@")
else
	mapfile -t pkgs < <(grep -v '^#' "$pkgroot/ORDER" | grep .)
fi

outdir=$REPO_OUT/$repo
logdir=$OUT/logs/$repo
mkdir -p "$outdir" "$logdir" "$SRC"
chown 1000:1000 "$outdir" "$logdir"

cleanup() { umount_vkfs "$LFS"; }
trap cleanup EXIT
mount_vkfs "$LFS"
for d in sources repo build/logs; do mkdir -p "$LFS/$d"; done
mountpoint -q "$LFS/sources"    || mount --bind -o ro "$SRC" "$LFS/sources"
mountpoint -q "$LFS/repo"       || mount --bind "$outdir" "$LFS/repo"
mountpoint -q "$LFS/build/logs" || mount --bind "$logdir" "$LFS/build/logs"

# Re-create the builder account (installing 'filesystem' replaces passwd).
ensure_builder() {
	in_chroot "$LFS" /bin/bash -c '
		grep -q "^builder:" /etc/group  || echo "builder:x:1000:" >> /etc/group
		grep -q "^builder:" /etc/passwd || echo "builder:x:1000:1000:BlankOS package builder:/home/builder:/bin/bash" >> /etc/passwd
		if [ -e /etc/shadow ] && ! grep -q "^builder:" /etc/shadow; then echo "builder:!:20000::::::" >> /etc/shadow; fi
		install -d -o 1000 -g 1000 /home/builder /build/pkg
		install -d /etc/pacman.d/hooks /var/lib/pacman /var/cache/pacman/pkg'
}

# makepkg wants a writable SRCDEST; give it a builder-owned directory of
# symlinks into the read-only source cache.
link_sources() {
	local d=$LFS/build/srcdest f
	install -d -o 1000 -g 1000 "$d"
	for f in "$SRC"/*; do
		ln -sfn "/sources/${f##*/}" "$d/${f##*/}"
	done
}

build_one() {
	local name=$1 dir=$pkgroot/$1 files f missing=()
	[[ -f $dir/PKGBUILD ]] || die "no PKGBUILD for $name"
	mapfile -t files < <(bash "$BLANKOS_ROOT/tools/pkgsrc.sh" info "$dir" | cut -d' ' -f2)
	for f in "${files[@]}"; do [[ -f $outdir/$f ]] || missing+=("$f"); done

	if ((${#missing[@]})); then
		msg "[$repo] building $name"
		bash "$BLANKOS_ROOT/tools/pkgsrc.sh" fetch "$dir"
		link_sources
		rm -rf "$LFS/build/pkg/$name"
		cp -rL "$dir" "$LFS/build/pkg/$name"
		chown -R 1000:1000 "$LFS/build/pkg/$name"
		local start=$SECONDS
		if ! chroot --userspec=1000:1000 "$LFS" /usr/bin/env -i \
			HOME=/home/builder TERM="${TERM:-xterm}" LANG=C.UTF-8 \
			PATH=/usr/bin:/usr/sbin \
			MAKEFLAGS="-j$JOBS" NINJAJOBS="$JOBS" \
			SRCDEST=/build/srcdest PKGDEST=/repo LOGDEST=/build/logs \
			BUILDDIR=/build/pkg/"$name"/work \
			/bin/bash -c "cd /build/pkg/$name && makepkg --cleanbuild --force --nodeps --noconfirm --log --nocolor" \
			> "$logdir/$name.makepkg.log" 2>&1; then
			tail -n 80 "$logdir/$name.makepkg.log"
			die "$name failed to build (logs in $logdir)"
		fi
		rm -rf "$LFS/build/pkg/$name"
		msg2 "$name built in $((SECONDS - start))s"
		for f in "${files[@]}"; do
			[[ -f $outdir/$f ]] || die "$name: makepkg did not produce $f"
		done
		in_chroot "$LFS" repo-add -q -R "/repo/$repo.db.tar.gz" "${files[@]/#//repo/}"
	else
		msg2 "[$repo] $name is up to date"
	fi

	# Install into the builder. --overwrite: the temporary system's files
	# are unowned and get replaced, just like LFS chapter 8 overwrites them.
	in_chroot "$LFS" pacman -U --noconfirm --needed --overwrite '*' -dd \
		"${files[@]/#//repo/}" > "$logdir/$name.install.log" 2>&1 ||
		{ cat "$logdir/$name.install.log"; die "installing $name into the builder failed"; }
	ensure_builder
}

ensure_builder
for p in "${pkgs[@]}"; do
	build_one "$p"
done
# Make sure the database lists every package (also after partial runs).
mapfile -t all < <(cd "$outdir" && ls -- *.pkg.tar.zst 2>/dev/null)
if ((${#all[@]})); then
	in_chroot "$LFS" repo-add -q -R "/repo/$repo.db.tar.gz" "${all[@]/#//repo/}" || true
fi
msg "[$repo] done: ${#pkgs[@]} packages"
