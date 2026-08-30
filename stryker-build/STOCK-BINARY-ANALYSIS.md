# StrykerApp Stock QEMU Binary — Deep Analysis

> **Last updated:** August 30, 2026
> **Method:** Binary analysis of rootless-main release + full app source code review

---

## 1. Binary Inventory

| File | SHA256 (from manifest) | Size |
|---|---|---|
| `qemu-system-aarch64` | `2a87f53...` | 42 MB |
| `libslirp.so` | `2263724...` | 1.1 MB |
| `Image` (kernel) | `cbe59a0...` | 36 MB |
| `initrd.img` | `655f3ef...` | 36 MB |
| `rootfs.imgz` | `f80c2b1...` | 408 MB |

---

## 2. QEMU Binary Deep Dive

### 2.1 Version & Source

- **QEMU version:** 11.0.2 (confirmed via embedded source paths)
- **Source paths in binary:** `/qemu-11.0.2/` — this is the **vanilla QEMU** directory structure
- **Architecture:** aarch64-softmmu
- **Linked libs:** libslirp.so, libc, libm, libz, libdl

### 2.2 USB Features (ALL present in stock binary)

```
usb-host              ✅  USB host passthrough device
usb-xhci              ✅  USB 3.0 controller
usb-ehci              ✅  USB 2.0 controller  
usb-storage           ✅  USB mass storage
usb-mass-storage      ✅  USB MSD
usb-hid               ✅  USB HID
usb-mouse             ✅  USB mouse
usb-kbd               ✅  USB keyboard
usb-tablet            ✅  USB tablet
usb-net               ✅  USB network
usb-serial            ✅  USB serial
usb-msd               ✅  USB MSD
usb-uas               ✅  USB attached SCSI
usb-mtp               ✅  USB MTP
usb-wacom             ✅  USB Wacom tablet
SCM_RIGHTS            ✅  fd passing (for USB attach)
libusb                ✅  USB library
wrap_sys_device       ✅  libusb_wrap_sys_device (critical!)
usbfs                 ✅  USB filesystem backend
```

**`wrap_sys_device`** is the CRITICAL symbol. This is what lets QEMU wrap an Android USB fd without needing direct `/dev/bus/usb` access.

### 2.3 Other Features

```
slirp                 ✅  User-mode networking
virtio-console        ✅  Terminal I/O
virtio-blk            ✅  Block devices
virtio-net            ✅  Networking
virtio-9p             ✅  File sharing
qmp                   ✅  Machine Protocol
-announce             ✅  Network announce
```

---

## 3. App Source Code Analysis

### 3.1 QEMU Command Construction (RootlessEngine.java)

```java
// Default settings (from VmSpecs.java)
cpus = 4
ramMb = 4096
usbEnabled = true
shareEnabled = true
rngEnabled = true
mttcg = true (multi-threaded TCG)
ioThread = true
fastBoot = true
cacheMode = "writeback"
aioMode = "threads"
cpuModel = "max,sve=off,pmu=off,pauth=off"
tbSize = 512 (for RAM >= 2GB)

// QEMU command:
qemu-system-aarch64
  -nodefaults
  -M virt,gic-version=3
  -cpu max,sve=off,pmu=off,pauth=off
  -accel tcg,thread=multi,tb-size=512
  -smp 4,sockets=1,cores=4,threads=1
  -m 4096
  -kernel Image
  -initrd initrd.img
  -append "root=/dev/vda rw rootwait rootflags=noatime 
           console=ttyAMA0 loglevel=4 net.ifnames=0 
           mitigations=off stryker.rootless=1
           init_on_alloc=0 init_on_free=0 audit=0 nokaslr
           rcupdate.rcu_expedited=1 rcupdate.rcu_normal_after_boot=1
           cryptomgr.notests random.trust_bootloader=on"
  -drive file=rootfs.img,if=none,id=drive0,format=raw,cache=writeback,aio=threads,discard=unmap,detect-zeroes=unmap
  -object iothread,id=io0
  -device virtio-blk-pci,drive=drive0,iothread=io0
  -netdev user,id=net0,ipv6=off,hostfwd=tcp:127.0.0.1:1050-:1050,hostfwd=tcp:127.0.0.1:1051-:1051,hostfwd=tcp:127.0.0.1:1052-:1052,hostfwd=tcp:127.0.0.1:2222-:22
  -device virtio-net-pci,netdev=net0,romfile=
  -device qemu-xhci,id=usbhc0,p2=8,p3=8
  -device virtio-rng-pci
  -fsdev local,id=fsdev0,security_model=none,path=/sdcard/Stryker
  -device virtio-9p-pci,fsdev=fsdev0,mount_tag=strykershare
  -chardev socket,id=serial0,path=serial.sock,server=on,wait=off,logfile=serial.log
  -serial chardev:serial0
  -device virtio-serial-pci
  -chardev socket,id=term0,path=term.sock,server=on,wait=off
  -device virtconsole,chardev=term0,name=org.stryker.term
  -display none
  -qmp unix:qmp.sock,server,nowait
```

