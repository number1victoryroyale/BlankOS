#!/bin/bash
# GitHub Releases plumbing for CI. Each pacman repo is one release (tag =
# repo name) whose assets are the packages plus <repo>.db/<repo>.files, so
#   Server = https://github.com/<owner>/<repo>/releases/download/$repo
# works directly in pacman.conf. The builder rootfs lives in the 'builder'
# release, keyed by a hash of everything that affects the toolchain stage.
#
#   tools/ci-release.sh builder-key
#   tools/ci-release.sh fetch-builder            -> $OUT/builder-rootfs.tar.zst (exit 1 if absent)
#   tools/ci-release.sh publish-builder
#   tools/ci-release.sh fetch-repo REPO          -> $REPO_OUT/REPO/
#   tools/ci-release.sh publish-repo REPO
#
# Needs `gh` with GH_TOKEN set (contents: write for publish-*).
set -euo pipefail
source "$(dirname "$0")/../config/blankos.conf"
source "$BLANKOS_ROOT/tools/lib.sh"

builder_key() {
	(cd "$BLANKOS_ROOT" &&
		find toolchain config/blankos.conf config/makepkg.conf config/pacman-builder.conf -type f |
		LC_ALL=C sort | xargs sha256sum) | sha256sum | cut -c1-16
}

ensure_release() {
	local tag=$1 title=$2
	gh release view "$tag" > /dev/null 2>&1 ||
		gh release create "$tag" --title "$title" --prerelease \
			--notes "Managed by BlankOS CI. Assets are rewritten on every build." > /dev/null
}

case ${1:-} in
	builder-key)
		builder_key
		;;
	fetch-builder)
		key=$(builder_key)
		mkdir -p "$OUT"
		gh release download builder --pattern "builder-rootfs-$key.tar.zst" \
			--output "$OUT/builder-rootfs.tar.zst" --clobber 2> /dev/null ||
			{ msg2 "no builder for key $key"; exit 1; }
		msg2 "fetched builder $key"
		;;
	publish-builder)
		key=$(builder_key)
		ensure_release builder "Builder root filesystem"
		cp "$OUT/builder-rootfs.tar.zst" "$OUT/builder-rootfs-$key.tar.zst"
		gh release upload builder "$OUT/builder-rootfs-$key.tar.zst" --clobber
		# keep only the current builder
		gh release view builder --json assets -q '.assets[].name' |
			{ grep -vx "builder-rootfs-$key.tar.zst" || true; } |
			while read -r a; do gh release delete-asset builder "$a" --yes; done
		;;
	fetch-repo)
		repo=${2:?repo}
		mkdir -p "$REPO_OUT/$repo"
		if gh release view "$repo" > /dev/null 2>&1; then
			gh release download "$repo" --dir "$REPO_OUT/$repo" --clobber \
				--pattern '*.pkg.tar.zst' --pattern "$repo.db.tar.gz" --pattern "$repo.files.tar.gz" || true
		fi
		ls "$REPO_OUT/$repo" | wc -l | xargs printf '  -> %s files in [%s]\n' "$repo"
		;;
	publish-repo)
		repo=${2:?repo}
		dir=$REPO_OUT/$repo
		[[ -f $dir/$repo.db.tar.gz ]] || die "no database in $dir"
		ensure_release "$repo" "[$repo] package repository"
		# pacman fetches <repo>.db / <repo>.files; release assets can't be
		# symlinks, so upload real copies under both names.
		dbdir=$(mktemp -d)
		cp "$dir/$repo.db.tar.gz" "$dir/$repo.files.tar.gz" "$dbdir/"
		cp "$dir/$repo.db.tar.gz" "$dbdir/$repo.db"
		cp "$dir/$repo.files.tar.gz" "$dbdir/$repo.files"
		existing=$(gh release view "$repo" --json assets -q '.assets[].name')
		new=("$dbdir"/*)
		for f in "$dir"/*.pkg.tar.zst; do
			# packages are immutable per version: upload only new ones
			grep -qxF "${f##*/}" <<< "$existing" || new+=("$f")
		done
		((${#new[@]})) && gh release upload "$repo" "${new[@]}" --clobber
		# drop assets for package versions that are no longer in the repo
		{ grep '\.pkg\.tar\.zst$' <<< "$existing" || true; } | while read -r a; do
			[[ -f $dir/$a ]] || gh release delete-asset "$repo" "$a" --yes
		done
		rm -rf "$dbdir"
		msg2 "published [$repo]: ${#new[@]} files uploaded"
		;;
	*)
		die "usage: $0 builder-key|fetch-builder|publish-builder|fetch-repo REPO|publish-repo REPO"
		;;
esac
