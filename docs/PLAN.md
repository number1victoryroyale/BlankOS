# BlankOS — Plan

## Context
The BlankOS repo is empty. The goal is a real, installable **gaming-focused Linux distro built from scratch (LFS)**, with this repo as its source of truth. GitHub Actions builds it in stages, publishes the packages, and boot-tests the result in QEMU.

**Decisions you made:**
- **Base:** LFS systemd book.
- **Desktop:** KDE Plasma 6 on Wayland.
- **Packages:** pacman.
- **Look:** dark with an electric-violet accent (`#8B5CF6`).
- **Install:** a live ISO with the Calamares installer.
- **Kernel:** latest stable.
- **GPU:** Mesa built in, NVIDIA as an optional package.
- **Apps:** Firefox, with a slot left for your own browser.
- **Gaming:** Wine plus Flatpak, with Steam and Sober (Roblox) from Flathub.
- **Headset:** Turtle Beach Stealth 500 PC support.

## How it works

**Building with pacman from the start.** The LFS cross toolchain and temporary tools (LFS ch. 5–7) are built with plain scripts. Pacman and makepkg are then bootstrapped inside that temporary chroot. From then on, **every package (LFS ch. 8 onward, all of BLFS, KDE, gaming) is a `PKGBUILD`** that gets built with makepkg and installed with pacman. That makes the OS updatable with `pacman -Syu` from day one.

**Repo layout:**
```
toolchain/        LFS ch.5-7 scripts + pacman bootstrap → "builder" rootfs tarball
pkgs/<repo>/<pkg>/PKGBUILD   repos: core, extra, desktop, gaming, blankos
versions.toml     pinned LFS/BLFS book version + upstream versions
tools/            build-pkg.sh (clean chroot build), deps-order.py (topo sort), repo-publish.sh
branding/         grub/, plymouth/, sddm/, plasma/ (global theme, colors, wallpapers, konsole),
                  tty/ (console palette, fastfetch logo, prompt), os-release
iso/              live ISO build: rootfs → squashfs, dracut (dmsquash-live), GRUB UEFI+BIOS hybrid
installer/        Calamares settings + BlankOS branding module
tests/            QEMU boot tests (serial-console smoke checks + screenshots)
.github/workflows/ staged build + publish + ISO + test
```

**Pacman repos:**
- **Hosting:** GitHub Releases, with one release tag per repo. Pacman reads straight from the release download URLs.
- **Signing:** packages are signed with a GPG key stored in GitHub Secrets, and a `blankos-keyring` package ships the key.

**Branding** is all in violet on near-black:
- GRUB theme
- Plymouth boot animation
- SDDM login screen
- Plasma global theme: color scheme, wallpapers, splash, Konsole profile
- Violet TTY palette
- fastfetch ASCII logo
- Shell prompt
- `/etc/os-release` that says `NAME="BlankOS"`

## Gaming layer (the main focus)

