# StrykerApp Stock QEMU Binary — Definitive Analysis

## Stock Binary Details
- **QEMU Version:** 11.0.2
- **Architecture:** aarch64-softmmu
- **Size:** 42 MB
- **Libraries:** libslirp.so (1.1 MB)

## USB Passthrough: Exact Flow

### App-Side (UsbPassthroughManager.java)
```
1. Android UsbManager.getDeviceList() → find WiFi adapter
2. UsbManager.openDevice(device) → get UsbDeviceConnection
3. UsbDeviceConnection.getFileDescriptor() → get raw fd
4. QmpClient.addFd(fd) → SCM_RIGHTS over LocalSocket
5. QmpClient.deviceAdd({driver: "usb-host", hostdevice: "/dev/fdset/N"})
6. QEMU opens fd → USB device attached
```

### QEMU-Side (host-libusb.c)
```
1. QMP add-fd → receives fd via SCM_RIGHTS
2. QMP device_add usb-host → creates USB host device
3. libusb_wrap_sys_device(ctx, fd) → wraps Android fd
4. LIBUSB_OPTION_NO_DEVICE_DISCOVERY → skip enumeration
5. USB device accessible to guest
```

## Critical QEMU Features (Must Be Compiled In)

### USB Features
```
✅ usb-host           - USB host device passthrough
✅ usb-xhci           - USB 3.0 controller
✅ usb-ehci           - USB 2.0 controller
✅ libusb             - USB library support
✅ LIBUSB_OPTION_NO_DEVICE_DISCOVERY - Skip enumeration
✅ libusb_wrap_sys_device - Wrap Android fd
✅ usbfs backend      - /dev/bus/usb support
```

### Other Required Features
```
✅ slirp              - User-mode networking
✅ virtio-console     - Terminal I/O
✅ virtio-blk         - Block devices
✅ virtio-net         - Networking
✅ virtio-9p          - File sharing
✅ qmp                - Machine Protocol
✅ tui                - Text UI (for -display none)
```

## Stock Binary: What We Know

### QEMU Version
- QEMU 11.0.2 (same as our build)
- Source: `qemu-11.0.2/`

### Linked Libraries
```
libslirp.so       - User-mode networking
libc.so           - C library
libdl.so          - Dynamic linker
libm.so           - Math library
libz.so           - Compression
```

### Build Configuration (Inferred)
```
--target-list=aarch64-softmmu
--enable-slirp
--enable-libusb
--enable-virtfs
--disable-docs
--disable-gtk
--disable-sdl
--disable-vnc
```

## Why Rebuild Fails (Hypothesis)

### Possible Causes

1. **AOSP libusb vs Vanilla libusb**
   - Stock: AOSP's android-libusb (custom fork with Android-specific patches)
   - Our build: Vanilla libusb 1.0.27
   - Difference: AOSP libusb has better Android fd handling

2. **QEMU Source**
   - Stock: Possibly AOSP's QEMU fork (with Android patches)
   - Our build: Vanilla QEMU 11.0.2 + our patches
   - Difference: AOSP QEMU has Android-specific USB fixes

3. **Build Flags**
   - Stock: Exact flags unknown
   - Our build: Standard flags + patches
   - Difference: Maybe missing `--enable-usb-host` or similar

4. **libusb Integration**
   - Stock: libusb compiled with AOSP's build system
   - Our build: libusb cross-compiled with NDK
   - Difference: Different compilation flags

## Build Script Requirements

### Must Match Stock Binary

1. **Use AOSP libusb** (not vanilla)
   - Source: https://android.googlesource.com/platform/external/libusb/
   - Must compile with `LIBUSB_OPTION_NO_DEVICE_DISCOVERY`

2. **Use AOSP QEMU** (not vanilla)
   - Source: https://android.googlesource.com/platform/external/qemu/
   - Has Android-specific USB patches

3. **Exact Configure Flags**
   ```
   --target-list=aarch64-softmmu
   --enable-slirp
   --enable-libusb
   --enable-virtfs
   --disable-docs
   --disable-gtk
   --disable-sdl
   --disable-vnc
   ```

4. **Cross-Compilation**
   - NDK r27c (or matching AOSP version)
   - Target: aarch64-linux-android26
   - API level: 26

## Next Steps

1. Find AOSP QEMU source repository
2. Find AOSP libusb source
3. Create Dockerfile matching AOSP build
4. Test on device
5. Compare binary with stock
