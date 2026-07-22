.PHONY: bootstrap build test format lint clean
bootstrap:
	command -v xcodegen >/dev/null || brew install xcodegen
	xcodegen generate
build: bootstrap
	xcodebuild -project MacVitals.xcodeproj -scheme MacVitals -configuration Debug -destination 'platform=macOS' build
test: bootstrap
	xcodebuild -project MacVitals.xcodeproj -scheme MacVitals -destination 'platform=macOS' test -only-testing:MacVitalsTests
format:
	swiftformat MacVitals MacVitalsTests MacVitalsUITests
lint:
	swiftformat --lint MacVitals MacVitalsTests MacVitalsUITests
clean:
	rm -rf MacVitals.xcodeproj build dist
