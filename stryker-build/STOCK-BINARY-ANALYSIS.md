# StrykerApp Stock QEMU Binary Analysis

## Binary Details
- **QEMU Version:** 11.0.2
- **Size:** 42 MB
- **Architecture:** aarch64 (ARM64)
- **Target:** aarch64-softmmu

## Critical Features Found

### USB Passthrough (Working in Stock)
```
usb-host          ✅ Present
usb-xhci          ✅ Present
usb-ehci          ✅ Present
libusb_init_context  ✅ Present
LIBUSB_OPTION_NO_DEVICE_DISCOVERY  ✅ "no device discovery will be performed"
libusb_wrap_sys_device  ✅ Present
usbfs backend     ✅ Present (/dev/bus/usb)
```

### Linked Libraries
```
libslirp.so       ✅ (user-mode networking)
libslirp.so.0     ✅ (soname)
libc.so           ✅
libdl.so          ✅
libm.so           ✅
libz.so           ✅
```

### QEMU Features
```
TCG acceleration  ✅ (software emulation)
KVM support       ✅ (if /dev/kvm available)
virtio devices    ✅ (all standard)
virtio-console    ✅ (terminal I/O)
virtio-blk        ✅ (block devices)
virtio-net        ✅ (networking)
virtio-9p         ✅ (file sharing)
```

## Guest Agent (stryker-agentd)
- **Size:** 572 bytes (shell script)
- **Dependencies:** socat
- **Port 1050:** `socat TCP-LISTEN:1050 EXEC:/bin/sh` (non-interactive)
- **Port 1051:** `socat TCP-LISTEN:1051 EXEC:'bash -il',pty` (interactive PTY)
- **Service:** systemd unit (stryker-agent.service)

## Why Stock Works But Rebuilt Doesn't

### Possible Causes

1. **AOSP QEMU Source**
   - Stock binary likely uses AOSP's QEMU fork (not vanilla)
   - AOSP has Android-specific patches for USB passthrough
   - Our build uses vanilla QEMU + patches

2. **Build Flags**
   - Stock: `--enable-libusb --enable-slirp --enable-virtfs`
   - Our: Same flags, but maybe different libusb version

3. **libusb Version**
   - Stock: AOSP's android-libusb (custom fork)
   - Our: Vanilla libusb 1.0.27

4. **QEMU Configure Options**
   - Stock might have: `--enable-usb-host --enable-usb-redirect`
   - We need to verify exact configure flags

## Build Script Requirements

Based on analysis, the build script must:

1. **Use AOSP libusb** (not vanilla)
2. **Match exact configure flags**
3. **Include all USB features**
4. **Use correct cross-compilation settings**

## Next Steps

1. Find AOSP QEMU source repository
2. Compare build flags with stock binary
3. Create accurate Dockerfile
4. Test on device
