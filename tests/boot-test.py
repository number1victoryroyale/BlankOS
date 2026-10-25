#!/usr/bin/env python3
"""Boot a BlankOS --test disk image in QEMU (UEFI) and run the in-guest
self test over the serial console.

    tests/boot-test.py out/image/blankos.img [--timeout 1200] [--log boot.log]

Exit status is 0 only if the guest reports "SELFTEST-DONE failures=0".
Uses KVM when /dev/kvm is usable, otherwise plain emulation (slow).
"""
import argparse, os, re, select, shutil, subprocess, sys, tempfile, time

OVMF_CODE = ["/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_CODE.fd",
             "/usr/share/edk2/x64/OVMF_CODE.4m.fd"]
OVMF_VARS = ["/usr/share/OVMF/OVMF_VARS_4M.fd", "/usr/share/OVMF/OVMF_VARS.fd",
             "/usr/share/edk2/x64/OVMF_VARS.4m.fd"]


def first(paths):
    for p in paths:
        if os.path.exists(p):
            return p
    sys.exit(f"none of {paths} exist (install ovmf)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--timeout", type=int, default=1200)
    ap.add_argument("--log", default="boot-test.log")
    ap.add_argument("--memory", default="4096")
    args = ap.parse_args()

    tmp = tempfile.mkdtemp()
    vars_copy = os.path.join(tmp, "vars.fd")
    shutil.copy(first(OVMF_VARS), vars_copy)
    kvm = os.access("/dev/kvm", os.R_OK | os.W_OK)
    cmd = ["qemu-system-x86_64", "-machine", "q35", "-m", args.memory,
           "-smp", str(min(4, os.cpu_count() or 1)),
           "-drive", f"if=pflash,format=raw,readonly=on,file={first(OVMF_CODE)}",
           "-drive", f"if=pflash,format=raw,file={vars_copy}",
           "-drive", f"file={args.image},if=virtio,format=raw,snapshot=on",
           "-nic", "user,model=virtio-net-pci",
           "-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot"]
    cmd += ["-enable-kvm", "-cpu", "host"] if kvm else ["-cpu", "max"]
    print(f"boot-test: {'KVM' if kvm else 'TCG (no KVM, slow)'}; timeout {args.timeout}s", flush=True)

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
