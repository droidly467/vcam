#!/bin/bash
#
# manual-package.sh — Đóng gói .deb thủ công KHÔNG CẦN THEOS
#
# Script này tạo cấu trúc .deb hoàn chỉnh bằng dpkg-deb.
# Dùng khi:
#   1. Đã compile xong .dylib (bằng Theos hoặc cross-compile)
#   2. Muốn đóng gói lại sau khi chỉnh sửa
#   3. Build trên máy không có Theos nhưng có dpkg
#
# USAGE:
#   chmod +x manual-package.sh
#   ./manual-package.sh                              # Tự tìm .dylib trong .theos
#   ./manual-package.sh /path/to/VCam.dylib          # Chỉ định .dylib cụ thể
#   DYLIB=/path/to/VCam.dylib ./manual-package.sh    # Qua env var

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[Package]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ID="com.vcam.qatool"
VERSION="1.0.0"

# =============================================================================
# Tìm dylib
# =============================================================================
DYLIB_PATH="${1:-${DYLIB:-}}"

if [ -z "$DYLIB_PATH" ]; then
    # Tự tìm trong .theos build output
    CANDIDATES=(
        "$SCRIPT_DIR/.theos/obj/debug/${PACKAGE_ID}.dylib"
        "$SCRIPT_DIR/.theos/obj/${PACKAGE_ID}.dylib"
        "$SCRIPT_DIR/.theos/obj/debug/VCam.dylib"
        "$SCRIPT_DIR/.theos/obj/VCam.dylib"
        "$SCRIPT_DIR/obj/VCam.dylib"
        "$SCRIPT_DIR/VCam.dylib"
    )
    for c in "${CANDIDATES[@]}"; do
        if [ -f "$c" ]; then
            DYLIB_PATH="$c"
            break
        fi
    done
fi

