<div align="center">

# YourXDemon

**Run Linux on your Android phone. No root. A real VM with SSH access.**

A real Debian Trixie (testing) Linux VM with its own kernel -- not a chroot or proot trick -- running on stock Android 8+ (arm64).

[![Release](https://img.shields.io/github/v/release/OPX-Aminul/OPX?include_prereleases&style=flat-square&label=release&color=blue)](https://github.com/OPX-Aminul/OPX/releases)
[![Downloads](https://img.shields.io/github/downloads/OPX-Aminul/OPX/total?style=flat-square&color=brightgreen)](https://github.com/OPX-Aminul/OPX/releases)
![Android 8+](https://img.shields.io/badge/Android-8%2B-3DDC84?style=flat-square&logo=android&logoColor=white)
![arm64](https://img.shields.io/badge/arch-arm64-orange?style=flat-square)

[**Download APK**](https://github.com/OPX-Aminul/OPX/releases/latest)

</div>

## What you get

- **A real VM** -- Debian Trixie on a custom kernel via QEMU, or hardware-accelerated AVF on supported pKVM devices
- **In-app terminal** -- full xterm-256color, 122 color themes, 13 fonts, live resize
- **USB WiFi support** -- works with Realtek, MediaTek, Qualcomm, Intel, Broadcom, and more
- **USB passthrough** -- hot-plug USB devices (WiFi adapters, storage, serial, Bluetooth) with Xiaomi/MIUI fix
- **SSH access** -- connect from any device on your network
- **Port forwarding** -- expose VM services to your phone and LAN
- **X11 desktop** -- run GUI Linux apps in a built-in viewer
- **English and Chinese**, no root, any arm64 device on Android 8+

## Quick start

1. [Download the APK](https://github.com/OPX-Aminul/OPX/releases/latest) and install it.
2. Tap **Start VM**, wait for **Ready!**, open the terminal.

```sh
# SSH in from your laptop (enable SSH in the setup wizard or Settings)
ssh root@<phone-ip> -p 9922        # password: yourxdemon
```

## Build

```sh
git clone https://github.com/OPX-Aminul/OPX.git
cd OPX
./build-all.sh all     # kernel, rootfs, QEMU and APK (needs Docker + Android SDK/NDK)
```

### Build targets

```sh
./build-all.sh kernel       # custom Linux kernel only
./build-all.sh initramfs    # kernel + minimal initramfs
./build-all.sh rootfs       # Debian Trixie squashfs
./build-all.sh qemu         # QEMU + native helpers via Docker
./build-all.sh termux       # terminal-emulator JNI for 16KB pages
./build-all.sh apk          # Android APK via Gradle
./build-all.sh all          # everything
./build-all.sh deploy       # all + install + launch
./build-all.sh test         # boot validation: installs, polls console.log for "Ready!"
```

## Features

| Feature | Status |
|---|---|
| Debian Trixie (testing) VM | ✅ |
| QEMU TCG (software emulation) | ✅ |
| AVF/pKVM (hardware acceleration) | ✅ |
| SSH (dropbear) | ✅ |
| WiFi firmware (12 packages) | ✅ |
| USB passthrough (Xiaomi/MIUI fix) | ✅ |
| X11 desktop viewer | ✅ |
| Port forwarding | ✅ |
| Guest to Android bridge | ✅ |
| OPX-wifi4 (pre-installed WiFi tool) | ✅ |
| Release APK with R8 minification | ✅ |

## Architecture

- **Two VM backends** behind one interface (`VmEngine`):
  - **QEMU (TCG)** -- software emulation, the default, needs no special permission
  - **AVF (pKVM)** -- hardware-accelerated via the Android Virtualization Framework on Pixel-class devices
- **Guest**: Debian Trixie with OpenRC as PID 1, persistent ext4 overlay on squashfs
- **Storage**: grows on demand (never shrinks), user-configurable (2-512 GB)
- **RAM**: 512 MB to 16 GB, user-configurable
- **CPU**: 1-8 cores, user-configurable

## License

[GPLv2](LICENSE).
