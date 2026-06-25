APP_NAME := MongoDBClient
BUILD_DIR := build
APP := $(BUILD_DIR)/$(APP_NAME).app

.PHONY: build run clean

build:
	mkdir -p "$(APP)/Contents/MacOS"
	cp Info.plist "$(APP)/Contents/Info.plist"
	swiftc -O -framework AppKit -framework Security Sources/MongoDBClient.swift -o "$(APP)/Contents/MacOS/$(APP_NAME)"

run: build
	open "$(APP)"

clean:
	rm -rf "$(BUILD_DIR)"
