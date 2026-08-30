# StrykerApp QEMU Build Guide

## এই ফাইলটা কেন গুরুত্বপূর্ণ

এই README পড়লে তুমি বুঝতে পারবে:
1. StrykerApp-এর rootless mode কিভাবে কাজ করে
2. আমাদের Xiaomi USB fix কী
3. QEMU binary কিভাবে build করতে হয়
4. StrykerApp-এর সাথে কীভাবে integrate করতে হয়

---

## ১. StrykerApp Rootless Mode Architecture

StrykerApp rootless mode-তে QEMU ব্যবহার করে Android-এ Linux VM চালাতে। এখানে:

### Binary Files (GitHub Release: `rootless-main`)
| File | Size | Description |
|---|---|---|
| `qemu-system-aarch64` | 41.77 MB | QEMU emulator (STOCK - no custom patches) |
| `libslirp.so` | 1.09 MB | User-mode networking |
| `Image` | 35.86 MB | Linux kernel |
| `initrd.img` | 36.53 MB | Initramfs |
| `rootfs.imgz` | 408.15 MB | Debian trixie rootfs (compressed ext4) |

### Terminal Path (Rootless Mode)
```
Non-interactive (port 1050):
  GuestExec.java → TCP 127.0.0.1:1050 → SLIRP → socat EXEC:/bin/sh

Interactive PTY (port 1051):
  GuestExec.java → TCP 127.0.0.1:1051 → SLIRP → socat EXEC:'bash -il',pty
```

### Guest Agent (`stryker-agentd`)
সবকিছু `socat` দিয়ে হয় (572 bytes shell script):
```sh
#!/bin/sh
SOCAT="$(command -v socat 2>/dev/null)"
"$SOCAT" TCP-LISTEN:1050,reuseaddr,fork EXEC:/bin/sh,stderr &
"$SOCAT" TCP-LISTEN:1051,reuseaddr,fork EXEC:'bash -il',pty,setsid,ctty,stderr &
wait
```

---

## ২. আমাদের Xiaomi USB Fix

### সমস্যা
Xiaomi/MIUI devices ভুল করে full-speed USB devices (12 Mbps) কে low-speed (1.5 Mbps) হিসেবে report করে। Guest Linux kernel `maxpacket = 64` দেখে low-speed device-কে reject করে:
```
usb 1-1: Invalid ep0 maxpacket: 64
```

### সমাধান
`xiaomi-usb-quirk.c` — QEMU-র `host-libusb.c`-তে inject করা হয়:
```c
if (udev->speed == USB_SPEED_LOW && xfer->actual_length >= 8 && r->cbuf[7] == 64) {
    udev->speed = USB_SPEED_FULL;
}
```

### কেন StrykerApp-এ এটা নেই
StrykerApp stock QEMU binary ব্যবহার করে। তাদের QEMU-তে কোনো custom patch নেই:
- ❌ Xiaomi USB speed quirk
- ❌ PAC coroutine fix (Pixel 10)
- ❌ LIBUSB NO_DEVICE_DISCOVERY

---

## ৩. QEMU Build Steps

### প্রয়োজনীয় Tools
- Docker (buildx সহ)
- ~10GB disk space
- Internet connection

### Build Command
```bash
# Clone StrykerApp
git clone https://github.com/zalexdev/strykerapp.git
cd strykerapp

# Copy build files (from this directory)
cp -r /path/to/stryker-build/* .

# Build QEMU with Xiaomi fix
docker build -t stryker-qemu-patched .

# Extract binary
docker create --name qemu-out stryker-qemu-patched /bin/true
docker cp qemu-out:/qemu-system-aarch64.so ./qemu-system-aarch64.so
docker cp qemu-out:/libslirp.so ./libslirp.so
docker rm qemu-out

# Binary ready!
ls -lh qemu-system-aarch64.so libslirp.so
```