### 3.2 USB Attach Flow (Complete)

```
Step 1: Android UsbManager
  UsbManager.getDeviceList() → find WiFi adapter
  UsbManager.openDevice(device) → UsbDeviceConnection
  UsbDeviceConnection.getFileDescriptor() → raw fd

Step 2: QMP add-fd (SCM_RIGHTS)
  QmpClient.addFd(fd)
    → LocalSocket sends fd as ancillary data (SCM_RIGHTS)
    → QEMU receives fd, assigns fdset-id=N

Step 3: QMP device_add
  QmpClient.deviceAdd({
    driver: "usb-host",
    id: "stryker_usb_<deviceId>",
    bus: "usbhc0.0",
    hostdevice: "/dev/fdset/N"
  })
    → QEMU calls libusb_wrap_sys_device(ctx, fd)
    → USB device accessible to guest
```

### 3.3 Guest Agent (stryker-agentd)

```sh
#!/bin/sh
# 572 bytes - pure socat
SOCAT="$(command -v socat 2>/dev/null)"
[ -z "$SOCAT" ] && exit 1
mkdir -p /sdcard/Stryker/hs /sdcard/Stryker/captured /sdcard/Stryker/reports

# Port 1050: non-interactive commands
"$SOCAT" TCP-LISTEN:1050,reuseaddr,fork EXEC:/bin/sh,stderr &

# Port 1051: interactive PTY shell
if command -v bash >/dev/null 2>&1; then
  "$SOCAT" TCP-LISTEN:1051,reuseaddr,fork EXEC:'bash -il',pty,setsid,ctty,stderr &
else
  "$SOCAT" TCP-LISTEN:1051,reuseaddr,fork EXEC:'/bin/sh -i',pty,setsid,ctty,stderr &
fi
wait
```

### 3.4 GuestExec.java (TCP Client)

```java
// Connect to port 1050, send command, read output
Socket sock = new Socket();
sock.connect("127.0.0.1", 1050, 4000);  // 4s connect timeout
sock.setSoTimeout(90000);  // 90s read timeout

// Send command with PATH setup
String payload = "export PATH=/usr/local/sbin:/usr/local/bin:...; " +
                 "export HOME=/root LANG=C.UTF-8; " +
                 command + "\n" +
                 "printf '\\n__STRYKER_EXIT__%s\\n' \"$?\"\n";
sock.getOutputStream().write(payload.getBytes());

// Read output until EXIT_SENTINEL
while ((line = reader.readLine()) != null) {
    if (line.startsWith("__STRYKER_EXIT__")) {
        exitCode = Integer.parseInt(line.substring(17));
        break;
    }
    output.add(line);
}
```

### 3.5 Port Map

| Port | Service | Use |
|---|---|---|
| 1050 | stryker-agentd | Non-interactive commands (GuestExec) |
| 1051 | stryker-agentd | Interactive PTY shell (bash -il) |
| 1052 | (unused in app code) | Reserved |
| 2222 | sshd | SSH access |

---

## 4. Rootfs Analysis

- **OS:** Debian 13.6 (trixie)
- **Init:** systemd (NOT OpenRC)
- **Key services enabled:**
  - stryker-agent.service (auto-starts socat daemon)
  - sshd.service
  - networking
  - cron
  - dbus
  - apparmor

- **Packages installed:** socat, bash, openssh-server, standard Debian base
- **Agent location:** `/usr/local/sbin/stryker-agentd`
- **Service file:** `/etc/systemd/system/stryker-agent.service`

---

## 5. Why Our Rebuild Breaks USB — The REAL Answer

### 5.1 Source is Vanilla QEMU (Confirmed)

The stock binary contains paths like `/qemu-11.0.2/hw/usb/hcd-ehci.h` and `/qemu-11.0.2/hw/usb/host-libusb.c`. This is **vanilla QEMU** directory structure. AOSP QEMU fork uses different paths.

