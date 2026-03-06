# VCam — Virtual Camera QA Tool
# Theos Makefile — rootless compatible
#
# Build:   make package FINALPACKAGE=1
# Clean:   make clean
# Install: make do THEOS_DEVICE_IP=<ip> THEOS_DEVICE_PORT=22

TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

# Rootless (Dopamine/palera1n/Fugu15)
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCam

VCam_FILES = Tweak.x \
             Sources/VCamConfig.m \
             Sources/VCamMediaLoader.m \
             Sources/VCamSessionHook.m \
             Sources/VCamOverlay.m \
             Sources/VCamLogger.m \
             Sources/VCamBypass.m

VCam_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
VCam_LDFLAGS = -lnotify
VCam_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreImage CoreGraphics Foundation ImageIO QuartzCore CoreText

SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
