# Extracted from Package.swift (single source of truth)
PLUGIN_NAME := $(shell sed -n 's/.*name: *"\([^"]*\)".*/\1/p' Package.swift | head -1)
STATUSBARKIT_VERSION := $(shell sed -n 's/.*from: *"\([^"]*\)".*/\1/p' Package.swift)
SWIFT_VERSION := $(shell head -1 Package.swift | sed 's/.*swift-tools-version: *//')

# Extracted from source code (single source of truth)
PLUGIN_SOURCE := Sources/$(PLUGIN_NAME)/$(PLUGIN_NAME).swift
PLUGIN_ID := $(shell sed -n 's/.*id: *"\([^"]*\)".*/\1/p' $(PLUGIN_SOURCE))
ENTRY_SYMBOL := $(shell sed -n 's/.*@_cdecl("\([^"]*\)").*/\1/p' $(PLUGIN_SOURCE))

VERSION ?= 0.1.0
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
	@echo '{\n  "id": "$(PLUGIN_ID)",\n  "name": "$(PLUGIN_NAME)",\n  "version": "$(VERSION)",\n  "statusBarKitVersion": "$(STATUSBARKIT_VERSION)",\n  "swiftVersion": "$(SWIFT_VERSION)",\n  "entrySymbol": "$(ENTRY_SYMBOL)"\n}' > $(BUNDLE_DIR)/manifest.json
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
