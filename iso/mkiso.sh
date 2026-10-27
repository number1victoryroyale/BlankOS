#!/bin/bash
# Build the BlankOS live ISO: a hybrid image that boots from CD/DVD and USB
# sticks on both BIOS and UEFI machines.
#
#   sudo iso/mkiso.sh [--test] [--pkgs "base linux grub blankos-system blankos-desktop blankos-gaming blankos-installer"]
#
# Layout of the ISO:
#   /boot/vmlinuz-linux, /boot/initramfs-live.img     kernel + live initramfs
#   /boot/grub/{grub.cfg,i386-pc/}                    BIOS GRUB (El Torito)
#   /efi.img                                          ESP with BOOTX64.EFI
#   /blankos/x86_64/rootfs.sfs                        the live root (squashfs)
# The initramfs mounts rootfs.sfs read-only with a tmpfs overlay on top.
#
# --test adds a root autologin on the serial console, the self test and
# console=ttyS0, for tests/boot-test.py. Never publish a --test ISO.
set -euo pipefail
source "$(dirname "$0")/../config/blankos.conf"
source "$BLANKOS_ROOT/tools/lib.sh"
need_root

test_iso=0
packages="base linux grub blankos-system blankos-desktop blankos-gaming blankos-installer"
while (($#)); do
	case $1 in
		--test) test_iso=1 ;;
		--pkgs) packages=$2; shift ;;
		*) die "unknown option $1" ;;
	esac
	shift
done

label=BLANKOS_LIVE
work=$OUT/iso
root=$work/root
stage=$work/stage
iso=$OUT/blankos-$(date -u +%Y.%m.%d)-x86_64.iso
rm -rf "$work"
mkdir -p "$root" "$stage"/{boot/grub,blankos/x86_64,EFI/BOOT}

cleanup() { umount_vkfs "$LFS"; }
trap cleanup EXIT
# shellcheck disable=SC2086
pacstrap_root "$root" $packages

msg "Configuring the live system"
cp -a "$BLANKOS_ROOT/iso/airootfs/." "$root/"
chroot "$root" /usr/bin/passwd -d root > /dev/null
# Unprivileged live user. Lingering starts its user manager at boot, so
# PipeWire (which refuses to run as root) is up even without a login
# session; the desktop will log this user in automatically.
if [[ -x $root/usr/bin/pipewire ]]; then
	chroot "$root" /usr/sbin/useradd -m -G wheel,audio,video,render,input -c "BlankOS live user" live
	chroot "$root" /usr/bin/passwd -d live > /dev/null
	install -d "$root/var/lib/systemd/linger"
	touch "$root/var/lib/systemd/linger/live"
fi
# Desktop: SDDM logs the live user straight into Plasma (Wayland); no
# screen locking, and admin actions (Discover, Flatpak) need no password.
if [[ -x $root/usr/bin/sddm ]]; then
	install -d "$root/etc/sddm.conf.d" "$root/etc/polkit-1/rules.d"
	printf '%s\n' '[Autologin]' 'User=live' 'Session=plasma' > "$root/etc/sddm.conf.d/50-live.conf"
	cat > "$root/etc/polkit-1/rules.d/49-live.rules" << "EOF"
// BlankOS live session: the live user may do admin tasks without a password
polkit.addRule(function(action, subject) {
	if (subject.user == "live") {
		return polkit.Result.YES;
	}
});
EOF
	install -d "$root/home/live/.config"
	printf '%s\n' '[Daemon]' 'Autolock=false' 'LockOnResume=false' > "$root/home/live/.config/kscreenlockerrc"
	# "Install BlankOS" on the live desktop
	if [[ -f $root/usr/share/applications/blankos-install.desktop ]]; then
		install -d "$root/home/live/Desktop"
		install -m755 "$root/usr/share/applications/blankos-install.desktop" "$root/home/live/Desktop/"
	fi
	chown -R --reference="$root/home/live" "$root/home/live/.config" "$root/home/live/Desktop" 2>/dev/null || true
fi
systemctl_preset_root "$root"
((test_iso)) && add_test_hooks "$root"

