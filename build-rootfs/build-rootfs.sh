#!/bin/sh
set -eu
ROOTFS=/work/rootfs

# ALPINE_VERSION comes from the Dockerfile ENV (full release like 3.24.1).
# Strip the patch component to get the major branch (e.g. 3.24) used in repo URLs.
: "${ALPINE_VERSION:?ALPINE_VERSION must be set (e.g. 3.24.1)}"
ALPINE_BRANCH="${ALPINE_VERSION%.*}"

mkdir -p "$ROOTFS/etc/apk"
cat > "$ROOTFS/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/community
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/testing
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

apk -X "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/main" \
    -X "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/community" \
    -X "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/testing" \
    -X "https://dl-cdn.alpinelinux.org/alpine/edge/main" \
    -X "https://dl-cdn.alpinelinux.org/alpine/edge/community" \
    -X "https://dl-cdn.alpinelinux.org/alpine/edge/testing" \
    -U --allow-untrusted --root "$ROOTFS" --initdb add \
    alpine-base \
    openrc \
    busybox-openrc \
    bash \
    iproute2 \
    dropbear dropbear-openrc \
    openssh-sftp-server \
    curl \
    ca-certificates \
    libcap-utils \
    doas sudo \
    gcompat \
    gzip \
    xz \
    linux-firmware-rtlwifi \
    linux-firmware-realtek \
    linux-firmware-rtl_bt \
    linux-firmware-rtl_nic \
    linux-firmware-rtw88 \
    linux-firmware-rtw89 \
    linux-firmware-mediatek \
    linux-firmware-brcm \
    linux-firmware-intel \
    linux-firmware-qca \
    linux-firmware-libertas \
    linux-firmware-ath9k_htc \
    || true
# NOTE: '|| true' tolerates cross-architecture post-install script errors
# (Exec format error) — packages ARE installed, only post-install scripts fail
# when running aarch64 binaries under QEMU on x86_64 GitHub Actions runners.

# Ensure doas and sudo are setuid-root. apk usually does this, but on
# overlay-mounted build hosts it can silently fail.
chmod u+s "$ROOTFS/usr/bin/doas"  2>/dev/null || true
chmod u+s "$ROOTFS/usr/bin/sudo"  2>/dev/null || true

# doas: members of the `wheel` group can become root after entering their
# password (cached for ~5 min). Standard *BSD/Alpine convention.
mkdir -p "$ROOTFS/etc/doas.d"
echo "permit persist :wheel" > "$ROOTFS/etc/doas.d/doas.conf"
chmod 0400 "$ROOTFS/etc/doas.d/doas.conf"

# sudo: equivalent rule for users who prefer sudo over doas.
mkdir -p "$ROOTFS/etc/sudoers.d"
echo "%wheel ALL=(ALL) ALL" > "$ROOTFS/etc/sudoers.d/wheel"
chmod 0440 "$ROOTFS/etc/sudoers.d/wheel"

# Set root password to "yourxdemon" (pre-hashed with openssl).
# We can't run chpasswd inside the aarch64 rootfs from an x86_64 host,
# so write the SHA-512 hash directly into /etc/shadow.
# No fixed -salt: openssl generates a random salt so the stored hash differs
# per build (the password stays the documented default "yourxdemon").
ROOT_HASH=$(openssl passwd -6 yourxdemon)
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# Strip docs/man/locale to shrink squashfs
rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/doc" \
       "$ROOTFS/usr/share/locale" "$ROOTFS/usr/share/info"

# Pre-create minimal runtime dirs
mkdir -p "$ROOTFS/run"

# Copy custom service files into the rootfs
cp /work/files/etc/init.d/podroid-bootstrap "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-network   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-resize    "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-ready     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-vsock     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-hostd     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-downloads "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-migrate   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/yourxdemon-agentd "$ROOTFS/etc/init.d/"
chmod +x "$ROOTFS/etc/init.d/podroid-"*
chmod +x "$ROOTFS/etc/init.d/yourxdemon-agentd"

