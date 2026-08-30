# StrykerApp QEMU Build Guide

> **Purpose:** Build a patched QEMU binary for StrykerApp that fixes Xiaomi USB passthrough.
> **Status:** Analysis complete — build script needs refinement based on binary diff.

---

## 1. The Problem

**Stock StrykerApp QEMU binary → USB works ✅**
**Rebuilt QEMU binary → USB fails ❌ ("can't attach to VM")**

This is a 64-bit problem. The Xiaomi max packet error (ep0 maxpacket: 64) is a separate issue that we've already fixed in our patch.

---

## 2. StrykerApp Architecture (Rootless Mode)

### Binaries
| File | Source | Purpose |
|---|---|---|
| `qemu-system-aarch64` | Vanilla QEMU 11.0.2 | VM emulator |
| `libslirp.so` | libslirp | User-mode networking |
| `Image` | Custom kernel | Linux kernel |
| `initrd.img` | Custom initrd | Bootstrap |
| `rootfs.imgz` | Debian trixie | Root filesystem |

### QEMU Command
```
qemu-system-aarch64
  -nodefaults
  -M virt,gic-version=3
  -cpu max,sve=off,pmu=off,pauth=off
  -accel tcg,thread=multi,tb-size=512
  -smp 4,sockets=1,cores=4,threads=1
  -m 4096
  -kernel Image -initrd initrd.img
  -append "root=/dev/vda ... init_on_alloc=0 nokaslr ..."
  -drive rootfs.img,cache=writeback,aio=threads
  -device qemu-xhci,id=usbhc0,p2=8,p3=8
  -device virtio-net-pci
  -device virtio-rng-pci
  -qmp unix:qmp.sock,server,nowait
```

### USB Attach Flow
```
Android UsbManager → openDevice() → fd
    ↓
QMP add-fd (SCM_RIGHTS) → QEMU receives fd
    ↓
QMP device_add usb-host → libusb_wrap_sys_device(fd)
    ↓
USB device accessible to guest
```

### Guest Agent (572 bytes socat script)
```
Port 1050: socat TCP-LISTEN:1050 EXEC:/bin/sh          → non-interactive
Port 1051: socat TCP-LISTEN:1051 EXEC:'bash -il',pty   → interactive PTY
```

---

## 3. Stock Binary Analysis

**See `STOCK-BINARY-ANALYSIS.md` for complete details.**

Key findings:
- QEMU 11.0.2 (vanilla source paths in binary)
- All USB features present (usb-host, usb-xhci, wrap_sys_device, etc.)
- Binary is 42MB (our build is ~52MB — different compilation)
- Source code confirms: `qemu-11.0.2/` paths = vanilla QEMU

---

## 4. Why Our Rebuild Breaks USB

### The 5 Patches We Add (That Stock Doesn't Have)

| Patch | Purpose | Risk |
|---|---|---|
| shm_open shim | Bionic compatibility | Low |
| PAC coroutine fix | Pixel 10 SIGILL | **HIGH — replaces sigsetjmp** |
| LIBUSB_NO_DEVICE_DISCOVERY | Skip enumeration | Medium |
| Xiaomi USB speed quirk | Fix maxpacket error | Low |
| ivshmem disabled | Bionic compatibility | Low |

**The PAC coroutine fix is the highest-risk patch.** It replaces `sigsetjmp`/`siglongjmp` with custom assembly. If libusb uses setjmp internally for error handling, this could break USB operations.

### What We DON'T Know

- Exact NDK version used by StrykerApp developer
- Exact libusb version in stock binary
- Exact configure flags (beyond what's inferred)
- Whether stock binary was built with AOSP build system

---

## 5. Build Strategy

### Phase 1: Minimal Build (Match Stock)

Build QEMU with **ZERO extra patches** (no PAC fix, no shm shim):

```bash
# Use NDK r27c
export NDK=/path/to/ndk
export CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang

# Clone QEMU 11.0.2
git clone --depth=1 --branch v11.0.2 https://github.com/qemu/qemu.git
cd qemu

# Apply ONLY Xiaomi USB fix and NO_DEVICE_DISCOVERY
# (skip PAC fix and shm shim for now)

./configure \
  --target-list=aarch64-softmmu \
  --enable-tcg --enable-slirp --enable-virtfs \
  --enable-libusb --enable-pie \
  --disable-docs --disable-gtk --disable-sdl --disable-vnc \
  --disable-vhost-user --disable-plugins \
  --with-coroutine=ucontext

make -j$(nproc)
```

### Phase 2: Add Patches One by One

1. Build without any patches → test USB
2. Add Xiaomi quirk → test USB
3. Add NO_DEVICE_DISCOVERY → test USB
4. Add shm shim → test USB
5. Add PAC fix → test USB ← **This is likely where it breaks**

### Phase 3: Binary Diff

Compare stock binary with our build:
```bash
# Extract symbols
nm -D stock-qemu > stock-symbols.txt
nm -D our-qemu > our-symbols.txt
diff stock-symbols.txt our-symbols.txt
```

---

## 6. Required Tools

- Docker (with buildx)
- NDK r27c (or matching version)
- ~10GB disk space
- StrykerApp source: https://github.com/zalexdev/strykerapp.git
- Stock binaries: https://github.com/zalexdev/strykerapp/releases/tag/rootless-main

---

## 7. Testing

### On Device
```bash
# Install patched binary
adb push qemu-system-aarch64 /data/data/com.zalexdev.stryker/files/rootless/

# Test USB
# 1. Plug WiFi adapter
# 2. Check QMP logs: adb logcat | grep -i usb
# 3. Check guest: dmesg | grep usb
```

### Success Criteria
- USB WiFi adapter enumerates in guest
- No "Invalid ep0 maxpacket" errors
- No "can't attach to VM" errors
- Network interface appears in guest (`ip link`)

---

## 8. Credits

- **StrykerApp:** zalexdev (rootless QEMU implementation)
- **Xiaomi USB fix:** OPX (custom QEMU patch)
- **Analysis:** Buffy (Codebuff) — August 2026
