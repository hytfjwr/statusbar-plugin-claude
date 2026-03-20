PLUGIN_NAME := ClaudeCodePlugin
PLUGIN_ID := com.hytfjwr.claudecode
VERSION ?= 0.1.0
STATUSBARKIT_VERSION := 1.0.0
SWIFT_VERSION := 6.2
BUNDLE_NAME := $(shell echo $(PLUGIN_NAME) | tr 'A-Z' 'a-z')

BUILD_DIR := .build/release
BUNDLE_DIR := $(BUILD_DIR)/$(BUNDLE_NAME).statusplugin
DYLIB := $(BUILD_DIR)/lib$(PLUGIN_NAME).dylib
ZIP_FILE := $(BUILD_DIR)/$(BUNDLE_NAME).statusplugin.zip
PLUGINS_DIR := $(HOME)/.config/statusbar/plugins

.PHONY: build bundle package dev clean

build:
	swift build -c release

bundle: build
	mkdir -p $(BUNDLE_DIR)
	cp $(DYLIB) $(BUNDLE_DIR)/plugin.dylib
	@echo '{\n  "id": "$(PLUGIN_ID)",\n  "name": "$(PLUGIN_NAME)",\n  "version": "$(VERSION)",\n  "statusBarKitVersion": "$(STATUSBARKIT_VERSION)",\n  "swiftVersion": "$(SWIFT_VERSION)",\n  "entrySymbol": "createStatusBarPlugin"\n}' > $(BUNDLE_DIR)/manifest.json
	@echo "Bundle created: $(BUNDLE_DIR)"

package: bundle
	cd $(BUILD_DIR) && zip -r $(BUNDLE_NAME).statusplugin.zip $(BUNDLE_NAME).statusplugin/
	@echo "Package created: $(ZIP_FILE)"

dev: bundle
	mkdir -p $(PLUGINS_DIR)
	rm -rf $(PLUGINS_DIR)/$(BUNDLE_NAME).statusplugin
	cp -r $(BUNDLE_DIR) $(PLUGINS_DIR)/
	@echo "Installed to $(PLUGINS_DIR)/$(BUNDLE_NAME).statusplugin"

clean:
	swift package clean
	rm -rf $(BUILD_DIR)/$(BUNDLE_NAME).statusplugin $(ZIP_FILE)
