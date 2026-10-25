#!/bin/bash
# Download every source tarball the toolchain stage needs into $SRC and
# verify it. LFS book sources are checked against the book's md5sums;
# everything else against toolchain/extra-sources.txt (sha256).
#
# If an upstream URL fails, the official LFS package mirror is tried
# ($LFS_MIRROR), which carries every file in the book's wget-list.
set -euo pipefail
source "$(dirname "$0")/../config/blankos.conf"
source "$BLANKOS_ROOT/tools/lib.sh"

LFS_MIRROR="${LFS_MIRROR:-https://mirror.koddos.net/lfs/lfs-packages/$LFS_BOOK}"

mkdir -p "$SRC"
cd "$SRC"
failed=()

fetch() {
	local url=$1 f
	f=$(basename "$url")
	download "$url" "$f" && return 0
	warn "upstream failed for $f, trying LFS mirror"
	download "$LFS_MIRROR/$f" "$f" && return 0
	failed+=("$url")
}

msg "Fetching LFS $LFS_BOOK sources into $SRC"
while read -r url; do
	[[ -z $url || $url == \#* ]] && continue
	fetch "$url"
done < "$BLANKOS_ROOT/toolchain/lfs-$LFS_BOOK/wget-list"

msg "Fetching extra sources"
while read -r sum url; do
	[[ -z $sum || $sum == \#* ]] && continue
	fetch "$url"
done < "$BLANKOS_ROOT/toolchain/extra-sources.txt"

if ((${#failed[@]})); then
	printf '  %s\n' "${failed[@]}" >&2
	die "${#failed[@]} download(s) failed"
fi

msg "Verifying checksums"
md5sum -c --quiet "$BLANKOS_ROOT/toolchain/lfs-$LFS_BOOK/md5sums" || die "md5 mismatch"
grep -v '^#' "$BLANKOS_ROOT/toolchain/extra-sources.txt" | grep . |
	while read -r sum url; do echo "$sum  $(basename "$url")"; done |
	sha256sum -c --quiet || die "sha256 mismatch"

msg "All toolchain sources present and verified"
