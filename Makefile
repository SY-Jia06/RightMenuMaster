.PHONY: project build test clean open install install-debug release

PROJECT := RightMenuMaster.xcodeproj
SCHEME := RightMenuMaster

project:
	xcodegen generate
	open $(PROJECT)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

debug:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean

open:
	open $(PROJECT)

install: install-debug

install-debug:
	scripts/install-debug.sh

release:
	scripts/release-macos.sh
