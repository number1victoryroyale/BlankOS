# shellcheck shell=bash
# Helpers for scripts that run inside the builder chroot.
STAMPS=/.stamps
WORK=/build/work
LOGS=/build/logs
mkdir -p "$STAMPS" "$LOGS"
umask 022

msg() { printf '\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

# step TARBALL FUNC: extract /sources/TARBALL and run FUNC in its tree.
step() {
	local tarball=$1 fn=$2
	if [[ -e $STAMPS/$fn ]]; then
		msg "skip $fn (done)"
		return
	fi
	msg "$fn"
	rm -rf "$WORK" && mkdir -p "$WORK"
	tar -xf "/sources/$tarball" -C "$WORK"
	cd "$WORK"/*/ || exit 1
	local start=$SECONDS
	# errexit is ignored inside `if` conditions, so capture the status
	# explicitly to make every failing command abort the step.
	local rc
	set +e
	(set -e; "$fn") > "$LOGS/$fn.log" 2>&1
	rc=$?
	set -e
	if ((rc != 0)); then
		tail -n 60 "$LOGS/$fn.log"
		echo "FAILED: $fn (full log: $LOGS/$fn.log)" >&2
		exit 1
	fi
	cd /
	rm -rf "$WORK"
	touch "$STAMPS/$fn"
	msg "$fn done in $((SECONDS - start))s"
}

# The unprivileged account makepkg runs as. Package installs can replace
# /etc/passwd, so callers re-run this after every install.
ensure_builder() {
	grep -q '^builder:' /etc/group  || echo 'builder:x:1000:' >> /etc/group
	grep -q '^builder:' /etc/passwd || echo 'builder:x:1000:1000:BlankOS package builder:/home/builder:/bin/bash' >> /etc/passwd
	if [[ -e /etc/shadow ]] && ! grep -q '^builder:' /etc/shadow; then
		echo 'builder:!:19000::::::' >> /etc/shadow
	fi
	install -d -o 1000 -g 1000 /home/builder
}
