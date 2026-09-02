#!/bin/sh
set -eu
ROOTFS=/work/rootfs

# DEBIAN_VERSION comes from the Dockerfile ENV (e.g. "trixie").
: "${DEBIAN_VERSION:?DEBIAN_VERSION must be set (e.g. trixie)}"

# ── Configure apt sources ────────────────────────────────────────────────────
mkdir -p "$ROOTFS/etc/apt"
cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb http://deb.debian.org/debian ${DEBIAN_RELEASE:-trixie} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${DEBIAN_RELEASE:-trixie}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${DEBIAN_RELEASE:-trixie}-security main contrib non-free non-free-firmware
EOF

# ── Install packages via chroot apt ───────────────────────────────────────────
# NOTE: We use debootstrap's already-installed base as a starting point and
# layer additional packages on top. The --no-install-recommends flag keeps the
# image small. Some packages may not be available on arm64; || true tolerates
# that.
chroot "$ROOTFS" /bin/sh -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update || true
apt-get install -y --no-install-recommends \
    openrc \
    busybox \
    bash \
    iproute2 \
    iputils-ping \
    dropbear \
    curl \
    ca-certificates \
    libcap2-bin \
    sudo \
    gzip \
    xz-utils \
    socat \
    kmod \
    procps \
    nano \
    less \
    git \
    python3 \
    python3-pip \
    python3-dev \
    iw \
    hostapd \
    dnsmasq \
    pixiewps \
    wpa-supplicant \
    wireless-tools \
    2>/dev/null || true

# Install WiFi firmware packages (non-free).
# Covers Realtek, Qualcomm/Atheros, Broadcom, Marvell, Ralink/MediaTek.
# Intel firmware (firmware-iwlwifi) excluded — too large (~50MB) for a VM.
apt-get install -y --no-install-recommends \
    firmware-realtek \
    firmware-atheros \
    firmware-brcm80211 \
    firmware-libertas \
    firmware-misc-nonfree \
    2>/dev/null || true

# Clean up apt cache to shrink the squashfs.
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
'

# ── Set root password to "yourxdemon" ────────────────────────────────────────
# We can't run chpasswd inside the aarch64 rootfs from an x86_64 host,
# so write the SHA-512 hash directly into /etc/shadow.
ROOT_HASH=$(openssl passwd -6 yourxdemon)
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# ── Strip docs/man/locale to shrink squashfs ─────────────────────────────────
rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/doc" \
       "$ROOTFS/usr/share/locale" "$ROOTFS/usr/share/info"

# ── Pre-create minimal runtime dirs ──────────────────────────────────────────
mkdir -p "$ROOTFS/run"

# ── Copy custom service files into the rootfs ────────────────────────────────
cp /work/files/etc/init.d/opx-bootstrap "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/opx-network   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/opx-resize    "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/opx-ready     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/opx-vsock     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/opx-hostd     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/opx-migrate   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/yourxdemon-agentd "$ROOTFS/etc/init.d/"
chmod +x "$ROOTFS/etc/init.d/opx-"*
chmod +x "$ROOTFS/etc/init.d/yourxdemon-agentd"

# ── Copy /usr/local/bin scripts ─────────────────────────────────────────────
mkdir -p "$ROOTFS/usr/local/bin"
cp /work/files/usr/local/bin/opx-resize "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/opx-login  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/opx-getty  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/opx-backup "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/opx-update-stats "$ROOTFS/usr/local/bin/"
# vsock-agent is COPY'd in from the vsock-builder Docker stage.
chmod +x "$ROOTFS/usr/local/bin/opx-vsock-agent" 2>/dev/null || true
# hostd is also COPY'd from the vsock-builder stage.
chmod +x "$ROOTFS/usr/local/bin/opx-hostd" 2>/dev/null || true
# yourxdemon-agentd is COPY'd from the vsock-builder stage.
chmod +x "$ROOTFS/usr/local/bin/yourxdemon-agentd" 2>/dev/null || true
# opx-overlay-normalize is COPY'd from the vsock-builder stage.
chmod +x "$ROOTFS/usr/local/bin/opx-overlay-normalize" 2>/dev/null || true
ln -sf opx-hostd "$ROOTFS/usr/local/bin/opx-notify"
ln -sf opx-hostd "$ROOTFS/usr/local/bin/opx-forward"
ln -sf opx-hostd "$ROOTFS/usr/local/bin/opx-open"
ln -sf opx-hostd "$ROOTFS/usr/local/bin/opx-power"
ln -sf opx-hostd "$ROOTFS/usr/local/bin/opx-headless"
ln -sf opx-hostd "$ROOTFS/usr/local/bin/opx-server"
chmod +x "$ROOTFS/usr/local/bin/opx-"*

# ── Config files ─────────────────────────────────────────────────────────────
mkdir -p "$ROOTFS/etc/conf.d"
cp /work/files/etc/conf.d/yourxdemon "$ROOTFS/etc/conf.d/"

# vsock agent's initial forward table.
mkdir -p "$ROOTFS/etc/yourxdemon"
cp /work/files/etc/yourxdemon/forwards.conf "$ROOTFS/etc/yourxdemon/forwards.conf"
chmod 0644 "$ROOTFS/etc/yourxdemon/forwards.conf"

# Migration scripts dir.
mkdir -p "$ROOTFS/etc/yourxdemon/migrations"
cp /work/files/etc/yourxdemon/migrations/README "$ROOTFS/etc/yourxdemon/migrations/README"

