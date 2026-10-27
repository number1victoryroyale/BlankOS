#!/bin/bash
# check-libs.sh ROOT: fail if a program or library in ROOT needs (ELF
# NEEDED) a shared library that exists nowhere in ROOT: a runtime
# dependency missing from some PKGBUILD. Private libraries that programs
# load from their own directories (Firefox, Wine, systemd) count as
# present wherever they are, so this only catches libraries that are
# missing altogether. A second pass runs ldd (inside ROOT) on every program
# in /usr/bin, which also catches libraries in private directories that a
# missing RPATH leaves unreachable. (Not on plugins: those may rely on
# libraries their host program has already loaded.)
set -euo pipefail
root=${1:?usage: check-libs.sh ROOT}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# every shared library file name in the image
find "$root/usr/lib" \( -type f -o -type l \) -name '*.so*' -printf '%f\n' | sort -u > "$work/have"
# "file<TAB>needed" for every ELF file
find "$root/usr/bin" "$root/usr/lib" -type f \( -perm -u+x -o -name '*.so*' \) -print0 |
	while IFS= read -r -d '' f; do
		[[ $(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' ') == 7f454c46 ]] || continue
		readelf -d "$f" 2>/dev/null | sed -n "s|.*(NEEDED).*\[\(.*\)\]|${f#"$root"}\t\1|p"
	done > "$work/needs"

bad=0
while IFS=$'\t' read -r f lib; do
	if [[ $lib == /* ]]; then
		[[ -e $root$lib ]] && continue
	else
		grep -qxF "$lib" "$work/have" && continue
	fi
	printf '%s (%s) needs %s\n' "$f" "$(chroot "$root" /usr/bin/pacman -Qoq "$f" 2>/dev/null || echo '?')" "$lib"
	bad=1
done < "$work/needs"

while IFS= read -r f; do
	missing=$(chroot "$root" /usr/bin/ldd "$f" 2>/dev/null | awk '/not found/ { print $1 }' | sort -u | tr '\n' ' ')
	if [[ -n $missing ]]; then
		printf '%s (%s) cannot load %s\n' "$f" "$(chroot "$root" /usr/bin/pacman -Qoq "$f" 2>/dev/null || echo '?')" "$missing"
		bad=1
	fi
done < <(cut -f1 "$work/needs" | sort -u | grep '^/usr/bin/')
exit $bad
