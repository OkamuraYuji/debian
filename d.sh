#!/bin/sh
mkdir -p yjing
ROOTFS_DIR=$(pwd)/yjing
ARCH=$(uname -m)

case "$ARCH" in
  "x86_64")  ARCH_ALT="amd64" ;;
  "aarch64") ARCH_ALT="arm64" ;;
  *) 
    echo "Unsupported: $ARCH"
    exit 1 
    ;;
esac


export PATH="$PATH:$HOME/.local/usr/bin"
INSTALL_MARKER="$ROOTFS_DIR/.installed"

if [ ! -e "$INSTALL_MARKER" ]; then
  DEBIAN_URL="https://images.linuxcontainers.org/images/debian/bookworm/${ARCH_ALT}/default/"
  html_content=$(curl -s $DEBIAN_URL)
  LATEST=$(echo "$html_content" | grep -oP 'href="\d{8}_\d{2}%3A\d{2}/"' | sed -E 's/href="([0-9]{8}_[0-9]{2}%3A[0-9]{2})\//\1/' | sort -r | head -n 1)
  LATEST=$(echo "$LATEST" | sed 's/"//')
  
  [ -z "$LATEST" ] && { echo "Could not find the latest version."; exit 1; }
  ROOTFS_FILE="/tmp/rootfs.tar.xz"
  
  download() {
    wget -q --tries=3 --timeout=1 --no-hsts -O "$2" "$1" || { echo "Error downloading $1"; return 1; }
  }
  download "${DEBIAN_URL}${LATEST}/rootfs.tar.xz" "$ROOTFS_FILE" || {
    for i in $(seq 1 3); do
      sleep 1
      download "${DEBIAN_URL}${LATEST}/rootfs.tar.xz" "$ROOTFS_FILE" && break
      [ $i -eq 3 ] && { echo "Failed to download rootfs.tar.xz after 3 attempts."; exit 1; }
    done
  }
  tar -xf "$ROOTFS_FILE" -C "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR/usr/local/bin"
  
  PROOT_PATH="$ROOTFS_DIR/usr/local/bin/proot"
  
  download "https://raw.githubusercontent.com/OkamuraYuji/debian/main/proot-${ARCH}" "$PROOT_PATH" || {
    for i in $(seq 1 3); do
      sleep 1
      download "https://raw.githubusercontent.com/OkamuraYuji/debian/main/proot-${ARCH}" "$PROOT_PATH" && break
      [ $i -eq 3 ] && { echo "Failed to download proot-${ARCH} after 3 attempts."; exit 1; }
    done
  }
  [ ! -f "$PROOT_PATH" ] && { echo "proot file not downloaded"; exit 1; }
  chmod 755 "$PROOT_PATH"
  echo "nameserver 1.1.1.1
nameserver 1.0.0.1" > "${ROOTFS_DIR}/etc/resolv.conf"
  
  rm -f "$ROOTFS_FILE"
  rm -rf /tmp/sbin
  touch "$INSTALL_MARKER"
fi

[ ! -w "$ROOTFS_DIR" ] && { echo "Permission denied: Cannot write to $ROOTFS_DIR"; exit 1; }

clear
exec "$ROOTFS_DIR/usr/local/bin/proot" \
  --rootfs="${ROOTFS_DIR}" \
  -0 -w "/root" \
  -b /dev -b /sys -b /proc -b /etc/resolv.conf \
  --kill-on-exit \
  env HOME=/root /bin/bash