# Copy /usr/local/bin scripts (resize daemon + login wrapper + getty selector)
mkdir -p "$ROOTFS/usr/local/bin"
cp /work/files/usr/local/bin/podroid-resize "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-login  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-getty  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-backup "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-update-stats "$ROOTFS/usr/local/bin/"
# podroid-vsock-agent is COPY'd in from the vsock-builder Docker stage. Make
# sure it's executable (cross-arch COPY can lose the mode bit on some buildkit
# versions).
chmod +x "$ROOTFS/usr/local/bin/podroid-vsock-agent" 2>/dev/null || true
# podroid-hostd is also COPY'd from the vsock-builder stage; same mode-bit guard.
# The CLIs are argv[0]-dispatch symlinks onto the one multi-call binary.
chmod +x "$ROOTFS/usr/local/bin/podroid-hostd" 2>/dev/null || true
# yourxdemon-agentd is COPY'd from the vsock-builder stage; same mode-bit guard.
chmod +x "$ROOTFS/usr/local/bin/yourxdemon-agentd" 2>/dev/null || true
# podroid-overlay-normalize is COPY'd from the vsock-builder stage; mode-bit guard.
chmod +x "$ROOTFS/usr/local/bin/podroid-overlay-normalize" 2>/dev/null || true
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-notify"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-forward"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-open"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-power"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-headless"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-server"
chmod +x "$ROOTFS/usr/local/bin/podroid-"*
mkdir -p "$ROOTFS/etc/conf.d"
cp /work/files/etc/conf.d/yourxdemon "$ROOTFS/etc/conf.d/"
# vsock agent's initial forward table (read at podroid-vsock startup).
mkdir -p "$ROOTFS/etc/yourxdemon"
cp /work/files/etc/yourxdemon/forwards.conf "$ROOTFS/etc/yourxdemon/forwards.conf"
chmod 0644 "$ROOTFS/etc/yourxdemon/forwards.conf"
# Migration scripts dir (seeded with its README; per-version <v>.sh added over time).
mkdir -p "$ROOTFS/etc/yourxdemon/migrations"
cp /work/files/etc/yourxdemon/migrations/README "$ROOTFS/etc/yourxdemon/migrations/README"
# System-version stamp: the migration anchor. Baked from the app versionCode at
# build time; compared against /mnt/persist/.yourxdemon/applied-version at boot.
printf '%s\n' "${SYSTEM_VERSION:-0}" > "$ROOTFS/etc/yourxdemon/system-version"
chmod 0644 "$ROOTFS/etc/yourxdemon/system-version"
cp /work/files/etc/inittab "$ROOTFS/etc/inittab"
cp /work/files/etc/rc.conf "$ROOTFS/etc/rc.conf"

# /etc/profile.d/*.sh — sourced by Alpine's /etc/profile in login shells.
# podroid-color.sh: COLORTERM=truecolor (24-bit color). podroid-x11.sh:
# DISPLAY / PULSE_SERVER for the in-app GUI viewer. Copy by explicit name so
# a renamed/removed asset fails the build (set -e) instead of silently
# shipping a squashfs without these exports.
mkdir -p "$ROOTFS/etc/profile.d"
cp /work/files/etc/profile.d/podroid-color.sh "$ROOTFS/etc/profile.d/"
chmod 0644 "$ROOTFS/etc/profile.d/podroid-color.sh"



# Hostname (read by podroid-bootstrap via `hostname -F /etc/hostname`)
echo "yourxdemon" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost yourxdemon" > "$ROOTFS/etc/hosts"
echo "::1 localhost ip6-localhost" >> "$ROOTFS/etc/hosts"

# Login banner shown by getty before the login prompt.
# \S=Alpine release, \r=kernel, \m=arch, \l=tty
cat > "$ROOTFS/etc/issue" <<'EOF'
Welcome to YourXDemon (Alpine \S)
Kernel \r on \m (\l)

  Default login:  root  /  yourxdemon
  Change root password:    passwd
  Create a regular user:   adduser -G wheel <name>
                           (wheel group → can run doas/sudo)

  Developed by ExTV (Podroid) | Rebranded by OP Aminul FF (OPX)

EOF

# Set runlevels via direct symlinks (host is x86_64, can't chroot into aarch64 rootfs to run rc-update).
# rc-update is just `ln -s /etc/init.d/X /etc/runlevels/<level>/X` under the hood.
mkdir -p "$ROOTFS/etc/runlevels/default" "$ROOTFS/etc/runlevels/boot"
# Guard each link: a dangling symlink (e.g. dnsmasq.lxcbr0, which lxc-bridge
# may ship only as dnsmasq config and not an init script) makes OpenRC log
# an error every boot and stalls podroid-ready's `after *` on a phantom.
for svc in podroid-migrate podroid-bootstrap podroid-network podroid-resize dropbear podroid-vsock podroid-downloads podroid-hostd yourxdemon-agentd podroid-ready; do
    if [ -e "$ROOTFS/etc/init.d/$svc" ]; then
        ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/default/$svc"
    else
        echo "WARN: init script /etc/init.d/$svc missing, skipping runlevel symlink"
    fi
done

# Disable services we don't need (initramfs already handles them, or they're noise in the VM)
for svc in hwclock swclock urandom networking sysctl bootmisc syslog; do
    rm -f "$ROOTFS/etc/runlevels/boot/$svc" "$ROOTFS/etc/runlevels/default/$svc"
done
