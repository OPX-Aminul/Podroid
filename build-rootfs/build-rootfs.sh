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
    2>/dev/null || true

# Install firmware packages if available (non-free).
apt-get install -y --no-install-recommends \
    firmware-realtek firmware-misc-nonfree \
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
cp /work/files/etc/init.d/podroid-bootstrap "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-network   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-resize    "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-ready     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-vsock     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-hostd     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-migrate   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/yourxdemon-agentd "$ROOTFS/etc/init.d/"
chmod +x "$ROOTFS/etc/init.d/podroid-"*
chmod +x "$ROOTFS/etc/init.d/yourxdemon-agentd"

# ── Copy /usr/local/bin scripts ─────────────────────────────────────────────
mkdir -p "$ROOTFS/usr/local/bin"
cp /work/files/usr/local/bin/podroid-resize "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-login  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-getty  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-backup "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-update-stats "$ROOTFS/usr/local/bin/"
# vsock-agent is COPY'd in from the vsock-builder Docker stage.
chmod +x "$ROOTFS/usr/local/bin/podroid-vsock-agent" 2>/dev/null || true
# hostd is also COPY'd from the vsock-builder stage.
chmod +x "$ROOTFS/usr/local/bin/podroid-hostd" 2>/dev/null || true
# yourxdemon-agentd is COPY'd from the vsock-builder stage.
chmod +x "$ROOTFS/usr/local/bin/yourxdemon-agentd" 2>/dev/null || true
# podroid-overlay-normalize is COPY'd from the vsock-builder stage.
chmod +x "$ROOTFS/usr/local/bin/podroid-overlay-normalize" 2>/dev/null || true
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-notify"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-forward"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-open"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-power"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-headless"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-server"
chmod +x "$ROOTFS/usr/local/bin/podroid-"*

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

# ── Profile scripts ──────────────────────────────────────────────────────────
mkdir -p "$ROOTFS/etc/profile.d"
cp /work/files/etc/profile.d/podroid-color.sh "$ROOTFS/etc/profile.d/"
chmod 0644 "$ROOTFS/etc/profile.d/podroid-color.sh"

# ── Hostname ─────────────────────────────────────────────────────────────────
echo "yourxdemon" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost yourxdemon" > "$ROOTFS/etc/hosts"
echo "::1 localhost ip6-localhost" >> "$ROOTFS/etc/hosts"

# ── Login banner ─────────────────────────────────────────────────────────────
cat > "$ROOTFS/etc/issue" <<'EOF'
Welcome to YourXDemon (Debian \n \l)

  Default login:  root  /  yourxdemon
  Change root password:    passwd

  Developed by ExTV (Podroid) | Rebranded by OP Aminul FF (OPX)

EOF

# ── Set runlevels via direct symlinks ────────────────────────────────────────
# Debian Trixie uses OpenRC (not systemd) to match our existing init scripts.
# Create runlevel symlinks via direct ln -s (can't chroot into aarch64 to run rc-update).
mkdir -p "$ROOTFS/etc/runlevels/default" "$ROOTFS/etc/runlevels/boot"
for svc in podroid-migrate podroid-bootstrap podroid-network podroid-resize dropbear podroid-vsock podroid-hostd yourxdemon-agentd podroid-ready; do
    if [ -e "$ROOTFS/etc/init.d/$svc" ]; then
        ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/default/$svc"
    else
        echo "WARN: init script /etc/init.d/$svc missing, skipping runlevel symlink"
    fi
done

# Disable services we don't need
for svc in hwclock swclock urandom networking sysctl bootmisc syslog; do
    rm -f "$ROOTFS/etc/runlevels/boot/$svc" "$ROOTFS/etc/runlevels/default/$svc"
done

# ── Ensure busybox symlinks ──────────────────────────────────────────────────
# Debian's busybox-static doesn't auto-create /bin/sh etc. Link them manually.
if [ -x "$ROOTFS/bin/busybox" ]; then
    cd "$ROOTFS/bin"
    for cmd in sh ash bash awk sed grep find sort head tail cat cp mv rm ln chmod chown mkdir mount umount sleep stty kill pgrep; do
        [ -e "$cmd" ] || ln -sf busybox "$cmd"
    done
    cd /work
fi
