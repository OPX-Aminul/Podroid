# Xiaomi/MIUI USB Speed Correction — Issue #85 Fix

## Summary

Xiaomi/MIUI devices (e.g., Poco F1) misreport full-speed USB devices as low-speed
through their custom USB host controller driver. This causes the Linux kernel inside
the OPX VM to reject the device with:

```
usb 1-1: Invalid ep0 maxpacket: 64
usb usb1-port1: unable to enumerate USB device
```

**Root cause:** The host reports `USB_SPEED_LOW` but the device descriptor's
`bMaxPacketSize0` is 64 — which is impossible for a real low-speed device
(USB spec limits low-speed maxpacket to ≤8). The kernel correctly rejects this
as invalid.

**Fix:** Two-layer defense-in-depth:
1. **QEMU layer** — correct the speed before the guest ever sees it
2. **Kernel layer** — safety net that catches the mismatch in the guest

---

## Timeline of Changes

### 1. Initial Investigation (Issue #85 Research)

**File:** `Dockerfile` (kernel builder section)

The original kernel `hub.c` code:
```c
} else {
    /* Initial guess is wrong and descriptor's value is invalid */
    dev_err(&udev->dev, "Invalid ep0 maxpacket: %d\n", maxp0);
    retval = -EMSGSIZE;
    goto fail;
}
```

When `speed == USB_SPEED_LOW` and `maxpacket == 64`, the condition falls through
to this `else` block and the device is rejected.

### 2. First Kernel Patch Attempt (sed-based)

**File:** `Dockerfile` — kernel patch section

```dockerfile
RUN cd linux-${KERNEL_VERSION} \
    && sed -i '/Invalid ep0 maxpacket/i\
            /* Xiaomi/MIUI host stack bug... */\
            if (udev->speed == USB_SPEED_LOW &&\
                usb_endpoint_maxp(&udev->ep0.desc) == 64) {\
                ...\
                udev->speed = USB_SPEED_FULL;\
            } else' drivers/usb/core/hub.c
```

**Bug:** The `} else` only covered the `dev_err()` line. The critical lines:
```c
retval = -EMSGSIZE;
goto fail;
```
were OUTSIDE the `else` — they always executed, even when the Xiaomi fix matched.
The device was still rejected every time.

**Root cause of the bug:** The sed inserted code before `dev_err` and ended with
`} else`, but `retval = -EMSGSIZE; goto fail;` was not inside any conditional
branch. The code structure was:

```c
} else {
    if (speed == LOW && maxpacket == 64) {
        speed = FULL;         // ← fix applied
    } else
    dev_err(...)              // ← only this was in the else
retval = -EMSGSIZE;           // ← ALWAYS runs!
goto fail;                    // ← ALWAYS fails!
}
```

### 3. Second Kernel Patch (correct approach)

**File:** `build-tools/apply-kernel-patch.py` (Python script)
**File:** `Dockerfile` — kernel patch section

Replaced the broken sed with a Python script that does a precise text replacement.
The script replaces the entire `} else { ... error ... }` block with a proper
`else if` chain:

```python
# apply-kernel-patch.py
old_block = """\t} else {
\t\t/* Initial guess is wrong and descriptor's value is invalid */
\t\tdev_err(&udev->dev, "Invalid ep0 maxpacket: %d\\n", maxp0);
\t\tretval = -EMSGSIZE;
\t\tgoto fail;
\t}"""

new_block = """\t} else if (udev->speed == USB_SPEED_LOW &&
\t\t\ti == 64) {
\t\t/* Xiaomi/MIUI host stack bug: full-speed devices misreported
\t\t * as low-speed. Accept maxpacket=64 and treat as full-speed
\t\t * (low-speed maxpacket must be <=8 per USB spec) (issue #85).
\t\t */
\t\tudev->speed = USB_SPEED_FULL;
\t\tudev->ep0.desc.wMaxPacketSize = cpu_to_le16(i);
\t\tusb_ep0_reinit(udev);
\t} else {
\t\t/* Initial guess is wrong and descriptor's value is invalid */
\t\tdev_err(&udev->dev, "Invalid ep0 maxpacket: %d\\n", maxp0);
\t\tretval = -EMSGSIZE;
\t\tgoto fail;
\t}"""
```

**Dockerfile:**
```dockerfile
COPY build-tools/apply-kernel-patch.py /tmp/apply-kernel-patch.py
RUN cd linux-${KERNEL_VERSION} \
    && python3 /tmp/apply-kernel-patch.py \
    && grep -q 'Xiaomi/MIUI' drivers/usb/core/hub.c
```

**Why this works:** The new `else if` branch catches the Xiaomi case BEFORE
the error block. When `speed == LOW && i == 64`, the code:
1. Sets `speed = USB_SPEED_FULL`
2. Sets `wMaxPacketSize = 64`
3. Calls `usb_ep0_reinit(udev)` to reinitialize the endpoint
4. Falls through to `usb_get_device_descriptor()` — device is now accepted

When the condition does NOT match, the original `else` block handles the error
as before. The `goto fail` is never reached for the Xiaomi case.

### 4. QEMU USB Quirk

**File:** `build-tools/xiaomi-usb-quirk.c`