if [ -z "$DYLIB_PATH" ] || [ ! -f "$DYLIB_PATH" ]; then
    warn "Dylib not found. Searching..."
    FOUND=$(find "$SCRIPT_DIR" -name "VCam.dylib" -o -name "${PACKAGE_ID}.dylib" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        DYLIB_PATH="$FOUND"
    else
        err "Cannot find VCam.dylib. Build first with: make
Or specify: $0 /path/to/VCam.dylib"
    fi
fi

log "Using dylib: $DYLIB_PATH"

# Tìm prefs bundle
PREFS_BUNDLE=""
PREFS_CANDIDATES=(
    "$SCRIPT_DIR/.theos/obj/VCamPrefs.bundle"
    "$SCRIPT_DIR/.theos/obj/debug/VCamPrefs.bundle"
    "$SCRIPT_DIR/Preferences/.theos/obj/VCamPrefs.bundle"
)
for c in "${PREFS_CANDIDATES[@]}"; do
    if [ -d "$c" ]; then
        PREFS_BUNDLE="$c"
        break
    fi
done

# =============================================================================
# Tạo cấu trúc package
# =============================================================================
BUILD_DIR="$SCRIPT_DIR/_build_deb"
STAGE="$BUILD_DIR/stage"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$STAGE/DEBIAN"

# ---------- DEBIAN/control ----------
cat > "$STAGE/DEBIAN/control" << 'CTRL'
Package: com.vcam.qatool
Name: VCam - Virtual Camera QA Tool
Version: 1.0.0
Architecture: iphoneos-arm64
Description: Internal QA/testing virtual camera tweak for iOS. Provides simulated camera feed from local media files for testing app camera pipelines.
Maintainer: QA Team <qa@internal.test>
Author: QA Team <qa@internal.test>
Section: Tweaks
Depends: mobilesubstrate (>= 0.9.5000), firmware (>= 15.0), preferenceloader
Tag: role::hacker
CTRL

# ---------- DEBIAN/postinst ----------
cat > "$STAGE/DEBIAN/postinst" << 'POST'
#!/bin/sh
# Post-installation: tạo thư mục media và set permissions

MEDIA_DIR="/var/jb/var/mobile/Library/VCamMedia"
PREFS_DIR="/var/jb/var/mobile/Library/Preferences"

mkdir -p "$MEDIA_DIR"
chown mobile:mobile "$MEDIA_DIR"
chmod 755 "$MEDIA_DIR"

mkdir -p "$PREFS_DIR"

# Tạo default config nếu chưa có
PLIST="$PREFS_DIR/com.vcam.qatool.plist"
if [ ! -f "$PLIST" ]; then
    cat > "$PLIST" << 'PLIST_CONTENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>tweakEnabled</key>
    <true/>
    <key>globalEnabled</key>
    <true/>
    <key>watermarkEnabled</key>
    <true/>
    <key>loopVideo</key>
    <true/>
    <key>debugLogEnabled</key>
    <true/>
    <key>simulatedPosition</key>
    <integer>2</integer>
    <key>mediaType</key>
    <integer>0</integer>
    <key>mediaFilePath</key>
    <string></string>
    <key>allowedBundleIDs</key>
    <array/>
    <key>bypassDetectionEnabled</key>
    <false/>
</dict>
</plist>
PLIST_CONTENT
    chown mobile:mobile "$PLIST"
    chmod 644 "$PLIST"
fi

echo "[VCam] Post-install complete. Respring required."
exit 0
POST
chmod 755 "$STAGE/DEBIAN/postinst"

# ---------- DEBIAN/postrm ----------
cat > "$STAGE/DEBIAN/postrm" << 'POSTRM'
#!/bin/sh
# Post-removal: cleanup (giữ lại media files và config cho user)

echo "[VCam] Removed. Media files preserved at /var/jb/var/mobile/Library/VCamMedia/"
echo "[VCam] To fully clean: rm -rf /var/jb/var/mobile/Library/VCamMedia/ /var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist"
exit 0
POSTRM
chmod 755 "$STAGE/DEBIAN/postrm"

# ---------- Tweak dylib ----------
# Rootless path: /var/jb/Library/MobileSubstrate/DynamicLibraries/
DYLIB_DIR="$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DYLIB_DIR"
cp "$DYLIB_PATH" "$DYLIB_DIR/VCam.dylib"
log "Copied dylib"

# ---------- Filter plist ----------
cat > "$DYLIB_DIR/VCam.plist" << 'FILTER'
{ Filter = { Bundles = ( "com.apple.UIKit" ); }; }
FILTER
log "Created filter plist"

# ---------- Preferences bundle ----------
PREFS_DEST="$STAGE/var/jb/Library/PreferenceBundles"
mkdir -p "$PREFS_DEST"

if [ -n "$PREFS_BUNDLE" ] && [ -d "$PREFS_BUNDLE" ]; then
    cp -R "$PREFS_BUNDLE" "$PREFS_DEST/VCamPrefs.bundle"
    log "Copied compiled prefs bundle"
else
    # Tạo prefs bundle từ source files
    warn "Pre-compiled prefs bundle not found, creating from source..."
    BUNDLE="$PREFS_DEST/VCamPrefs.bundle"
    mkdir -p "$BUNDLE"

    # Copy plist resources
    if [ -d "$SCRIPT_DIR/Preferences/Resources" ]; then
        cp -R "$SCRIPT_DIR/Preferences/Resources/"* "$BUNDLE/"
    fi

    if [ -f "$SCRIPT_DIR/Preferences/entry.plist" ]; then
        cp "$SCRIPT_DIR/Preferences/entry.plist" "$BUNDLE/"
    fi

    # Info.plist cho bundle
    cat > "$BUNDLE/Info.plist" << 'BINFO'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vcam.qatool.prefs</string>
    <key>CFBundleName</key>
    <string>VCamPrefs</string>
    <key>CFBundleExecutable</key>
    <string>VCamPrefs</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>NSPrincipalClass</key>
    <string>VCamRootListController</string>
</dict>
</plist>
BINFO
    warn "NOTE: Prefs bundle needs compiled binary. Settings UI may not work without it."
    warn "Build prefs with Theos first, then re-run this script."
fi

# ---------- PreferenceLoader entry ----------
PREFLOADER_DIR="$STAGE/var/jb/Library/PreferenceLoader/Preferences"
mkdir -p "$PREFLOADER_DIR"
cat > "$PREFLOADER_DIR/VCam.plist" << 'PLENTRY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>entry</key>
    <dict>
        <key>bundle</key>
        <string>VCamPrefs</string>
        <key>cell</key>
        <string>PSLinkCell</string>
        <key>detail</key>
        <string>VCamRootListController</string>
        <key>isController</key>
        <true/>
        <key>label</key>
        <string>VCam</string>
    </dict>
</dict>
</plist>
PLENTRY
log "Created PreferenceLoader entry"

# ---------- Media directory placeholder ----------
MEDIA_DIR="$STAGE/var/jb/var/mobile/Library/VCamMedia"
mkdir -p "$MEDIA_DIR"
cat > "$MEDIA_DIR/.vcam_readme" << 'MREADME'
VCam Media Directory
====================
Place your test media files here:
  - Images: .jpg, .jpeg, .png, .heic
  - Videos: .mp4, .mov, .m4v

Then configure the filename in Settings > VCam > Media Filename.

Example:
  1. Copy test_face.mp4 here
  2. Settings > VCam > Media Type = Video
  3. Settings > VCam > Media Filename = test_face.mp4
  4. Open target app camera
MREADME
log "Created media directory"

# =============================================================================
# Build .deb
# =============================================================================
OUTPUT_DIR="$SCRIPT_DIR/packages"
mkdir -p "$OUTPUT_DIR"
DEB_NAME="${PACKAGE_ID}_${VERSION}_${ARCH:-iphoneos-arm64}.deb"
OUTPUT="$OUTPUT_DIR/$DEB_NAME"

# Fix permissions
find "$STAGE" -type d -exec chmod 755 {} \;
find "$STAGE" -type f -exec chmod 644 {} \;
chmod 755 "$STAGE/DEBIAN/postinst"
chmod 755 "$STAGE/DEBIAN/postrm"
if [ -f "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/VCam.dylib" ]; then
    chmod 755 "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/VCam.dylib"
fi

# Package
dpkg-deb -Zxz --root-owner-group -b "$STAGE" "$OUTPUT" 2>/dev/null || \
dpkg-deb -Zgzip --root-owner-group -b "$STAGE" "$OUTPUT" 2>/dev/null || \
dpkg-deb --root-owner-group -b "$STAGE" "$OUTPUT" 2>/dev/null || \
dpkg-deb -b "$STAGE" "$OUTPUT"

if [ -f "$OUTPUT" ]; then
    echo ""
    log "========================================="
    log "   PACKAGE BUILD SUCCESS"
    log "========================================="
    log "File: $OUTPUT"
    log "Size: $(du -h "$OUTPUT" | cut -f1)"
    echo ""
    log "Verify contents:"
    dpkg-deb -c "$OUTPUT" 2>/dev/null | head -20 || true
    echo ""
    log "========================================="
    log "   CÀI ĐẶT"
    log "========================================="
    log ""
    log "Cách 1 — SCP + dpkg:"
    log "  scp $OUTPUT root@<DEVICE_IP>:/var/jb/tmp/"
    log "  ssh root@<DEVICE_IP>"
    log "  dpkg -i /var/jb/tmp/$DEB_NAME"
    log "  uicache -a"
    log "  killall -9 SpringBoard"
    log ""
    log "Cách 2 — Filza:"
    log "  1. AirDrop/copy file .deb vào thiết bị"
    log "  2. Mở Filza, tìm file .deb"
    log "  3. Tap > Install"
    log "  4. Respring"
    log ""
    log "Cách 3 — Sileo (local repo):"
    log "  1. Copy .deb vào /var/jb/var/mobile/Documents/"
    log "  2. Dùng terminal: dpkg -i /var/jb/var/mobile/Documents/$DEB_NAME"
    log "  3. Mở Sileo > Installed > VCam sẽ hiển thị"
    log ""
    log "========================================="
else
    err "Failed to create .deb file!"
fi

# Cleanup
rm -rf "$BUILD_DIR"
log "Build directory cleaned up."
