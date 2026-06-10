APP_NAME := ZoomIt
BUILD_DIR := .build/release
APP_BUNDLE := dist/$(APP_NAME).app

.PHONY: all build test app run clean

all: app

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf dist
