ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: prepare-assets bootstrap build test format lint validate-tooling package verify-package runtime-smoke collect-runtime clean

VERSION ?= 0.0.0
RUNTIME_DURATION ?= 300
RUNTIME_INTERVAL ?= 2

prepare-assets:
	cd "$(ROOT_DIR)" && python3 scripts/materialize_app_icon.py

bootstrap: prepare-assets
	command -v xcodegen >/dev/null || brew install xcodegen
	cd "$(ROOT_DIR)" && xcodegen generate

build: bootstrap
	cd "$(ROOT_DIR)" && xcodebuild -project MacVitals.xcodeproj -scheme MacVitals -configuration Debug -destination 'platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

test: bootstrap
	cd "$(ROOT_DIR)" && xcodebuild -project MacVitals.xcodeproj -scheme MacVitals -destination 'platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test -only-testing:MacVitalsTests

format:
	cd "$(ROOT_DIR)" && swift format format --in-place --recursive MacVitals MacVitalsTests MacVitalsUITests

lint:
	cd "$(ROOT_DIR)" && swift format lint --recursive MacVitals MacVitalsTests MacVitalsUITests

validate-tooling:
	cd "$(ROOT_DIR)" && python3 -m py_compile scripts/materialize_app_icon.py scripts/validate_localizations.py scripts/validate_output_path.py scripts/validate_release_metadata.py scripts/validate_runtime_metrics.py
	cd "$(ROOT_DIR)" && python3 scripts/materialize_app_icon.py --self-test
	cd "$(ROOT_DIR)" && python3 scripts/materialize_app_icon.py --check-only
	cd "$(ROOT_DIR)" && python3 scripts/validate_localizations.py
	cd "$(ROOT_DIR)" && python3 scripts/validate_output_path.py --self-test
	cd "$(ROOT_DIR)" && python3 scripts/validate_release_metadata.py --self-test
	cd "$(ROOT_DIR)" && python3 scripts/validate_runtime_metrics.py --self-test
	cd "$(ROOT_DIR)" && bash -n scripts/package_release.sh scripts/verify_release.sh scripts/collect_runtime_metrics.sh scripts/run_ci_runtime_smoke.sh

package: validate-tooling
	cd "$(ROOT_DIR)" && bash scripts/package_release.sh "$(VERSION)"

verify-package: validate-tooling
	cd "$(ROOT_DIR)" && bash scripts/verify_release.sh "$(VERSION)"

runtime-smoke: package
	cd "$(ROOT_DIR)" && bash scripts/run_ci_runtime_smoke.sh build/MacVitals.xcarchive/Products/Applications/MacVitals.app

collect-runtime:
	cd "$(ROOT_DIR)" && bash scripts/collect_runtime_metrics.sh "$(RUNTIME_DURATION)" "$(RUNTIME_INTERVAL)"

clean:
	rm -rf -- "$(ROOT_DIR)/MacVitals.xcodeproj" "$(ROOT_DIR)/build" "$(ROOT_DIR)/dist" "$(ROOT_DIR)/runtime-smoke-results" "$(ROOT_DIR)/performance-results"
	rm -f -- "$(ROOT_DIR)/MacVitals/Resources/AppIcon.icns"