### 5.2 The Binary is 42MB — Our Build is ~52MB

The stock binary is **10MB smaller**. This suggests:
- Different compiler optimization flags
- Possibly stripped more aggressively
- Or compiled with different NDK version

### 5.3 Key Differences Between Stock and Our Build

| Feature | Stock (StrykerApp) | Our Build |
|---|---|---|
| **Source** | Vanilla QEMU 11.0.2 | Vanilla QEMU 11.0.2 |
| **libusb** | **Unknown version** | libusb 1.0.27 |
| **Compiler** | **Unknown NDK** | Debian cross + llvm |
| **Extra flags** | Unknown | `-DANDROID`, shm shim, PAC shim |
| **Binary size** | 42 MB | ~52 MB |

### 5.4 The Real Problem

**The stock binary was NOT built with our Dockerfile.** It was built by someone (the StrykerApp developer) using:
- Unknown build environment
- Unknown NDK version
- Unknown configure flags
- Unknown libusb version

**Our Dockerfile adds 5 patches/shims:**
1. shm_open shim (memfd_create)
2. PAC coroutine fix (sigsetjmp replacement)
3. LIBUSB_OPTION_NO_DEVICE_DISCOVERY injection
4. Xiaomi USB speed quirk
5. ivshmem disabled

**The PAC coroutine fix might be breaking USB.** The shim replaces sigsetjmp/siglongjmp with custom assembly. If this affects libusb's internal state management (which uses setjmp for error handling), USB operations could fail silently.

### 5.5 The "can't attach to VM" Error

This error comes from the **app** when `qmp.deviceAdd()` returns false. The exact QEMU-side failure is:
1. QMP add-fd succeeds (fd is received)
2. QMP device_add is called
3. QEMU tries to open the USB device via libusb
4. **Something fails** — but QMP returns an error
5. App sees error → "can't attach to VM"

---

## 6. DEFINITIVE Fix Strategy

### Option A: Match Stock Binary Exactly (Recommended)

1. **Don't use our Dockerfile patches** (PAC fix, shm shim)
2. **Use same NDK version** as StrykerApp developer
3. **Use same libusb version** as stock binary
4. **Compare binary hashes** after build

### Option B: Use AOSP QEMU Fork

AOSP maintains a QEMU fork at:
- https://android.googlesource.com/platform/external/qemu/
- AOSP libusb: https://android.googlesource.com/platform/external/libusb/

These are pre-patched for Android but may not be QEMU 11.0.2.

### Option C: Binary Diff Analysis

1. Extract all symbols from stock binary: `nm -D qemu-system-aarch64`
2. Extract all symbols from our build
3. Diff the two lists
4. Find missing/extra symbols
5. Identify the exact feature causing failure

---

## 7. Build Requirements (For Next Session)

### What to Build
1. QEMU 11.0.2 with vanilla source (no extra patches except USB ones)
2. libusb 1.0.27 (or match stock version)
3. libslirp (standard)

### How to Build
```bash
# Clone QEMU
git clone --depth=1 --branch v11.0.2 https://github.com/qemu/qemu.git
cd qemu

# Apply ONLY these patches (not the PAC/shm patches):
# 1. Xiaomi USB speed quirk
# 2. LIBUSB_OPTION_NO_DEVICE_DISCOVERY

# Configure
./configure \
  --target-list=aarch64-softmmu \
  --enable-tcg \
  --enable-slirp \
  --enable-virtfs \
  --enable-libusb \
  --enable-pie \
  --disable-docs \
  --disable-gtk \
  --disable-sdl \
  --disable-vnc \
  --disable-vhost-user \
  --disable-plugins \
  --with-coroutine=ucontext

# Build
make -j$(nproc)
```

### What to Test
1. USB WiFi adapter enumeration
2. USB HID passthrough
3. Port 1050 (non-interactive exec)
4. Port 1051 (interactive PTY)
5. Serial console output

---

## 8. Critical Context from OPXDemom

The user tried 7 releases (v1.0.0 → v1.0.7) to fix USB:
- v1.0.7: Xiaomi USB speed quirk added
- Stock binary: USB works ✅
- Rebuilt binary: USB fails ❌

**The problem is NOT the Xiaomi patch.** The problem is that something else in our build environment breaks USB passthrough.

---

*Generated by Buffy — August 30, 2026*
