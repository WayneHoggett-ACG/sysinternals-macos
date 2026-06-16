APP_NAME := ZoomIt

# Version is derived from git so tags are the single source of truth.
# Marketing version = latest tag (without the leading "v"); falls back to
# 0.0.0 on an untagged checkout. Build number = commit count (monotonic).
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
ifeq ($(VERSION),)
VERSION := 0.0.0
endif
BUILD := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)

# Set ARCHS to build a universal binary, e.g. `make app ARCHS="arm64 x86_64"`.
# Releases use this; local `make app` builds host-arch only for speed.
ARCHS ?=
ifeq ($(strip $(ARCHS)),)
SWIFT_BUILD_FLAGS :=
BUILD_DIR := .build/release
else
SWIFT_BUILD_FLAGS := $(foreach a,$(ARCHS),--arch $(a))
BUILD_DIR := .build/apple/Products/Release
endif

APP_BUNDLE := dist/$(APP_NAME).app
ZIP := dist/$(APP_NAME)-$(VERSION).zip

.PHONY: all build test app run zip clean version

all: app

version:
	@echo "$(VERSION) (build $(BUILD))"

build:
	swift build -c release $(SWIFT_BUILD_FLAGS)

test:
	swift test

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD)" $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (version $(VERSION), build $(BUILD))"

# Package the bundle for distribution. ditto preserves the .app structure and
# resource forks correctly (plain zip can corrupt bundles).
zip: app
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP)
	@echo "Packaged $(ZIP)"

run: app
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf dist