**Kernel:**
- Latest stable kernel, configured for gaming:
  - Full preemption and 1000 Hz timer.
  - `NTSYNC` (Wine's fast sync driver) and `sched_ext`.
  - zram swap and the BBR network setting.
  - All GPU drivers: amdgpu, i915/xe, nouveau.
- The `scx` schedulers (e.g. `scx_lavd`) come as an optional package.

**Graphics:**
- Mesa with RADV (AMD), ANV (Intel), NVK (NVIDIA open), Zink and lavapipe (lavapipe lets CI test Vulkan with no GPU).
- Vulkan loader and tools.
- **NVIDIA is first-class.** Your main machine is a laptop with a **Quadro RTX 5000 Max-Q** (Turing). I changed this from "optional" to **shipping NVIDIA on the ISO**, since otherwise BlankOS wouldn't game properly on your own machine:
  - **Driver:** `nvidia-open` kernel module (supports Turing) plus `nvidia-utils`, built by CI for every kernel update so they always match.
  - **Boot menu:** the GRUB menu has a "BlankOS (NVIDIA)" entry and an "open drivers" entry.
  - **Installer:** Calamares installs the NVIDIA packages automatically when it detects an NVIDIA GPU.
  - **Settings:** `nvidia-drm.modeset=1` for Wayland, and suspend/resume services that keep video memory across sleep.
  - **Flatpak:** Flatpak Steam and Sober pick up their matching NVIDIA runtime automatically.
- **Laptop hybrid graphics (Optimus).** These laptops usually pair an Intel iGPU with the NVIDIA card:
  - **PRIME render offload,** so the desktop runs on Intel to save battery and games run on NVIDIA.
  - **switcheroo-control,** so you can right-click a game and pick "Run on dedicated GPU" in KDE.
  - **`prime-run` wrapper** for Steam launch options.
  - **Power saving:** runtime power management (RTD3) for the NVIDIA card when the laptop supports it.
  - If your BIOS has a "discrete GPU only" switch, that mode works too.
- **Laptop basics:**
  - `power-profiles-daemon`, which hooks into KDE's battery applet with a "Performance" mode for gaming.
  - Touchpad via libinput.
  - Backlight control.
  - Wi-Fi and Bluetooth firmware.
  - Suspend/hibernate.

**Windows games and apps:**
- **Wine** in 64-bit WoW64 mode, so 32-bit Windows games work without a 32-bit Linux system. This needs a mingw-w64 cross compiler, which gets its own package.
- **winetricks**, plus **DXVK** and **VKD3D-Proton** for DirectX.

**Game tools:**
- gamemode
- MangoHud
- gamescope

**Steam and Roblox:**
- Flatpak with Flathub enabled.
- A **"BlankOS Game Hub"** first-boot app offers one-click installs of:
  - Steam (Flatpak, with Proton)
  - **Sober = Roblox** (`org.vinegarhq.Sober`)
  - Heroic, Lutris and ProtonUp-Qt
- Discover (KDE's app store) uses its Flatpak backend for games and apps.
- Note: Roblox blocks Wine, so Sober is the only working route. It's unofficial and can break whenever Roblox updates.

**Audio and controllers:**
- PipeWire and WirePlumber, tuned for low latency.
- BlueZ for Bluetooth.
- Valve's `steam-devices` udev rules (Flatpak Steam needs these for controllers) and `game-devices-udev`.
- `xpadneo` for Xbox Bluetooth controllers.

**Stealth 500 PC headset (over Bluetooth on the laptop, for now):**
- **Bluetooth stack:** BlueZ plus PipeWire/WirePlumber's Bluetooth support, with good codecs enabled:
  - **Listening:** SBC-XQ and AAC.
  - **Mic:** mSBC and LC3-SWB for wideband mic audio, plus LE Audio/LC3 if the headset supports it.
- The KDE Bluetooth tray (Bluedevil) handles pairing.
- **Automatic profile switching:** WirePlumber switches to headset mode (mic on) when a game or voice chat opens the mic, and back to high-quality music mode afterwards.
- **Classic Bluetooth limit:** while the mic is in use, game audio drops to "headset" quality. That's how Bluetooth works on every OS, not a BlankOS bug. The only way around it is LE Audio, and only if the Stealth 500 supports it, which I'll check when you test.
- **Battery level:** BlueZ's experimental battery reporting is enabled, so the headset's battery shows in KDE.
- **Bluetooth hardware:** firmware for the laptop's Wi-Fi/Bluetooth chip (Intel/Realtek/MediaTek) is included through a `linux-firmware` package.
- **Deferred:** making the USB transmitter work on the desktop (which has no Bluetooth). When you're home, boot any Linux live USB with the transmitter plugged in and send me `lsusb -v` + `dmesg`. From that I'll write a kernel quirk or udev helper package (`blankos-headset-turtlebeach`).

## Apps and browser
- Firefox, using Mozilla's official build wrapped as a `firefox-bin` package.
- Default browser is set through `/etc/xdg/mimeapps.list` and a `blankos-default-browser` meta package. **Your own browser** can be added later as a `PKGBUILD` and made the default by swapping that meta package. I'll need to know what it's built on (Electron, Chromium or Qt).
- KDE basics: Dolphin, Konsole, Kate, Spectacle, Ark, Gwenview, System Settings, Discover.
- **QtWebEngine is skipped**, because it can't be compiled within CI time limits.

## Cloud build (GitHub Actions, staged)

**Stages.** Chained jobs, each ≤6 h. Each stage pulls the previous packages from the releases and pushes its own:
1. `toolchain`: builds LFS ch. 5–7 and pacman, and uploads the builder tarball.
2. `core`: about 80 LFS packages plus the kernel.
3. `extra`: graphics, audio and network (Wayland, Mesa, LLVM, PipeWire, NetworkManager, BlueZ, Flatpak).
4. `desktop`: Qt6, KF6, Plasma 6, SDDM, Calamares.
5. `gaming`: mingw-w64, Wine, DXVK, gamemode, MangoHud, gamescope, NVIDIA packages.
6. `iso`: builds the live ISO and runs the `test` boot test.

**Incremental builds:** a package is rebuilt only when its `pkgver`/`pkgrel` changes, so after the first full build an update is cheap.

**Speed tricks:**
- Rust and the Firefox build come from official binaries instead of being compiled.
- ccache per stage.

**Tests:** QEMU boots the ISO with OVMF (UEFI) and with BIOS. Over the serial console, the checks are:
- `systemctl is-system-running`
- `pacman -Q`
- SDDM/KWin are up
- `vulkaninfo` through lavapipe
- `wine --version`
- Flatpak works

Screenshots of GRUB, Plymouth, SDDM and the desktop are uploaded as artifacts, and the ISO is attached to the release.

**Repo visibility:** the repo needs to be **public** for free, unlimited Actions minutes. Private repos get 2,000 minutes a month, which a full build would use up.

## Milestones (each is pushed to `claude/trusting-brown-27r6p2` and CI-verified before moving on)
1. Skeleton, toolchain stage, pacman bootstrap, core packages, and a console qcow2 that boots in QEMU in CI.
2. Live ISO (dracut, GRUB UEFI+BIOS) and TTY branding.
3. Graphics, audio and network stack.
4. Plasma 6, SDDM, KDE apps and Firefox.
5. Gaming layer and Game Hub.
6. Full branding: GRUB, Plymouth, SDDM, Plasma theme and Calamares.
7. Hardware polish on your laptop: NVIDIA/Optimus tuning, Stealth 500 over Bluetooth, and your own browser. The desktop USB transmitter fix comes after you're home.

**Not in the first version:** Secure Boot (you'll need to turn it off in your BIOS for now; signing can be added later), 32-bit multilib, and QtWebEngine.

**Total size:** about 600 packages. This is a multi-week project that I'll grind through milestone by milestone.

## Verification
- **Every milestone:** the CI QEMU boot test passes, and screenshots are attached to the run.
- **Milestone 1:** I run the toolchain scripts locally in this container first (shellcheck, plus the early stages), before CI.
- **Before release:** you boot the ISO from USB on your **laptop** and check:
  - Both GRUB entries (NVIDIA and open drivers).
  - `nvidia-smi`, and that "Run on dedicated GPU" works.
  - Sober/Roblox, a Steam game through Proton, and a Wine app, with MangoHud showing the NVIDIA GPU.
  - Stealth 500 pairing over Bluetooth, with the mic working in a voice chat.
  - Suspend/resume.

  That's the only real test for hardware and game performance.

## Addendum: Dell / Lenovo laptop support (requested after approval)
The kernel already has the vendor drivers (thinkpad_acpi, think-lmi, ideapad_laptop, lenovo-ymc,
dell-laptop/wmi/smbios/sysman, dell-smm-hwmon, intel/amd pstate, platform profiles, i2c-hid,
SOF audio, IPU6 cameras). Userspace follows with the stack it belongs to:
- milestone 3: sof-firmware, linux-firmware, microcode, power-profiles-daemon, thermald, fwupd
- milestones 4/6: iio-sensor-proxy (auto-rotate), tablet mode + on-screen keyboard, libwacom (pens),
  fprintd (fingerprint readers), Plasma battery charge limits
- milestone 7: hardware self-test covering these drivers on real Dell/Lenovo machines

## Addendum: old laptops and the Razer Blade 15
**Old laptops (a friend's machines):**
- Plain x86-64 compiler baseline instead of x86-64-v2: runs on every 64-bit CPU (Core 2, Athlon 64,
  early Pentium Dual-Core). CI proves it by booting the live ISO on an emulated Core 2 Duo. 32-bit-only
  CPUs (most pre-2006 laptops) cannot run BlankOS.
- Live ISO boots on legacy BIOS from CD and from USB sticks, as well as UEFI.
- zram swap (compressed RAM, half of RAM up to 8 GiB) on by default for 2-4 GB machines.
- Later: old GPUs through Mesa (Intel GMA/crocus, Radeon r300/r600, nouveau), Broadcom Wi-Fi
  (b43 firmware / broadcom-wl), Atheros/Realtek firmware via linux-firmware, a lighter Plasma profile.

**Razer Blade 15 (the user's laptop for now):**
- Kernel side already present: Intel/AMD pstate, i2c-hid precision touchpad, iwlwifi, SOF/HDA audio.
- NVIDIA RTX + Intel iGPU: same NVIDIA/PRIME offload plan as the Quadro laptop; MUX-switch models
  can run the NVIDIA GPU directly.
- Keyboard RGB, backlight and fan/performance modes: OpenRazer (kernel module built per kernel +
  daemon) with Polychromatic or OpenRGB as the GUI, in [gaming].
- Model-specific quirks (suspend, screen flicker, speaker routing) get DMI-matched entries in a
  blankos-hwquirks package once the exact model year is known.