First version (too aggressive):
```c
/* Converts ALL low-speed to full-speed */
if (udev->speed == USB_SPEED_LOW) { udev->speed = USB_SPEED_FULL; }
```

This was wrong because it would break actual low-speed devices (keyboards, mice)
that legitimately have maxpacket ≤ 8.

**Fixed version:**
```c
/* Only corrects when descriptor shows maxpacket=64 (Xiaomi bug pattern) */
if (udev->speed == USB_SPEED_LOW && xfer->actual_length >= 8 && r->cbuf[7] == 64) {
    udev->speed = USB_SPEED_FULL;
}
```

**Inserted in:** `hw/usb/host-libusb.c` after the USB-3 maxpacket fixup line
`r->cbuf[7] = 64;` (in `usb_host_req_complete_ctrl`).

**How it works:**
1. `r->cbuf` contains the raw device descriptor from the host
2. `r->cbuf[7]` is `bMaxPacketSize0` (endpoint 0 max packet size)
3. `udev->speed` was set during device init from `speed_map[libusb_speed]`
4. On Xiaomi devices: `speed == LOW` but `cbuf[7] == 64` → mismatch
5. QEMU corrects `udev->speed = USB_SPEED_FULL` before the guest sees it
6. Guest kernel never encounters the invalid combination

### 5. Kernel Patch File (`kernel-hub-quirk.patch`)

Initially created as a unified diff, then replaced by the Python script because
the `patch` command is not installed in the `debian:bookworm` kernel-builder image.

The `patch` command failure:
```
/bin/sh: 1: patch: not found
exit code: 127
```

Solution: Use `python3` which is already present in the image.

---

## Files Modified

| File | What Changed | Why |
|------|-------------|-----|
| `Dockerfile` | Replaced sed-based kernel patch with Python script | sed approach had logic bug; `patch` not available |
| `build-tools/apply-kernel-patch.py` | **New file** — Python script for kernel hub.c patch | Reliable text replacement; tested locally |
| `build-tools/xiaomi-usb-quirk.c` | Added `r->cbuf[7] == 64` check | Was too aggressive; now only fixes Xiaomi bug |
| `.github/workflows/build.yml` | Existing — builds kernel + QEMU | Unchanged (only rebuilds when Dockerfile/build-tools change) |
| `.github/workflows/build-apk.yml` | Removed `push` trigger; uses `workflow_run` only | Prevents APK from building with old binaries |

---

## Root Cause Analysis

### Why does Xiaomi misreport USB speed?

The Xiaomi/MIUI custom USB host controller driver reports the device speed
incorrectly. When a full-speed device is connected:

- **Correct:** `libusb_get_device_speed()` → `LIBUSB_SPEED_FULL` → `USB_SPEED_FULL`
- **Xiaomi bug:** `libusb_get_device_speed()` → `LIBUSB_SPEED_LOW` → `USB_SPEED_LOW`

The maxpacket size in the device descriptor is still correct (64 for full-speed),
creating the impossible combination: low-speed + maxpacket=64.

### USB Spec Reference

| Speed | Max Packet Size (EP0) |
|-------|----------------------|
| Low-speed | 8 bytes |
| Full-speed | 8, 16, 32, or 64 bytes |
| High-speed | 64 bytes |
| SuperSpeed | 512 bytes |

A low-speed device with maxpacket=64 is physically impossible per USB spec,
which is why the kernel rejects it.

### Defense-in-Depth

```
Host (Xiaomi) → QEMU (host-libusb.c) → Guest Kernel (hub.c)
     ↓                   ↓                      ↓
  speed=LOW          speed=FULL            accepts device
  maxpacket=64      (quirk corrects)      (else-if branch)
```

- **Layer 1 (QEMU):** Catches the mismatch in the completion handler, corrects
  speed before the guest sees the device descriptor
- **Layer 2 (Kernel):** Safety net in case QEMU quirk doesn't fire (e.g., timing
  edge case). The `else if` branch handles it without reaching `goto fail`

---

## Build Pipeline

### Workflow: `build.yml` (Build Patches & Update Release)

Triggers on push to main when these files change:
- `Dockerfile`
- `build-tools/**`
- `opx_kernel.config`
- `gradle.properties`
- `.github/workflows/build.yml`

Builds:
1. **QEMU** (`qemu-builder` stage) — cross-compiled with Xiaomi USB quirk
2. **Kernel** (`kernel-builder` stage) — with hub.c maxpacket fix

Uploads to `all-core-file` release via `gh release upload --clobber`.

### Workflow: `build-apk.yml` (Build APK & Publish Release)

Triggers ONLY after `build.yml` completes successfully (`workflow_run`).

Builds:
1. Downloads fresh binaries from `all-core-file` release
2. Runs `./gradlew assembleDebug` (exact developer build process)
3. Creates `v1.0.0` release with the APK

---

## Verification

After building, test on a Xiaomi/MIUI device:

```bash
# In the OPX terminal:
lsusb                    # Should show connected USB devices
dmesg | grep -i usb      # Should NOT contain "Invalid ep0 maxpacket"
dmesg | grep -i "low-speed device with maxpacket=64"  # QEMU quirk log
```

If the fix works:
- `lsusb` shows the device
- No "Invalid ep0 maxpacket" errors in dmesg
- Device is accessible via `podman` or standard Linux tools
