#!/bin/bash
# shellcheck disable=SC2154  # PKGBUILD variables come from `source ./PKGBUILD`
# Host-side source handling for PKGBUILDs. Builds run offline inside the
# builder chroot, so every remote source is downloaded into $SRC first.
#
#   tools/pkgsrc.sh fetch pkgs/core/zlib ...   download sources into $SRC
#   tools/pkgsrc.sh sums  pkgs/core/zlib ...   rewrite sha256sums=() from them
#   tools/pkgsrc.sh info  pkgs/core/zlib       print "pkgname pkgfile" lines
#   tools/pkgsrc.sh check pkgs/core/*          verify sums of in-tree (local) sources
set -euo pipefail
source "$(dirname "$0")/../config/blankos.conf"
source "$BLANKOS_ROOT/tools/lib.sh"

LFS_MIRROR="${LFS_MIRROR:-https://mirror.koddos.net/lfs/lfs-packages/$LFS_BOOK}"
BLFS_MIRROR="${BLFS_MIRROR:-https://mirror.koddos.net/blfs/${BLFS_BOOK:-13.1}}"
# filename -> alternate source, for files whose upstream host may be
# unreachable (see the header of that file)
ALT_SOURCES=$BLANKOS_ROOT/tools/source-mirrors.txt

# Print "<filename>\t<url>" for each source entry ("-" url = local file).
list_sources() (
	cd "$1"
	# shellcheck disable=SC1091
	source ./PKGBUILD
	local s name url
	for s in "${source[@]}"; do
		if [[ $s == *::* ]]; then
			name=${s%%::*} url=${s#*::}
		else
			url=$s name=${s##*/}
		fi
		if [[ $url == *://* ]]; then
			printf '%s\t%s\n' "$name" "$url"
		else
			printf '%s\t-\n' "$name"
		fi
	done
)

# Upstream first, then the LFS/BLFS source mirrors (which keep every
# file of a book release, GitHub-hosted ones included), then an alternate
# from $ALT_SOURCES.
fetch_one() {
	local name=$1 url=$2 letter alt
	letter=$(tr '[:upper:]' '[:lower:]' <<< "${name:0:1}")
	download "$url" "$SRC/$name" && return 0
	download "$LFS_MIRROR/$name" "$SRC/$name" && return 0
	download "$BLFS_MIRROR/$letter/$name" "$SRC/$name" && return 0
	download "$BLFS_MIRROR/Xorg/$name" "$SRC/$name" && return 0
	alt=$(awk -v n="$name" '$1 == n { $1 = ""; print substr($0, 2); exit }' "$ALT_SOURCES")
	[[ -n $alt ]] || return 1
	msg2 "  trying alternate source for $name"
	case $alt in
		git\ *) git_archive "$name" ${alt#git } ;;
		*) download "$alt" "$SRC/$name" ;;
	esac
}

# git_archive NAME REPO REF PREFIX: rebuild a GitHub tag or commit tarball
# the way GitHub does (git archive piped through gzip -n), for hosts that
# only allow git access. REF is a tag or a full commit id.
git_archive() {
	local name=$1 repo=$2 ref=$3 prefix=$4 tmp
	tmp=$(mktemp -d)
	git init -q --bare "$tmp/repo.git" &&
		git -C "$tmp/repo.git" fetch -q --depth 1 "$repo" "$ref" || { rm -rf "$tmp"; return 1; }
	git -C "$tmp/repo.git" -c tar.tar.gz.command="gzip -cn" archive --format=tar.gz \
		--prefix="$prefix" -o "$SRC/$name.part" FETCH_HEAD &&
		mv "$SRC/$name.part" "$SRC/$name"
	local rc=$?
	rm -rf "$tmp"
	return $rc
}

cmd_fetch() {
	mkdir -p "$SRC"
	local dir name url failed=0
	for dir in "$@"; do
		while IFS=$'\t' read -r name url; do
			[[ $url == - ]] && continue
			[[ -s $SRC/$name ]] && continue
			msg2 "fetch $name"
			fetch_one "$name" "$url" || { warn "failed: $url"; failed=1; }
		done < <(list_sources "$dir")
	done
	return $failed
}

cmd_sums() {
	local dir name url f sums
	for dir in "$@"; do
		sums=()
		while IFS=$'\t' read -r name url; do
			if [[ $url == - ]]; then f=$dir/$name; else f=$SRC/$name; fi
			[[ -f $f ]] || die "$dir: missing source $name (run fetch first)"
			sums+=("'$(sha256sum "$f" | cut -d' ' -f1)'")
		done < <(list_sources "$dir")
		python3 - "$dir/PKGBUILD" "${sums[@]}" << 'EOF'
import re, sys
path, sums = sys.argv[1], sys.argv[2:]
text = open(path).read()
pad = "\n" + " " * len("sha256sums=(")
new = "sha256sums=(" + pad.join(sums) + ")"
text, n = re.subn(r"^sha256sums=\([^)]*\)", lambda m: new, text, count=1, flags=re.M)
assert n == 1, f"{path}: no sha256sums array"
open(path, "w").write(text)
EOF
	done
}

# Local sources live in git, so a stale checksum would otherwise only show
# up hours into a CI build. Positions follow source=() order.
cmd_check() {
	local dir name url i bad=0
	local -a sums
	for dir in "$@"; do
		mapfile -t sums < <(cd "$dir" && (
			# shellcheck disable=SC1091
			source ./PKGBUILD; printf '%s\n' "${sha256sums[@]}"))
		i=0
		while IFS=$'\t' read -r name url; do
			if [[ $url == - && ${sums[i]:-} != SKIP &&
				$(sha256sum "$dir/$name" | cut -d' ' -f1) != "${sums[i]:-}" ]]; then
				warn "$dir: checksum mismatch for $name (run: tools/pkgsrc.sh sums $dir)"
				bad=1
			fi
			i=$((i + 1))
		done < <(list_sources "$dir")
	done
	return $bad
}

cmd_info() (
	cd "$1"
	# shellcheck disable=SC1091
	source ./PKGBUILD
	local a=${arch[0]} n
	for n in "${pkgname[@]}"; do
		printf '%s %s\n' "$n" "$n-${epoch:+$epoch:}$pkgver-$pkgrel-$a.pkg.tar.zst"
	done
)

case ${1:-} in
	fetch) shift; cmd_fetch "$@" ;;
	sums)  shift; cmd_sums "$@" ;;
	info)  shift; cmd_info "$@" ;;
	check) shift; cmd_check "$@" ;;
	*) die "usage: $0 fetch|sums|info|check PKGDIR..." ;;
esac
