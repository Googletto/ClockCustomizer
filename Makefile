ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:17.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ClockCustomizer

ClockCustomizer_FILES = Tweak.xm
ClockCustomizer_CFLAGS = -fobjc-arc
ClockCustomizer_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreText

include $(THEOS_MAKE_PATH)/tweak.mk

# Preferences bundle (shown inside Settings.app)
SUBPROJECTS += ClockCustomizerPrefs.bundle
include $(THEOS_MAKE_PATH)/aggregate.mk