kver=$(basename "$(dirname "$(ls "$root"/usr/lib/modules/*/vmlinuz)")")
msg "Building the live initramfs for $kver"
mount_vkfs "$root"
chroot "$root" /usr/bin/blankos-mkinitramfs --live -k "$kver" -o /tmp/initramfs-live.img
umount_vkfs "$root"
install -m644 "$root/tmp/initramfs-live.img" "$stage/boot/initramfs-live.img"
install -m644 "$root/boot/vmlinuz-linux" "$stage/boot/vmlinuz-linux"
# CPU microcode goes first: the kernel applies it before anything else runs
initrd=''
for uc in intel-ucode amd-ucode; do
	if [[ -f $root/boot/$uc.img ]]; then
		install -m644 "$root/boot/$uc.img" "$stage/boot/$uc.img"
		initrd+="/boot/$uc.img "
	fi
done
initrd+=/boot/initramfs-live.img
# The installed-system initramfs is regenerated on install; don't ship it.
rm -f "$root"/tmp/initramfs-live.img "$root"/boot/initramfs-*.img

msg "Writing the boot menu"
palette=$(grep -v '^#' "$root/usr/share/blankos/console-palette.cmdline")
extra='' timeout=5
if ((test_iso)); then
	extra='console=tty0 console=ttyS0,115200'
	timeout=1
fi
sed -e "s|@LABEL@|$label|g" -e "s|@PALETTE@|$palette|" \
	-e "s|@EXTRA@|$extra|g" -e "s|@TIMEOUT@|$timeout|" -e "s|@INITRD@|$initrd|g" \
	"$BLANKOS_ROOT/iso/grub.cfg" > "$stage/boot/grub/grub.cfg"
# graphical menu (blankos-grub-theme), when installed in the live root
if [[ -f $root/usr/share/grub/themes/blankos/theme.txt ]]; then
	install -d "$stage/boot/grub/themes"
	cp -r "$root/usr/share/grub/themes/blankos" "$stage/boot/grub/themes/"
fi

msg "Building GRUB for BIOS and UEFI"
# BIOS: El Torito core image; the rest of the modules load from the ISO.
in_chroot "$LFS" grub-mkimage -O i386-pc-eltorito -p /boot/grub -o /tmp/eltorito.img \
	biosdisk iso9660 part_msdos part_gpt normal configfile search search_label \
	linux echo test all_video
install -d "$stage/boot/grub/i386-pc"
cp "$LFS"/usr/lib/grub/i386-pc/*.{mod,lst} "$stage/boot/grub/i386-pc/"
install -m644 "$LFS/tmp/eltorito.img" "$stage/boot/grub/i386-pc/eltorito.img"
install -m644 "$LFS/usr/lib/grub/i386-pc/boot_hybrid.img" "$work/boot_hybrid.img"

# UEFI: standalone GRUB that finds the medium by label and reads the
# shared grub.cfg from it.
cat > "$LFS/tmp/grub-early-iso.cfg" << EOF
search --no-floppy --set=root --label $label
set prefix=(\$root)/boot/grub
configfile (\$root)/boot/grub/grub.cfg
EOF
efi_mods="part_gpt part_msdos fat iso9660 search search_label normal configfile linux all_video echo test reboot halt gfxterm gfxmenu png font"
in_chroot "$LFS" grub-mkstandalone -O x86_64-efi -o /tmp/BOOTX64.EFI \
	--modules="$efi_mods" --install-modules="$efi_mods" \
	--locales= --fonts= --themes= \
	"boot/grub/grub.cfg=/tmp/grub-early-iso.cfg"
install -m644 "$LFS/tmp/BOOTX64.EFI" "$stage/EFI/BOOT/BOOTX64.EFI"
export MTOOLS_SKIP_CHECK=1
rm -f "$stage/efi.img"
# FAT image sized to the loader plus 1 MiB of slack (in KiB)
efi_kib=$(( ($(stat -c %s "$LFS/tmp/BOOTX64.EFI") / 1024 + 1024 + 511) / 512 * 512 ))
mkfs.vfat -C -n BLANKOS_EFI "$stage/efi.img" "$efi_kib" > /dev/null
mmd -i "$stage/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$stage/efi.img" "$LFS/tmp/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI

msg "Compressing the live root"
umount_vkfs "$LFS"
mksquashfs "$root" "$stage/blankos/x86_64/rootfs.sfs" \
	-comp zstd -Xcompression-level 15 -b 1M -noappend -no-progress -quiet
du -h "$stage/blankos/x86_64/rootfs.sfs" | cut -f1 | xargs printf '  -> rootfs.sfs: %s\n'

msg "Writing $iso"
rm -f "$iso"
# Same layout grub-mkrescue produces: El Torito BIOS + EFI images, GPT/MBR
# hybrid so the file can be dd'ed to a USB stick.
xorriso -as mkisofs -graft-points -r -J -joliet-long \
	-V "$label" -A "BlankOS live" -publisher "BlankOS" \
	-b boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 \
	-boot-info-table --grub2-boot-info --grub2-mbr "$work/boot_hybrid.img" \
	--efi-boot efi.img -efi-boot-part --efi-boot-image --protective-msdos-label \
	-o "$iso" "$stage" 2> "$work/xorriso.log" || { cat "$work/xorriso.log"; die "xorriso failed"; }
ln -sf "$(basename "$iso")" "$OUT/blankos-live.iso"
msg "ISO ready: $iso ($(du -h "$iso" | cut -f1))"
