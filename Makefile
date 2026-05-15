.PHONY: project build clean open install

PROJECT := RightMenuMaster.xcodeproj
SCHEME := RightMenuMaster

project:
	xcodegen generate
	open $(PROJECT)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build 2>&1

debug:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build 2>&1

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/RightMenuMaster-*

open:
	open $(PROJECT)

install: build
	echo "Build complete. Copy the app to /Applications to install."
	cp -R build/Release/RightMenuMaster.app /Applications/ 2>/dev/null || echo "Run manually: cp -R build/Release/RightMenuMaster.app /Applications/"
