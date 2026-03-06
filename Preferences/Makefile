# VCamPrefs — Preferences Bundle
# Installs to rootless PreferenceBundles path

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = VCamPrefs

VCamPrefs_FILES = VCamRootListController.m VCamAppListController.m
VCamPrefs_INSTALL_PATH = /var/jb/Library/PreferenceBundles
VCamPrefs_FRAMEWORKS = UIKit
VCamPrefs_PRIVATE_FRAMEWORKS = Preferences
VCamPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VCamPrefs_LDFLAGS = -lnotify

include $(THEOS_MAKE_PATH)/bundle.mk
