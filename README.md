<div align="center">

# YourXDemon

**Run Linux on your Android phone. No root. A real VM with SSH access.**

A real Alpine Linux VM with its own kernel — not a chroot or proot trick — running on stock Android 8+ (arm64).

[![Release](https://img.shields.io/github/v/release/OPX-Aminul/Podroid?include_prereleases&style=flat-square&label=release&color=blue)](https://github.com/OPX-Aminul/Podroid/releases)
[![Downloads](https://img.shields.io/github/downloads/OPX-Aminul/Podroid/total?style=flat-square&color=brightgreen)](https://github.com/OPX-Aminul/Podroid/releases)
![Android 8+](https://img.shields.io/badge/Android-8%2B-3DDC84?style=flat-square&logo=android&logoColor=white)
![arm64](https://img.shields.io/badge/arch-arm64-orange?style=flat-square)

[**Download APK**](https://github.com/OPX-Aminul/Podroid/releases/latest)

</div>

## What you get

- **A real VM** — Alpine Linux on a custom kernel via QEMU, or hardware-accelerated AVF on supported pKVM devices
- **In-app terminal** — full xterm-256color, 122 color themes, 13 fonts, live resize
- **USB WiFi support** — works with Realtek, MediaTek, Qualcomm, Intel, Broadcom, and more
- **SSH access** — connect from any device on your network
- **Port forwarding** — expose VM services to your phone and LAN
- **X11 desktop** — run GUI Linux apps in a built-in viewer
- **English and 中文**, no root, any arm64 device on Android 8+

## Quick start

1. [Download the APK](https://github.com/OPX-Aminul/Podroid/releases/latest) and install it.
2. Tap **Start VM**, wait for **Ready!**, open the terminal.

```sh
# SSH in from your laptop (enable SSH in the setup wizard or Settings)
ssh root@<phone-ip> -p 9922        # password: yourxdemon
```

## Build

```sh
git clone https://github.com/OPX-Aminul/Podroid.git
cd Podroid
./build-all.sh all     # kernel, rootfs, QEMU and APK (needs Docker + Android SDK/NDK)
```

## Features

| Feature | Status |
|---|---|
| Alpine Linux 3.24 VM | ✅ |
| QEMU TCG (software emulation) | ✅ |
| AVF/pKVM (hardware acceleration) | ✅ |
| SSH (dropbear) | ✅ |
| WiFi firmware (12 packages) | ✅ |
| USB passthrough (Xiaomi/MIUI fix) | ✅ |
| X11 desktop viewer | ✅ |
| Port forwarding | ✅ |
| Guest → Android bridge | ✅ |
| Release APK with R8 minification | ✅ |

## Credits

| | |
|---|---|
| **Original developer** | [ExTV](https://github.com/ExTV) — created Podroid |
| **Rebranded by** | OP Aminul FF (OPX) |
| [QEMU](https://www.qemu.org) | Machine emulation |
| [Termux](https://github.com/termux/termux-app) | Terminal emulator engine |
| [Alpine Linux](https://alpinelinux.org) | The guest distribution |

This project is a fork/rebrand of [Podroid](https://github.com/ExTV/Podroid) by ExTV. All credit to the original developers for creating the VM engine, boot pipeline, and Android integration.

## License

[GPLv2](LICENSE). Based on [Podroid](https://github.com/ExTV/Podroid) by ExTV.
