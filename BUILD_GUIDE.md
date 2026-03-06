# VCam — Hướng Dẫn Build & Cài Đặt .deb

## Tóm tắt: Bạn cần gì?

| Bạn có | Cách build |
|--------|-----------|
| Mac có Xcode | **Cách 1** — Build trên macOS |
| iPhone jailbreak | **Cách 2** — Build trên thiết bị |
| Linux/WSL | **Cách 3** — Cross-compile |
| Chỉ có Windows | **Cách 4** — Dùng GitHub Actions |

---

## Cách 1: Build trên macOS (Khuyến nghị)

### Bước 1: Cài Theos

```bash
# Cài Xcode Command Line Tools (nếu chưa có)
xcode-select --install

# Cài Theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"

# Thêm vào shell profile (~/.zshrc hoặc ~/.bashrc)
echo 'export THEOS=~/theos' >> ~/.zshrc
echo 'export PATH=$THEOS/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

### Bước 2: Cài iOS SDK

```bash
# Tải SDK
cd $THEOS/sdks
curl -LO https://github.com/theos/sdks/archive/master.zip
unzip master.zip
mv sdks-master/*.sdk .
rm -rf sdks-master master.zip

# Kiểm tra
ls $THEOS/sdks/
# Phải thấy: iPhoneOS16.5.sdk hoặc tương tự
```

### Bước 3: Copy project & Build

```bash
# Copy thư mục vcam vào Mac
# (dùng SCP, USB, AirDrop, git, v.v.)

cd /path/to/vcam

# Build
make clean
make package FINALPACKAGE=1

# Kết quả
ls -la packages/
# → com.vcam.qatool_1.0.0_iphoneos-arm64.deb
```

### Bước 4: Copy .deb lên thiết bị & cài

```bash
# Lấy IP thiết bị (Settings > Wi-Fi > tap (i))
DEVICE_IP=192.168.1.xxx

# Copy file
scp packages/com.vcam.qatool_1.0.0_iphoneos-arm64.deb root@$DEVICE_IP:/var/jb/tmp/

# SSH vào thiết bị và cài
ssh root@$DEVICE_IP
dpkg -i /var/jb/tmp/com.vcam.qatool_1.0.0_iphoneos-arm64.deb
uicache -a
killall -9 SpringBoard
```

**Hoặc dùng make install trực tiếp:**
```bash
make do THEOS_DEVICE_IP=192.168.1.xxx THEOS_DEVICE_PORT=22
```

---

## Cách 2: Build trực tiếp trên thiết bị jailbreak

### Bước 1: Cài build tools từ Sileo/Zebra

Mở Sileo, thêm repo nếu cần, rồi cài các package:

```
- Theos Dependencies (từ repo Procursus)
- make
- clang (hoặc Apple LLVM)
- ldid
- dpkg
- git
```

Hoặc qua terminal:
```bash
apt update
apt install theos make clang ldid dpkg git -y
```

### Bước 2: Cài Theos trên thiết bị

```bash
# SSH vào thiết bị
ssh root@<DEVICE_IP>    # password mặc định: alpine

# Cài Theos
git clone --recursive https://github.com/theos/theos.git /var/jb/opt/theos
echo 'export THEOS=/var/jb/opt/theos' >> ~/.profile
echo 'export PATH=$THEOS/bin:$PATH' >> ~/.profile
source ~/.profile
```

### Bước 3: Copy source & Build

```bash
# Copy toàn bộ thư mục vcam vào thiết bị
# (qua SCP, Filza, SSH, v.v.)
scp -r /path/to/vcam root@<DEVICE_IP>:/var/jb/var/mobile/vcam

# Trên thiết bị
ssh root@<DEVICE_IP>
cd /var/jb/var/mobile/vcam

# Build
chmod +x build.sh
./build.sh ondevice

# Hoặc thủ công:
make clean
make package FINALPACKAGE=1
dpkg -i packages/*.deb
uicache -a
killall -9 SpringBoard
```

---

## Cách 3: Cross-compile từ Linux/WSL

### Bước 1: Cài Theos trên Linux

```bash
# Ubuntu/Debian
sudo apt install build-essential fakeroot rsync curl git perl clang

# Cài Theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
export THEOS=~/theos
```

### Bước 2: Cài iOS toolchain

```bash
# Theos tự cài toolchain khi chạy lần đầu
# Hoặc cài thủ công:
$THEOS/bin/update-theos

# Cài SDK
cd $THEOS/sdks
curl -LO https://github.com/theos/sdks/archive/master.zip
unzip master.zip && mv sdks-master/*.sdk . && rm -rf sdks-master master.zip
```

### Bước 3: Build

```bash
cd /path/to/vcam
make package FINALPACKAGE=1
```

### Nếu dùng WSL trên Windows:

```bash
# Mở WSL (Ubuntu)
wsl

# Cài dependencies
sudo apt update && sudo apt install -y build-essential fakeroot rsync curl git perl clang dpkg

# Cài Theos
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
echo 'export THEOS=~/theos' >> ~/.bashrc && source ~/.bashrc

# Vào thư mục project (Windows path → WSL path)
cd /mnt/c/Users/hieum/Desktop/vcam/vcam

# Build
make clean && make package FINALPACKAGE=1

# File .deb sẽ ở: packages/
ls -la packages/
```

---

## Cách 4: Build bằng GitHub Actions (không cần Mac/Linux)

### Bước 1: Tạo GitHub repo

1. Push thư mục `vcam` lên GitHub
2. Tạo file `.github/workflows/build.yml`:

```yaml
name: Build VCam .deb
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Theos
        run: |
          bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
          echo "THEOS=$HOME/theos" >> $GITHUB_ENV

      - name: Install SDK
        run: |
          cd $THEOS/sdks
          curl -LO https://github.com/theos/sdks/archive/master.zip
          unzip -q master.zip
          mv sdks-master/*.sdk .
          rm -rf sdks-master master.zip

      - name: Build
        run: |
          make package FINALPACKAGE=1

      - name: Upload .deb
        uses: actions/upload-artifact@v4
        with:
          name: vcam-deb
          path: packages/*.deb
```

### Bước 2: Push & Download

1. Push code lên GitHub
2. Vào **Actions** tab, chờ build xong
3. Download file `.deb` từ **Artifacts**
4. Copy lên thiết bị và cài

---

## Sau khi có file .deb — Cài đặt qua Sileo

### Cách A: dpkg trực tiếp (nhanh nhất)

```bash
# SSH vào thiết bị
ssh root@<DEVICE_IP>

# Cài
dpkg -i /path/to/com.vcam.qatool_1.0.0_iphoneos-arm64.deb

# Refresh
uicache -a
killall -9 SpringBoard
```

### Cách B: Qua Filza

1. Copy file `.deb` vào thiết bị (AirDrop, SCP, iCloud, v.v.)
2. Mở **Filza File Manager**
3. Tìm file `.deb`
4. Tap vào file → **Install**
5. Respring

### Cách C: Local Sileo repo

```bash
# Trên thiết bị, tạo local repo
mkdir -p /var/jb/var/mobile/repo/debs
cp /path/to/*.deb /var/jb/var/mobile/repo/debs/

# Tạo Packages index
cd /var/jb/var/mobile/repo
dpkg-scanpackages debs /dev/null > Packages
gzip -k Packages

# Trong Sileo: thêm repo file:///var/jb/var/mobile/repo/
# VCam sẽ xuất hiện trong Sileo để cài
```

---

## Kiểm tra cài đặt thành công

```bash
# SSH vào thiết bị rồi chạy:

# 1. Kiểm tra dylib
ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/VCam.*
# Phải thấy: VCam.dylib và VCam.plist

# 2. Kiểm tra prefs bundle
ls -la /var/jb/Library/PreferenceBundles/VCamPrefs.bundle/
# Phải thấy: VCamPrefs (binary), Root.plist, Info.plist

# 3. Kiểm tra PreferenceLoader entry
ls -la /var/jb/Library/PreferenceLoader/Preferences/VCam.plist

# 4. Kiểm tra media directory
ls -la /var/jb/var/mobile/Library/VCamMedia/

# 5. Kiểm tra config
cat /var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist

# 6. Kiểm tra log (sau khi mở một app camera)
cat /var/jb/var/mobile/Library/VCamMedia/vcam.log
```

---

## Setup media test

```bash
# Copy video test lên thiết bị
scp test_face.mp4 root@<DEVICE_IP>:/var/jb/var/mobile/Library/VCamMedia/

# Copy ảnh test
scp test_photo.jpg root@<DEVICE_IP>:/var/jb/var/mobile/Library/VCamMedia/

# Set permissions
ssh root@<DEVICE_IP>
chmod 644 /var/jb/var/mobile/Library/VCamMedia/*
chown mobile:mobile /var/jb/var/mobile/Library/VCamMedia/*
```

Sau đó mở **Settings → VCam**:
- Media Type = Video (hoặc Image)
- Media Filename = `test_face.mp4` (hoặc `test_photo.jpg`)
- Bật app cần test trong Allowlist
- Mở app đó → camera sẽ hiện test media

---

## Gỡ cài đặt

```bash
# Qua dpkg
dpkg -r com.vcam.qatool
killall -9 SpringBoard

# Xoá sạch hoàn toàn (bao gồm media & config)
rm -rf /var/jb/var/mobile/Library/VCamMedia/
rm -f /var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist
```
