#!/bin/bash
#
# build.sh — Build VCam tweak and package as .deb
#
# USAGE:
#   chmod +x build.sh
#   ./build.sh              # Build trên macOS với Theos
#   ./build.sh ondevice     # Build trực tiếp trên thiết bị jailbreak
#   ./build.sh clean        # Xoá build artifacts
#   ./build.sh package      # Chỉ đóng gói .deb (không compile lại)
#
# YÊU CẦU:
#   - macOS: Theos + Xcode Command Line Tools
#   - On-device: Theos + build-essential (từ Procursus/Elucubratus)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PACKAGE_ID="com.vcam.qatool"
PACKAGE_NAME="VCam"
PACKAGE_VERSION="1.0.0"
ARCH="iphoneos-arm64"

log()  { echo -e "${GREEN}[VCam]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# Kiểm tra môi trường
# =============================================================================
check_theos() {
    if [ -z "$THEOS" ]; then
        if [ -d "$HOME/theos" ]; then
            export THEOS="$HOME/theos"
        elif [ -d "/var/jb/opt/theos" ]; then
            export THEOS="/var/jb/opt/theos"
        elif [ -d "/opt/theos" ]; then
            export THEOS="/opt/theos"
        else
            err "Theos not found. Set \$THEOS or install: bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)\""
        fi
    fi
    log "Theos: $THEOS"

    if [ ! -f "$THEOS/makefiles/common.mk" ]; then
        err "Theos installation broken — missing common.mk"
    fi
}

check_sdk() {
    local sdk_dir="$THEOS/sdks"
    if [ ! -d "$sdk_dir" ] || [ -z "$(ls -A "$sdk_dir" 2>/dev/null)" ]; then
        warn "No iOS SDK found in $sdk_dir"
        warn "Download: https://github.com/theos/sdks"
        warn "Place iPhoneOS*.sdk in $THEOS/sdks/"
        err "Missing iOS SDK"
    fi
    log "SDK found: $(ls "$sdk_dir" | head -1)"
}

check_dpkg() {
    if ! command -v dpkg-deb &>/dev/null; then
        if command -v dpkg &>/dev/null; then
            log "dpkg available"
        else
            err "dpkg-deb not found. Install: brew install dpkg (macOS) or apt install dpkg (Linux/device)"
        fi
    fi
}

# =============================================================================
# Clean
# =============================================================================
do_clean() {
    log "Cleaning build artifacts..."
    make clean 2>/dev/null || true
    rm -rf .theos packages obj
    log "Clean done."
}

# =============================================================================
# Build với Theos
# =============================================================================
do_build_theos() {
    check_theos
    check_sdk

    log "Building with Theos (rootless)..."
    log "Package: $PACKAGE_ID v$PACKAGE_VERSION ($ARCH)"

    export THEOS_PACKAGE_SCHEME=rootless

    make clean 2>/dev/null || true
    make -j$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

    log "Compile done. Packaging..."
    make package FINALPACKAGE=1

    local deb_file=$(ls packages/*.deb 2>/dev/null | head -1)
    if [ -n "$deb_file" ]; then
        log "========================================="
        log "BUILD SUCCESS"
        log "Package: $deb_file"
        log "Size: $(du -h "$deb_file" | cut -f1)"
        log "========================================="
        echo ""
        log "Cài đặt trên thiết bị:"
        log "  scp $deb_file root@<IP>:/var/jb/tmp/"
        log "  ssh root@<IP> 'dpkg -i /var/jb/tmp/$(basename "$deb_file") && killall -9 SpringBoard'"
    else
        err "No .deb file produced!"
    fi
}

# =============================================================================
# Build trên thiết bị (on-device)
# =============================================================================
do_build_ondevice() {
    log "Building on-device..."

    if [ ! -d "/var/jb" ]; then
        err "Not a rootless jailbreak (no /var/jb)"
    fi

    check_theos
    check_sdk

    export THEOS_PACKAGE_SCHEME=rootless

    make clean 2>/dev/null || true
    make -j$(nproc 2>/dev/null || echo 2)
    make package FINALPACKAGE=1

    local deb_file=$(ls packages/*.deb 2>/dev/null | head -1)
    if [ -n "$deb_file" ]; then
        log "BUILD SUCCESS: $deb_file"
        echo ""
        read -p "Install now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            dpkg -i "$deb_file"
            uicache -a 2>/dev/null || true
            log "Installed. Respring now..."
            killall -9 SpringBoard
        fi
    else
        err "Build failed — no .deb produced"
    fi
}

# =============================================================================
# Đóng gói .deb thủ công (không cần Theos compile)
# Dùng khi đã có file .dylib sẵn
# =============================================================================
do_manual_package() {
    log "Manual .deb packaging..."
    bash "$(dirname "$0")/manual-package.sh"
}

# =============================================================================
# Main
# =============================================================================
case "${1:-build}" in
    clean)
        do_clean
        ;;
    ondevice)
        do_build_ondevice
        ;;
    package)
        do_manual_package
        ;;
    build|*)
        do_build_theos
        ;;
esac