# System-version stamp.
printf '%s\n' "${SYSTEM_VERSION:-0}" > "$ROOTFS/etc/yourxdemon/system-version"
chmod 0644 "$ROOTFS/etc/yourxdemon/system-version"

# ── Init system: inittab + rc.conf ───────────────────────────────────────────
cp /work/files/etc/inittab "$ROOTFS/etc/inittab"
cp /work/files/etc/rc.conf "$ROOTFS/etc/rc.conf"

# ── OPX-wifi4 pre-installed ────────────────────────────────────────────────
mkdir -p "$ROOTFS/opt/opx-wifi4"
cp /work/opx-wifi4/* "$ROOTFS/opt/opx-wifi4/" 2>/dev/null || true
# Create /usr/local/bin/wifi4 wrapper
cat > "$ROOTFS/usr/local/bin/wifi4" <<'WIFIEOF'
#!/bin/sh
exec python3 /opt/opx-wifi4/oneshot.py "$@"
WIFIEOF
chmod +x "$ROOTFS/usr/local/bin/wifi4"

# ── PS1 prompt ──────────────────────────────────────────────────────────────
cat > "$ROOTFS/etc/profile.d/opx-prompt.sh" <<'PROMPTEOF'
# Modern OPX prompt: opx root ~/path $
PS1='\[\033[1;32m\]opx\[\033[0m\] \[\033[1;33m\]\u\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\]\$ '
export PS1
PROMPTEOF
chmod 0644 "$ROOTFS/etc/profile.d/opx-prompt.sh"

# ── Profile scripts ──────────────────────────────────────────────────────────
mkdir -p "$ROOTFS/etc/profile.d"
cp /work/files/etc/profile.d/opx-color.sh "$ROOTFS/etc/profile.d/"
chmod 0644 "$ROOTFS/etc/profile.d/opx-color.sh"

# ── Hostname ─────────────────────────────────────────────────────────────────
echo "yourxdemon" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost yourxdemon" > "$ROOTFS/etc/hosts"
echo "::1 localhost ip6-localhost" >> "$ROOTFS/etc/hosts"

# ── Login banner ─────────────────────────────────────────────────────────────
cat > "$ROOTFS/etc/issue" <<'EOF'
Welcome to YourXDemon (Debian \n \l)

  Default login:  root  /  yourxdemon
  Change root password:    passwd

  Developed by ExTV (OPX) | Rebranded by OP Aminul FF (OPX)

EOF

# ── Set runlevels via direct symlinks ────────────────────────────────────────
# Debian Trixie uses OpenRC (not systemd) to match our existing init scripts.
# Create runlevel symlinks via direct ln -s (can't chroot into aarch64 to run rc-update).
mkdir -p "$ROOTFS/etc/runlevels/default" "$ROOTFS/etc/runlevels/boot"
for svc in opx-migrate opx-bootstrap opx-network opx-resize dropbear opx-vsock opx-hostd yourxdemon-agentd opx-ready; do
    if [ -e "$ROOTFS/etc/init.d/$svc" ]; then
        ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/default/$svc"
    else
        echo "WARN: init script /etc/init.d/$svc missing, skipping runlevel symlink"
    fi
done

# Disable Alpine-specific services that don't exist or conflict on Debian
for svc in hwclock swclock urandom networking sysctl bootmisc syslog; do
    rm -f "$ROOTFS/etc/runlevels/boot/$svc" "$ROOTFS/etc/runlevels/default/$svc"
done

# Debian-provided procps and cgroups depend on 'mountkernfs' which is an
# Alpine-only OpenRC service. init-yourxdemon already mounts /proc, /sys,
# /dev, and cgroups, so these are redundant and would just fail.
rm -f "$ROOTFS/etc/runlevels/sysinit/procps"
rm -f "$ROOTFS/etc/runlevels/sysinit/cgroups"

# ── Fix merged-usr symlinks (CRITICAL for boot) ─────────────────────────────
# Debian Trixie uses merged /usr: /bin → /usr/bin, /sbin → /usr/sbin.
# debootstrap may create these as empty directories; replace them with
# symlinks so /sbin/init, /sbin/openrc, /bin/sh etc. are resolvable.
rm -rf "$ROOTFS/bin" "$ROOTFS/sbin"
ln -sf usr/bin  "$ROOTFS/bin"
ln -sf usr/sbin "$ROOTFS/sbin"

# ── /sbin/init symlink for busybox init ─────────────────────────────────────
# Debian's OpenRC package provides /sbin/openrc-init but NOT /sbin/init.
# init-yourxdemon does: switch_root /mnt/overlay /sbin/init
# We point /sbin/init → busybox (not openrc-init) because:
#   - busybox init reads /etc/inittab and processes:
#       ::sysinit:/sbin/openrc sysinit  (starts OpenRC)
#       hvc0::respawn:/usr/local/bin/opx-getty hvc0  (starts terminal)
#   - openrc-init ignores inittab → getty never starts → no terminal.
ln -sf /bin/busybox "$ROOTFS/usr/sbin/init"

# ── Ensure busybox symlinks ──────────────────────────────────────────────────
# With merged-usr, /bin/busybox lives at /usr/bin/busybox.
# The /bin → /usr/bin symlink makes /bin/busybox resolvable.
if [ -x "$ROOTFS/usr/bin/busybox" ]; then
    cd "$ROOTFS/usr/bin"
    for cmd in sh ash awk sed grep find sort head tail cat cp mv rm ln chmod chown mkdir mount umount sleep stty kill pgrep; do
        [ -e "$cmd" ] || ln -sf busybox "$cmd"
    done
    cd /work
fi
