#!/bin/bash
# VCam WSL Build Script — chạy trong WSL để build .deb
# Usage: wsl -d Ubuntu -- bash /mnt/c/Users/hieum/Desktop/vcam/vcam/wsl-build.sh
set -e

echo "============================================"
echo " VCam Build — Installing dependencies..."
echo "============================================"

export DEBIAN_FRONTEND=noninteractive

# Cài tools cần thiết
apt-get update -qq
apt-get install -y -qq build-essential fakeroot dpkg git curl rsync perl clang llvm \
    libxml2 zlib1g-dev libtinfo5 2>/dev/null || \
apt-get install -y -qq build-essential fakeroot dpkg git curl rsync perl clang llvm \
    libxml2 zlib1g-dev 2>/dev/null

echo "============================================"
echo " Installing Theos..."
echo "============================================"

export THEOS=/opt/theos

if [ ! -d "$THEOS" ]; then
    git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
fi

# Cài iOS SDK
if [ -z "$(ls -A $THEOS/sdks/*.sdk 2>/dev/null)" ]; then
    echo "Downloading iOS SDK..."
    cd "$THEOS/sdks"
    curl -sLO https://github.com/theos/sdks/archive/master.zip
    unzip -q master.zip
    mv sdks-master/*.sdk . 2>/dev/null || true
    rm -rf sdks-master master.zip
fi

echo "SDK: $(ls $THEOS/sdks/ | head -1)"

# Cài toolchain nếu chưa có
if [ ! -d "$THEOS/toolchain" ] || [ -z "$(ls -A $THEOS/toolchain/ 2>/dev/null)" ]; then
    echo "Downloading toolchain..."
    cd "$THEOS"
    # Linux toolchain
    curl -sLO https://github.com/CRKatri/llvm-project/releases/download/swift-5.3.2-RELEASE/linux-arm64e.tar.zst 2>/dev/null || true
    # Fallback: dùng system clang
fi

echo "============================================"
echo " Building VCam..."
echo "============================================"

PROJECT_DIR="/mnt/c/Users/hieum/Desktop/vcam/vcam"
cd "$PROJECT_DIR"

export PATH=$THEOS/bin:$PATH

# Clean và build
make clean 2>/dev/null || true
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless 2>&1

DEB=$(ls packages/*.deb 2>/dev/null | head -1)
if [ -n "$DEB" ]; then
    echo ""
    echo "============================================"
    echo " BUILD THANH CONG!"
    echo " File: $DEB"
    echo " Size: $(du -h "$DEB" | cut -f1)"
    echo "============================================"
    # Copy ra Desktop
    cp "$DEB" "/mnt/c/Users/hieum/Desktop/" 2>/dev/null || true
    echo " Da copy ra Desktop!"
else
    echo ""
    echo "============================================"
    echo " Theos build that bai."
    echo " Thu dong goi thu cong..."
    echo "============================================"
    # Fallback: đóng gói thủ công không cần compile
    bash "$PROJECT_DIR/manual-package-nocompile.sh"
fi
