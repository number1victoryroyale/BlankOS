#!/usr/bin/env python3
"""Boot a BlankOS --test disk image in QEMU (UEFI) and run the in-guest
self test over the serial console.

    tests/boot-test.py out/image/blankos.img [--timeout 1200] [--log boot.log]

Exit status is 0 only if the guest reports "SELFTEST-DONE failures=0".
Uses KVM when /dev/kvm is usable, otherwise plain emulation (slow).
--screenshot FILE.png saves the screen once the self test is done;
--after CMD runs a shell command in the guest after it (diagnostics).
"""
import argparse, os, re, select, shutil, socket, struct, subprocess, sys, tempfile, time, zlib

OVMF_CODE = ["/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_CODE.fd",
             "/usr/share/edk2/x64/OVMF_CODE.4m.fd"]
OVMF_VARS = ["/usr/share/OVMF/OVMF_VARS_4M.fd", "/usr/share/OVMF/OVMF_VARS.fd",
             "/usr/share/edk2/x64/OVMF_VARS.4m.fd"]


def first(paths):
    for p in paths:
        if os.path.exists(p):
            return p
    sys.exit(f"none of {paths} exist (install ovmf)")


def ppm_to_png(ppm, png):
    """Convert QEMU's binary PPM (P6) screendump to PNG."""
    data = open(ppm, "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            pos = data.index(b"\n", pos)
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    width, height = int(fields[1]), int(fields[2])
    pixels = data[pos + 1:]
    stride = width * 3
    raw = b"".join(b"\0" + pixels[y * stride:(y + 1) * stride] for y in range(height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
    with open(png, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def screendump(sock_path, png):
    """Ask the QEMU monitor for a screendump and save it as PNG."""
    ppm = png + ".ppm"
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock_path)
    s.settimeout(10)
    s.sendall(f"screendump {ppm}\n".encode())
    for _ in range(50):
        time.sleep(0.2)
        if os.path.exists(ppm) and os.path.getsize(ppm) > 0:
            time.sleep(1)
            break
    s.close()
    if os.path.exists(ppm):
        ppm_to_png(ppm, png)
        os.remove(ppm)
        print(f"boot-test: screenshot saved to {png}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--timeout", type=int, default=1200)
    ap.add_argument("--log", default="boot-test.log")
    ap.add_argument("--memory", default="4096")
    ap.add_argument("--cdrom", action="store_true", help="attach the image as a CD-ROM (live ISO)")
    ap.add_argument("--bios", action="store_true", help="boot with legacy BIOS (SeaBIOS) instead of UEFI")
    ap.add_argument("--no-kvm", action="store_true",
                    help="force software emulation (needed for --cpu to reject newer instructions)")
    ap.add_argument("--cpu", help="QEMU CPU model, e.g. core2duo to prove old laptops work "
                                  "(default: the host CPU with KVM, 'max' otherwise)")
    ap.add_argument("--screenshot", help="save the screen as this PNG file after the self test")
    ap.add_argument("--after", help="shell command to run in the guest after the self test (diagnostics)")
    args = ap.parse_args()

    tmp = tempfile.mkdtemp()
    vars_copy = os.path.join(tmp, "vars.fd")
    shutil.copy(first(OVMF_VARS), vars_copy)
    kvm = os.access("/dev/kvm", os.R_OK | os.W_OK) and not args.no_kvm
    cmd = ["qemu-system-x86_64", "-machine", "q35", "-m", args.memory,
           "-smp", str(min(4, os.cpu_count() or 1))]
    if not args.bios:
        cmd += ["-drive", f"if=pflash,format=raw,readonly=on,file={first(OVMF_CODE)}",
                "-drive", f"if=pflash,format=raw,file={vars_copy}"]
    if args.cdrom:
        cmd += ["-drive", f"file={args.image},media=cdrom,readonly=on", "-boot", "d"]
    else:
        cmd += ["-drive", f"file={args.image},if=virtio,format=raw,snapshot=on"]
    cmd += ["-nic", "user,model=virtio-net-pci",
           "-display", "none", "-serial", "stdio", "-no-reboot"]
    monitor = os.path.join(tmp, "monitor.sock")
    cmd += ["-monitor", f"unix:{monitor},server,nowait"] if args.screenshot else ["-monitor", "none"]
    cmd += ["-enable-kvm"] if kvm else []
    cmd += ["-cpu", args.cpu or ("host" if kvm else "max")]
    print(f"boot-test: {'BIOS' if args.bios else 'UEFI'}, {'cdrom' if args.cdrom else 'disk'}, "
          f"{'KVM' if kvm else 'TCG (no KVM, slow)'}, cpu {args.cpu or 'default'}; timeout {args.timeout}s", flush=True)

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log = open(args.log, "wb")
    buf = b""
    deadline = time.time() + args.timeout
    stage = "boot"
    result = None

    def send(s):
        proc.stdin.write(s.encode())
        proc.stdin.flush()

    while time.time() < deadline and proc.poll() is None:
        r, _, _ = select.select([proc.stdout], [], [], 1.0)
        if not r:
            continue
        chunk = os.read(proc.stdout.fileno(), 65536)
        if not chunk:
            break
        log.write(chunk)
        log.flush()
        sys.stdout.write(chunk.decode("utf-8", "replace"))
        sys.stdout.flush()
        buf = (buf + chunk)[-20000:]
        text = buf.decode("utf-8", "replace")
        # agetty announces "<host> login: root (automatic login)"; give the
        # shell a moment to print its prompt, then start the self test.
        if stage == "boot" and "(automatic login)" in text:
            stage = "shell"
            time.sleep(3)
            send("\n/usr/local/bin/blankos-selftest; echo SELFTEST-EXIT=$?\n")
        m = re.search(r"SELFTEST-DONE failures=(\d+)", text)
        if stage == "shell" and m:
            result = int(m.group(1))
            stage = "done"
            if args.screenshot:
                try:
                    screendump(monitor, os.path.abspath(args.screenshot))
                except OSError as e:
                    print(f"boot-test: screenshot failed: {e}", flush=True)
            if args.after:
                stage = "after"
                # quoted so the echoed command line does not match
                send(f"\n{args.after}; echo AFTER-'DONE'\n")
            else:
                stage = "poweroff"
        if stage == "after" and "AFTER-DONE" in text:
            stage = "poweroff"
        if stage == "poweroff":
            stage = "off"
            time.sleep(1)
            send("systemctl poweroff\n")
            deadline = min(deadline, time.time() + 120)
    if proc.poll() is None:
        proc.kill()
    log.close()
    shutil.rmtree(tmp, ignore_errors=True)

    if result is None:
        print(f"\nboot-test: FAILED - no self-test result (stage reached: {stage})")
        return 1
    print(f"\nboot-test: self test finished with {result} failure(s)")
    return 0 if result == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
