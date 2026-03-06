# VCam — Virtual Camera QA Tool for iOS (Rootless)

> **Internal QA/Testing tool for simulating camera input on jailbroken iOS devices.**
> NOT for production use. For testing media pipelines, camera UI, and automation only.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Structure](#project-structure)
3. [Prerequisites](#prerequisites)
4. [Build Instructions](#build-instructions)
5. [Packaging (.deb)](#packaging-deb)
6. [Installation via Sileo](#installation-via-sileo)
7. [Configuration](#configuration)
8. [Usage Guide](#usage-guide)
9. [Bypass Detection](#bypass-detection)
10. [Debugging](#debugging)
11. [Build Checklist](#build-checklist)
12. [Install Checklist](#install-checklist)
13. [QA Test Checklist](#qa-test-checklist)
14. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Tweak.x                               │
│                   (Logos Hook Entry)                          │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ AVCapture    │  │ AVCapture    │  │ UIImagePicker     │  │
│  │ VideoData    │  │ Session      │  │ Controller        │  │
│  │ Output Hook  │  │ Hook         │  │ Hook              │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────────┘  │
│         │                  │                   │              │
│         ▼                  ▼                   ▼              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              VCamSessionHook                          │   │
│  │         (Frame replacement logic)                     │   │
│  └──────────────────┬──────────────────┬────────────────┘   │
│                     │                  │                     │
│         ┌───────────▼──────┐  ┌────────▼──────────┐        │
│         │  VCamMediaLoader │  │   VCamOverlay      │        │
│         │  (Image/Video)   │  │   (Watermark)      │        │
│         └───────────┬──────┘  └───────────────────┘        │
│                     │                                       │
│         ┌───────────▼──────┐  ┌───────────────────┐        │
│         │   VCamConfig     │  │   VCamBypass       │        │
│         │  (Preferences)   │  │   (Detection       │        │
│         │                  │  │    evasion)         │        │
│         └──────────────────┘  └───────────────────┘        │
│                     │                                       │
│         ┌───────────▼──────┐                                │
│         │   VCamLogger     │                                │
│         │  (Debug/QA log)  │                                │
│         └──────────────────┘                                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Preferences Bundle                          │
│          (Settings.app UI for configuration)                 │
│  ┌────────────────────┐  ┌─────────────────────┐           │
│  │ VCamRootList       │  │ VCamAppList          │           │
│  │ Controller         │  │ Controller           │           │
│  └────────────────────┘  └─────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

### Module Responsibilities

| Module | File | Purpose |
|--------|------|---------|
| **Config** | `VCamConfig.m` | Preferences read/write, allowlist management |
| **MediaLoader** | `VCamMediaLoader.m` | Load image/video, produce CVPixelBuffer/CMSampleBuffer |
| **SessionHook** | `VCamSessionHook.m` | Camera position logic, frame replacement decision |
| **Overlay** | `VCamOverlay.m` | "TEST FEED" watermark rendering via CoreGraphics |
| **Bypass** | `VCamBypass.m` | KYC/liveness/anti-fraud detection evasion |
| **Logger** | `VCamLogger.m` | Centralized os_log + file logging |
| **Tweak.x** | `Tweak.x` | Logos hooks into AVFoundation classes |
| **Prefs** | `Preferences/` | Settings.app UI bundle |

---

## Project Structure

```
vcam/
├── Makefile                          # Root Makefile (rootless scheme)
├── control                           # Debian package metadata
├── VCam.plist                        # Substrate filter (UIKit bundle)
├── Tweak.x                           # Main hook file (Logos)
├── Sources/
│   ├── VCamConfig.h / .m            # Configuration manager
│   ├── VCamMediaLoader.h / .m       # Media loading & frame production
│   ├── VCamSessionHook.h / .m       # Camera session hook logic
│   ├── VCamOverlay.h / .m           # Watermark overlay renderer
│   ├── VCamBypass.h / .m            # Detection bypass hooks
│   └── VCamLogger.h / .m            # Logging system
├── Preferences/
│   ├── Makefile                      # Prefs bundle Makefile
│   ├── entry.plist                   # Prefs entry point
│   ├── VCamRootListController.h/.m   # Main settings screen
│   ├── VCamAppListController.h/.m    # App allowlist selector
│   └── Resources/
│       └── Root.plist                # Settings specifiers
├── layout/
│   └── var/mobile/Library/VCamMedia/ # Default media directory
└── README.md                         # This file
```

---

## Prerequisites

### Required tools

| Tool | Version | Purpose |
|------|---------|---------|
| **Theos** | Latest | Build system |
| **Xcode** | 14.0+ | Compiler toolchain |
| **iOS SDK** | 15.0+ | Headers & frameworks |
| **dpkg** | Any | .deb packaging |
| **ldid** | Latest | Code signing |

### Device requirements

| Requirement | Details |
|-------------|---------|
| iOS version | 15.0 — 17.x |
| Jailbreak | Rootless (Dopamine, Fugu15, palera1n rootless) |
| Substrate | ElleKit / libhooker / Substitute |
| Package manager | Sileo (recommended), Zebra |

### Install Theos

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

Set environment:
```bash
export THEOS=~/theos
export PATH=$THEOS/bin:$PATH
```

---

## Build Instructions

### 1. Clone/copy project

```bash
cd ~/Projects
# Copy the vcam folder here
```

### 2. Build the tweak

```bash
cd vcam
make clean
make package FINALPACKAGE=1
```

### 3. Build output

The `.deb` file will be in `packages/`:
```
packages/com.vcam.qatool_1.0.0_iphoneos-arm64.deb
```

### Build flags

| Flag | Purpose |
|------|---------|
| `FINALPACKAGE=1` | Production build (strip debug, optimize) |
| `DEBUG=1` | Debug build (symbols, no optimization) |
| `THEOS_PACKAGE_SCHEME=rootless` | Already set in Makefile |

---

## Packaging (.deb)

The `make package` command automatically creates the `.deb`. Manual packaging:

```bash
# After 'make'
cd $THEOS_OBJ_DIR
dpkg-deb -b com.vcam.qatool/ ../packages/com.vcam.qatool_1.0.0_iphoneos-arm64.deb
```

### Package info

| Field | Value |
|-------|-------|
| Package ID | `com.vcam.qatool` |
| Name | VCam - Virtual Camera QA Tool |
| Version | 1.0.0 |
| Architecture | iphoneos-arm64 |
| Section | Tweaks |
| Dependencies | mobilesubstrate, firmware (>= 15.0), preferenceloader |

---

## Installation via Sileo

### Method 1: Direct transfer

```bash
# From build machine, copy .deb to device
scp packages/com.vcam.qatool_1.0.0_iphoneos-arm64.deb root@<DEVICE_IP>:/var/jb/var/mobile/Documents/
```

On device:
1. Open **Filza** or **Santander**
2. Navigate to `/var/jb/var/mobile/Documents/`
3. Tap the `.deb` file
4. Select "Install"
5. Respring

### Method 2: Via Sileo

1. Transfer `.deb` to device
2. Open Sileo
3. Go to **Sources** → **Get** → select the `.deb` file
4. Or use **dpkg** directly:
   ```bash
   ssh root@<DEVICE_IP>
   dpkg -i /var/jb/var/mobile/Documents/com.vcam.qatool_1.0.0_iphoneos-arm64.deb
   ```
5. Run `uicache -a` if the prefs don't appear
6. Respring: `killall -9 SpringBoard`

### Method 3: Local repo

```bash
# On device
dpkg -i /path/to/com.vcam.qatool_1.0.0_iphoneos-arm64.deb
uicache -a
killall -9 SpringBoard
```

---

## Configuration

### Settings location

All preferences are stored at:
```
/var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist
```

### Settings UI

Open **Settings** → **VCam** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Enable VCam | ON | Master kill switch |
| Global Enable | ON | Secondary global toggle |
| App Allowlist | (empty = all) | Which apps get simulated feed |
| Media Type | None | Image / Video / None |
| Media Filename | (empty) | File in VCamMedia directory |
| Loop Video | ON | Repeat video playback |
| Camera Position | Both | Front / Back / Both |
| Show Watermark | ON | "TEST FEED" overlay |
| Bypass Detection | OFF | KYC/liveness evasion |
| Debug Logging | ON | Verbose logging |
| Reset Settings | (button) | Restore defaults |

### Media files

Place test media in:
```
/var/jb/var/mobile/Library/VCamMedia/
```

Example:
```bash
# Copy test video to device
scp test_face.mp4 root@<DEVICE_IP>:/var/jb/var/mobile/Library/VCamMedia/

# Copy test image
scp test_photo.jpg root@<DEVICE_IP>:/var/jb/var/mobile/Library/VCamMedia/
```

Then in Settings → VCam:
- Set **Media Type** to "Video" or "Image"
- Set **Media Filename** to `test_face.mp4` or `test_photo.jpg`

---

## Usage Guide

### Basic workflow

1. Install the tweak
2. Copy test media to `/var/jb/var/mobile/Library/VCamMedia/`
3. Open Settings → VCam
4. Enable the tweak
5. Select media type and filename
6. Configure target apps (or leave empty for all)
7. Open target app's camera
8. The camera feed will show your test media instead

### Camera position simulation

- **Front**: Only replaces front camera feed
- **Back**: Only replaces back camera feed
- **Both**: Replaces both camera feeds

### Watermark

When enabled, a red semi-transparent banner appears at the top of the feed showing:
- "TEST FEED — SIMULATED CAMERA"
- Current timestamp

---

## Bypass Detection

The bypass module hooks into common detection mechanisms:

### What it bypasses

| Detection Method | Hook Strategy |
|-----------------|---------------|
| **Jailbreak file checks** | Hides rootless paths from NSFileManager |
| **Dylib enumeration** | Filters injection-related libraries |
| **Environment variables** | Removes DYLD_INSERT_LIBRARIES etc. |
| **Device property inspection** | Ensures consistent device metadata |
| **Process inspection** | Hides substrate-related env vars |

### How to use

1. Settings → VCam → **Bypass Detection** → ON
2. Reopen the target app (kill it first)
3. The app's KYC/liveness SDK should not detect the virtual camera

### Limitations

- Cannot bypass server-side liveness checks that analyze video quality
- Cannot bypass 3D depth-based liveness (TrueDepth hardware)
- Some SDKs may use obfuscated detection that isn't covered

---

## Debugging

### Log file

```
/var/jb/var/mobile/Library/VCamMedia/vcam.log
```

### View logs in real-time

```bash
ssh root@<DEVICE_IP>
tail -f /var/jb/var/mobile/Library/VCamMedia/vcam.log
```

### System log

```bash
# On macOS with device connected
idevicesyslog | grep VCam
```

### Log format

```
[2025-01-15 10:30:45.123] [VCam][ModuleName] Message here
[2025-01-15 10:30:45.456] [VCam][ERROR][ModuleName] Error message
[2025-01-15 10:30:45.789] [VCam][DEBUG][ModuleName] Debug message
```

### Key log messages

| Log | Meaning |
|-----|---------|
| `VCam loading in process: com.xxx` | Tweak injected into app |
| `App xxx not in allowlist, skipping` | App filtered out |
| `Media pre-load success` | Test media loaded OK |
| `Session hooks activated` | Camera hooks ready |
| `Frames replaced: N` | Feed replacement working |
| `Frame replacement exception` | Error during replacement |

---

## Build Checklist

- [ ] Theos installed and `$THEOS` set
- [ ] iOS SDK available (check `$THEOS/sdks/`)
- [ ] `make clean` runs without error
- [ ] `make` compiles without warnings/errors
- [ ] `make package` produces `.deb` in `packages/`
- [ ] `.deb` file size is reasonable (< 1MB)
- [ ] Package name matches `com.vcam.qatool`
- [ ] Architecture is `iphoneos-arm64`

## Install Checklist

- [ ] Device is jailbroken (rootless)
- [ ] Substrate/Substitute is installed
- [ ] PreferenceLoader is installed
- [ ] `.deb` transferred to device
- [ ] `dpkg -i` completes without errors
- [ ] `uicache -a` run after install
- [ ] SpringBoard resprung
- [ ] VCam appears in Settings app
- [ ] All Settings toggles work
- [ ] Prefs file created at expected path

## QA Test Checklist

### Pre-test
- [ ] Test media files copied to `/var/jb/var/mobile/Library/VCamMedia/`
- [ ] Image file (JPG/PNG) available
- [ ] Video file (MP4/MOV) available
- [ ] VCam enabled in Settings
- [ ] Media type and filename configured
- [ ] Debug logging enabled

### Functional tests
- [ ] **Image feed**: Camera shows static test image
- [ ] **Video feed**: Camera shows test video
- [ ] **Video loop**: Video restarts after ending
- [ ] **Front camera**: Feed replaced when using front cam
- [ ] **Back camera**: Feed replaced when using back cam
- [ ] **Watermark ON**: Red banner visible with "TEST FEED"
- [ ] **Watermark OFF**: No banner, clean feed
- [ ] **Allowlist**: Only selected apps get simulated feed
- [ ] **Non-listed app**: Camera works normally
- [ ] **Toggle OFF**: Camera reverts to real feed
- [ ] **Kill switch**: Disabling master toggle stops all hooks

### Error handling tests
- [ ] **Missing media file**: Falls back to real camera
- [ ] **Corrupt media file**: Falls back to real camera, no crash
- [ ] **Wrong file extension**: Error logged, fallback works
- [ ] **App crash test**: Target app does NOT crash
- [ ] **Rapid toggle**: Quickly toggle on/off — no crash
- [ ] **Multiple sessions**: Multiple apps using camera simultaneously

### Bypass tests (if enabled)
- [ ] **Jailbreak detection**: App's JB check bypassed
- [ ] **Camera detection**: Virtual camera not flagged
- [ ] **KYC flow**: Liveness check receives simulated feed
- [ ] **No false positives**: Non-target apps unaffected

### Performance tests
- [ ] **Frame rate**: Feed maintains smooth framerate (≥24fps)
- [ ] **Memory**: No excessive memory growth over time
- [ ] **Battery**: No abnormal battery drain
- [ ] **Log rotation**: Log file doesn't exceed 2MB

---

## Troubleshooting

### Common issues and fixes

#### 1. Tweak not loading

**Symptoms**: Camera shows real feed, no VCam entries in log

**Fixes**:
```bash
# Check if tweak dylib exists
ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/VCam*

# Check filter plist
cat /var/jb/Library/MobileSubstrate/DynamicLibraries/VCam.plist

# Verify substrate is running
launchctl list | grep substrate

# Force respring
killall -9 SpringBoard
```

#### 2. Settings not appearing

**Symptoms**: No "VCam" entry in Settings app

**Fixes**:
```bash
# Check prefs bundle exists
ls -la /var/jb/Library/PreferenceBundles/VCamPrefs.bundle/

# Refresh icon cache
uicache -a

# Check PreferenceLoader
dpkg -l | grep preferenceloader
```

#### 3. Media file not loading

**Symptoms**: Log shows "File not found" or "Failed to decode"

**Fixes**:
```bash
# Verify file exists
ls -la /var/jb/var/mobile/Library/VCamMedia/

# Check file permissions
chmod 644 /var/jb/var/mobile/Library/VCamMedia/test_video.mp4

# Check file format (must be valid)
file /var/jb/var/mobile/Library/VCamMedia/test_video.mp4

# Try a known-good test file
```

#### 4. App crashes when opening camera

**Symptoms**: App force closes when camera starts

**Fixes**:
- Disable VCam for that specific app (remove from allowlist)
- Check if the app uses a custom camera framework not covered by hooks
- Check log for crash details:
  ```bash
  cat /var/jb/var/mobile/Library/VCamMedia/vcam.log | tail -50
  ```
- If crash persists, the app may be incompatible — add to internal blacklist

#### 5. Video stuttering

**Symptoms**: Feed is choppy or freezing

**Fixes**:
- Use a lower resolution video (720p recommended)
- Use H.264 codec (not HEVC)
- Check CPU usage — close other apps
- Reduce video framerate to 24-30fps

#### 6. Bypass not working

**Symptoms**: KYC app still detects virtual camera

**Fixes**:
- Ensure **Bypass Detection** is ON in Settings
- Kill and relaunch the target app
- Some SDKs use obfuscated detection — check their specific methods
- Server-side checks cannot be bypassed client-side
- 3D depth / TrueDepth liveness cannot be spoofed with 2D video

#### 7. Prefs not saving

**Symptoms**: Settings revert after closing Settings app

**Fixes**:
```bash
# Check file permissions
ls -la /var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist

# Fix permissions
chown mobile:mobile /var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist
chmod 644 /var/jb/var/mobile/Library/Preferences/com.vcam.qatool.plist

# Create directory if missing
mkdir -p /var/jb/var/mobile/Library/Preferences/
```

#### 8. Build errors

| Error | Fix |
|-------|-----|
| `theos/makefiles/common.mk: No such file` | Set `$THEOS` environment variable |
| `SDK not found` | Install iOS SDK in `$THEOS/sdks/` |
| `Undefined symbols` | Check framework list in Makefile |
| `Logos preprocessing failed` | Check Logos syntax in Tweak.x |
| `ldid error` | Install/update ldid: `brew install ldid` |

---

## Dependencies

| Package | Required | Purpose |
|---------|----------|---------|
| `mobilesubstrate` | Yes | Hook injection |
| `preferenceloader` | Yes | Settings UI |
| `firmware (>= 15.0)` | Yes | iOS 15+ APIs |

## License

Internal use only. Not for distribution.

---

*VCam v1.0.0 — Virtual Camera QA Tool*
