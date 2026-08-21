ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:17.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ClockCustomizerPrefs

ClockCustomizerPrefs_FILES = ClockCustomizerPrefsListController.m
ClockCustomizerPrefs_CFLAGS = -fobjc-arc
ClockCustomizerPrefs_INSTALL_PATH = /Library/PreferenceBundles
ClockCustomizerPrefs_FRAMEWORKS = UIKit CoreGraphics CoreText

include $(THEOS_MAKE_PATH)/bundle.mk
