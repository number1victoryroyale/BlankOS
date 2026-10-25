#!/bin/bash
# Prepare an Ubuntu/Debian host (CI runner or dev box) for building BlankOS.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	bison gawk texinfo m4 g++ make patch perl python3 xz-utils zstd \
	curl ca-certificates file \
	qemu-system-x86 qemu-utils ovmf mtools dosfstools e2fsprogs fdisk xorriso squashfs-tools
# LFS 2.2: /bin/sh must be bash.
ln -sf bash /bin/sh