### যা Build হয়
```
Input:  QEMU 11.0.2 source + patches
Output: qemu-system-aarch64.so (patched) + libslirp.so

Patches applied:
1. Xiaomi USB speed quirk (host-libusb.c)
2. PAC coroutine fix (coroutine-ucontext.c)
3. LIBUSB NO_DEVICE_DISCOVERY (host-libusb.c)
4. shm_open shim (Bionic API-26)
5. ivshmem disabled (Bionic)
6. 9p-marshal.h fix (Bionic)
```

---

## ৪. StrykerApp-এ Integrate করার পদ্ধতি

### Step 1: Patched Binary বিল্ড করো
```bash
docker build -t stryker-qemu-patched .
docker cp $(docker create stryker-qemu-patched):/qemu-system-aarch64.so ./qemu-system-aarch64.so
```

### Step 2: StrykerApp-এ Replace করো
```bash
# StrykerApp-এর rootless directory-তে replace করো
cp qemu-system-aarch64.so /data/data/com.zalexdev.stryker/files/rootless/qemu-system-aarch64
```

### Step 3: Test করো
```bash
# USB WiFi adapter plug করো
# Xiaomi device-তে "Invalid ep0 maxpacket: 64" error আসতে নেই
# WiFi adapter successfully enumerate করবে
```

---

## ৫. পার্থক্য: StrykerApp vs YourXDemon

| বিষয় | StrykerApp | YourXDemon |
|---|---|---|
| **Rootfs** | Debian trixie | Alpine 3.24 |
| **QEMU patches** | None (stock) | Custom (Xiaomi, PAC, LIBUSB) |
| **Build system** | No Dockerfile | Full Dockerfile |
| **Agent daemon** | socat (572B script) | socat (same now) |
| **Interactive PTY** | Port 1051 (socat) | Port 9051 (socat) |
| **Root required** | Yes (chroot + QEMU) | No (QEMU only) |

---

## ৬. Troubleshooting

### Build Fails
- Docker BuildKit সক্রিয় করো: `export DOCKER_BUILDKIT=1`
- Network সমস্যা: `docker build --network=host`

### USB Device Not Enumerating
- Xiaomi device: patched QEMU binary use করো
- Check QEMU logs: `adb logcat | grep -i usb`

### Agent Not Starting
- Check socat: `which socat` in guest
- Check ports: `ss -ltn | grep -E '1050|1051'`

---

## ৭. Known Issues (CRITICAL — Read This First)

### The Core Problem

**Stock StrykerApp QEMU binary → USB works ✅**
**Rebuilt QEMU binary (even same source) → USB fails ❌**

This happens on BOTH 64-bit AND 32-bit. The issue is NOT arm32 vs arm64.

### What Was Tried (OPXDemom v1.0.0 → v1.0.7)
1. ✅ armv7 rootfs provisioning (systemd-udevd, networkd, agentd)
2. ✅ Boot timeout fixes for slow devices
3. ✅ Permission flow fixes (Android 8-17)
4. ✅ Xiaomi USB speed quirk (ep0 maxpacket=64 fix)
5. ❌ Rebuilt QEMU → USB still fails on BOTH architectures

### Why Rebuild Breaks USB
Possible causes (need investigation):
- Build flags different from StrykerApp's build
- AOSP patches not properly applied
- libusb configured differently
- Missing QEMU features (usb-host, usbfs backend)
- QEMU version mismatch (8.2.7 vs 11.0.2)

### What Needs Investigation
1. Compare StrykerApp's stock QEMU binary build flags with our rebuild
2. Check if AOSP usbfs backend is enabled in our build
3. Verify QEMU configure output matches StrykerApp's expected config
4. Add QMP error logging to see EXACT failure point

**See OPXDemom docs/arm32-usb-next-steps.md for detailed debugging steps**

---

## ৮. Credits

- **StrykerApp**: zalexdev (original rootless QEMU implementation)
- **Xiaomi USB fix**: YourXDemon/OPX (custom QEMU patch)
- **PAC fix**: YourXDemon/OPX (coroutine shim for Pixel 10)
- **LIBUSB fix**: YourXDemon/OPX (NO_DEVICE_DISCOVERY for unprivileged Android)

---

*Generated by Buffy (Codebuff) — August 2026*
*For use in StrykerApp development sessions*
