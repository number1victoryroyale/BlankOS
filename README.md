# BlankOS

A gaming-focused Linux distribution built **from scratch** ([LFS 13.1, systemd edition](https://www.linuxfromscratch.org/lfs/)),
managed with **pacman**, heading for a **KDE Plasma 6** desktop with a dark + electric-violet (`#8B5CF6`) look.

Everything is built from this repository by GitHub Actions: the LFS toolchain, every package, the disk/ISO images, and
a QEMU boot test.

> **Status:** Milestone 1 (bootable console system) is done: built from scratch in GitHub Actions, published as the `core` pacman repo, and boot-tested in QEMU on every build. Next: the live ISO. See [the roadmap](#roadmap).

## How it's built

```
toolchain/   LFS ch. 5-7 (cross toolchain + temporary tools) and a pacman/makepkg bootstrap
             -> builder-rootfs.tar.zst: the chroot every package is built in
pkgs/core/   one PKGBUILD per package: LFS ch. 8 (+ kernel, pacman, BlankOS bits)
             ORDER = build order (same order as the book)
tools/       build-repo.sh (build a repo inside the builder), pkgsrc.sh (fetch sources,
             pin checksums), ci-release.sh (GitHub Releases as pacman repos)
image/       mkimage.sh: UEFI disk image from the [core] repo
tests/       boot-test.py + selftest.sh: boot the image in QEMU and check it
config/      makepkg.conf, build settings
```

1. **Toolchain stage.** The book's chapters 5–7 run unmodified (as the `lfs` user, then in a chroot). Pacman and makepkg
   are then bootstrapped inside that temporary system.
2. **Package stage.** From chapter 8 on, every package is a `PKGBUILD` built by `makepkg` as an unprivileged user and
   installed with `pacman -U`, one after another in book order. Each one overwrites the temporary tool it replaces, just
   as the book's `make install` does. The result is a pacman repository in which every file on the final system is
   owned by a package.
3. **Image stage.** A fresh root is created with `pacman --root … -S base linux grub`, then packed into a GPT disk
   (ESP + ext4) without using loop devices.
4. **Test stage.** QEMU boots the image with OVMF, logs in on the serial console and runs `tests/selftest.sh`. That
   checks systemd state, the pacman database, networking, locales, gaming sysctls, the C/C++ toolchain, Python modules
   and more.

### Build it yourself (Ubuntu/Debian host, root required)

```sh
sudo toolchain/host-prep.sh          # host packages, /bin/sh -> bash
sudo toolchain/build-toolchain.sh    # ~2-3 h on 4 cores; resumable
sudo tools/build-repo.sh core        # ~4-7 h; resumable, skips already-built packages
sudo image/mkimage.sh --test --pkgs "base base-devel linux grub"
sudo tests/boot-test.py out/image/blankos.img
```

Paths can be changed with `LFS=`, `SRC=` and `OUT=` (see `config/blankos.conf`).

### Cloud build

`.github/workflows/build.yml` runs `lint → toolchain → core (3 chained passes) → image + boot test`.

- **Packages:** published as release assets, one release per repo (tag `core`, …). Pacman uses them directly:
  `Server = https://github.com/<owner>/BlankOS/releases/download/$repo`.
- **Builder:** the builder rootfs is cached in the `builder` release, keyed by a hash of the toolchain inputs. It's only
  rebuilt when the toolchain changes.
- **Resuming:** each pass gets about 5.5 h. A pass that runs out of time publishes what it finished, and the next pass
  continues from there. After the first full build, a run only rebuilds packages whose `pkgver`/`pkgrel` changed.

> The first full build uses roughly 8–10 runner-hours. GitHub gives **public** repositories unlimited Actions minutes;
> private repositories only get the monthly quota of their plan.

## Decisions

| Area | Choice |
|---|---|
| Base | LFS 13.1 systemd book, merged `/usr` layout, x86-64-v2 compiler baseline |
| Packages | pacman 7.1 + makepkg, with Arch-style PKGBUILDs and package names |
| Kernel | Latest stable (7.3), built from Arch's config plus `pkgs/core/linux/config.blankos`: full preemption, 1000 Hz, NTSYNC for Wine |
| Desktop | KDE Plasma 6 (Wayland), SDDM, Calamares installer |
| Theme | Near-black base, electric violet `#8B5CF6` accent: GRUB, Plymouth, SDDM, Plasma, TTY |
| Gaming | Wine (WoW64), DXVK, VKD3D-Proton, gamemode, MangoHud, gamescope, Flatpak with Steam and Sober (Roblox) |
| GPU | Mesa (RADV/ANV/NVK) built in, and the NVIDIA open kernel module + userspace on the ISO, with PRIME offload for laptops |
| Browser | Firefox (official binary, repackaged), with a slot left for a custom browser |

## Roadmap

1. ~~Bootable console system: toolchain, pacman bootstrap, [core], UEFI disk image, CI boot test~~ ✅
2. Live ISO (dracut, GRUB BIOS+UEFI), TTY branding ← *next*
3. Graphics, audio and network stack: Wayland, Mesa, PipeWire, NetworkManager, BlueZ, Flatpak, GnuPG (signed packages)
4. Plasma 6, SDDM, KDE apps, Firefox
5. Gaming layer and the BlankOS Game Hub
6. Full branding and the Calamares installer
7. Hardware polish: NVIDIA/Optimus tuning, Turtle Beach Stealth 500 (Bluetooth first), the custom browser,
   and Dell / Lenovo (ThinkPad, Yoga, IdeaPad) laptop support: SOF audio firmware, power profiles, thermald,
   fwupd firmware updates, 2-in-1 rotation/tablet mode/pen, fingerprint login, battery charge limits

The full plan is in [docs/PLAN.md](docs/PLAN.md).

### Known gaps in Milestone 1

- **Unsigned packages:** pacman is built without gpgme until the GnuPG stack lands (milestone 3), so repos use
  `SigLevel = Never` for now.
- **Boot:** no initramfs yet; the root filesystem and storage drivers are built into the kernel. The image is UEFI only;
  BIOS boot comes with the ISO.
- **Disabled kernel features:** BTF/sched_ext and Rust kernel modules are off until pahole and rustc are packaged.
- **Missing pieces:** no PAM yet, and test suites (`check()`) are not run in CI.
