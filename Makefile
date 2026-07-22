.PHONY: bootstrap build test format lint package verify-package clean

VERSION ?= dev

bootstrap:
	command -v xcodegen >/dev/null || brew install xcodegen
	xcodegen generate

build: bootstrap
	xcodebuild -project MacVitals.xcodeproj -scheme MacVitals -configuration Debug -destination 'platform=macOS' build

test: bootstrap
	xcodebuild -project MacVitals.xcodeproj -scheme MacVitals -destination 'platform=macOS' test -only-testing:MacVitalsTests

format:
	swift format format --in-place --recursive MacVitals MacVitalsTests MacVitalsUITests

lint:
	swift format lint --recursive MacVitals MacVitalsTests MacVitalsUITests

package:
	bash scripts/package_release.sh "$(VERSION)"

verify-package:
	bash scripts/verify_release.sh "$(VERSION)"

clean:
	rm -rf MacVitals.xcodeproj build dist
