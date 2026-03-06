#!/bin/bash
#
# manual-package-nocompile.sh
# Đóng gói .deb mà KHÔNG cần compile dylib
# Tạo package có đầy đủ structure, prefs plist, postinst
# Dylib sẽ được thay bằng placeholder — bạn cần compile riêng hoặc
# dùng script này khi đã có dylib từ nguồn khác
#
# Mục đích: tạo .deb structure hợp lệ để test quy trình cài đặt
#
set -e

echo "[VCam] Đóng gói .deb thủ công (không compile)..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$SCRIPT_DIR/_deb_build"
STAGE="$BUILD/root"
OUTPUT_DIR="$SCRIPT_DIR/packages"
DEB_NAME="com.vcam.qatool_1.0.0_iphoneos-arm64.deb"

rm -rf "$BUILD"
mkdir -p "$STAGE/DEBIAN"
mkdir -p "$OUTPUT_DIR"

# ===== DEBIAN/control =====
cat > "$STAGE/DEBIAN/control" << 'EOF'
Package: com.vcam.qatool
Name: VCam - Virtual Camera QA Tool
Version: 1.0.0
Architecture: iphoneos-arm64
Description: Internal QA/testing virtual camera tweak for iOS. Provides simulated camera feed from local media files.
Maintainer: QA Team <qa@internal.test>
Author: QA Team <qa@internal.test>
Section: Tweaks
Depends: mobilesubstrate (>= 0.9.5000), firmware (>= 15.0), preferenceloader
Tag: role::hacker
EOF

# ===== DEBIAN/postinst =====
cat > "$STAGE/DEBIAN/postinst" << 'POSTEOF'
#!/bin/sh
MEDIA_DIR="/var/jb/var/mobile/Library/VCamMedia"
PREFS_DIR="/var/jb/var/mobile/Library/Preferences"
PLIST="$PREFS_DIR/com.vcam.qatool.plist"

mkdir -p "$MEDIA_DIR"
chown mobile:mobile "$MEDIA_DIR"
chmod 755 "$MEDIA_DIR"
mkdir -p "$PREFS_DIR"

if [ ! -f "$PLIST" ]; then
cat > "$PLIST" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>tweakEnabled</key><true/>
    <key>globalEnabled</key><true/>
    <key>watermarkEnabled</key><true/>
    <key>loopVideo</key><true/>
    <key>debugLogEnabled</key><true/>
    <key>simulatedPosition</key><integer>2</integer>
    <key>mediaType</key><integer>0</integer>
    <key>mediaFilePath</key><string></string>
    <key>allowedBundleIDs</key><array/>
    <key>bypassDetectionEnabled</key><false/>
</dict>
</plist>
PLISTEOF
chown mobile:mobile "$PLIST"
chmod 644 "$PLIST"
fi
echo "[VCam] Installed. Respring to activate."
exit 0
POSTEOF
chmod 755 "$STAGE/DEBIAN/postinst"

# ===== DEBIAN/postrm =====
cat > "$STAGE/DEBIAN/postrm" << 'RMEOF'
#!/bin/sh
rm -f /var/jb/var/mobile/Library/VCamMedia/vcam.log
rm -f /var/jb/var/mobile/Library/VCamMedia/vcam.log.old
echo "[VCam] Removed. Media files preserved."
exit 0
RMEOF
chmod 755 "$STAGE/DEBIAN/postrm"

# ===== Dylib + filter (placeholder) =====
DYLIB_DIR="$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DYLIB_DIR"

# Tạo placeholder dylib nếu không có compiled version
if [ -f "$SCRIPT_DIR/VCam.dylib" ]; then
    cp "$SCRIPT_DIR/VCam.dylib" "$DYLIB_DIR/VCam.dylib"
    echo "[VCam] Dùng VCam.dylib có sẵn"
elif [ -f "$SCRIPT_DIR/.theos/obj/debug/VCam.dylib" ]; then
    cp "$SCRIPT_DIR/.theos/obj/debug/VCam.dylib" "$DYLIB_DIR/VCam.dylib"
    echo "[VCam] Dùng VCam.dylib từ .theos build"
else
    echo "[VCam] WARNING: Không tìm thấy VCam.dylib!"
    echo "[VCam] Package sẽ không có tweak binary."
    echo "[VCam] Bạn cần compile trên macOS/device rồi copy VCam.dylib vào thư mục project."
    # Tạo empty placeholder để package vẫn hợp lệ
    touch "$DYLIB_DIR/VCam.dylib"
fi

cat > "$DYLIB_DIR/VCam.plist" << 'FEOF'
{ Filter = { Bundles = ( "com.apple.UIKit" ); }; }
FEOF

# ===== PreferenceLoader entry =====
PL_DIR="$STAGE/var/jb/Library/PreferenceLoader/Preferences"
mkdir -p "$PL_DIR"
cat > "$PL_DIR/VCam.plist" << 'PLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>entry</key>
    <dict>
        <key>bundle</key><string>VCamPrefs</string>
        <key>cell</key><string>PSLinkCell</string>
        <key>detail</key><string>VCamRootListController</string>
        <key>isController</key><true/>
        <key>label</key><string>VCam</string>
    </dict>
</dict>
</plist>
PLEOF

# ===== Prefs bundle (plist only, no binary) =====
PREFS_DIR="$STAGE/var/jb/Library/PreferenceBundles/VCamPrefs.bundle"
mkdir -p "$PREFS_DIR"

cp "$SCRIPT_DIR/Preferences/Resources/Root.plist" "$PREFS_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/Preferences/Resources/Info.plist" "$PREFS_DIR/" 2>/dev/null || true

# ===== Media directory =====
MEDIA="$STAGE/var/jb/var/mobile/Library/VCamMedia"
mkdir -p "$MEDIA"
echo "Place test media files here (.jpg .png .mp4 .mov)" > "$MEDIA/.readme"

# ===== Fix permissions =====
find "$STAGE" -type d -exec chmod 755 {} \;
find "$STAGE" -type f -exec chmod 644 {} \;
chmod 755 "$STAGE/DEBIAN/postinst"
chmod 755 "$STAGE/DEBIAN/postrm"
[ -f "$DYLIB_DIR/VCam.dylib" ] && chmod 755 "$DYLIB_DIR/VCam.dylib"

# ===== Build .deb =====
dpkg-deb -Zxz --root-owner-group -b "$STAGE" "$OUTPUT_DIR/$DEB_NAME" 2>/dev/null || \
dpkg-deb -Zgzip --root-owner-group -b "$STAGE" "$OUTPUT_DIR/$DEB_NAME" 2>/dev/null || \
dpkg-deb --root-owner-group -b "$STAGE" "$OUTPUT_DIR/$DEB_NAME" 2>/dev/null || \
dpkg-deb -b "$STAGE" "$OUTPUT_DIR/$DEB_NAME"

rm -rf "$BUILD"

if [ -f "$OUTPUT_DIR/$DEB_NAME" ]; then
    echo ""
    echo "============================================"
    echo " THANH CONG!"
    echo " File: $OUTPUT_DIR/$DEB_NAME"
    echo " Size: $(du -h "$OUTPUT_DIR/$DEB_NAME" | cut -f1)"
    echo "============================================"
    echo ""
    echo " Copy lên thiết bị:"
    echo "   scp $OUTPUT_DIR/$DEB_NAME root@<IP>:/var/jb/tmp/"
    echo "   ssh root@<IP> 'dpkg -i /var/jb/tmp/$DEB_NAME && killall -9 SpringBoard'"
else
    echo "[ERROR] Không tạo được .deb!"
    exit 1
fi
