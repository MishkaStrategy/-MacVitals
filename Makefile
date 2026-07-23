.PHONY: prepare-assets bootstrap build test format lint validate-tooling package verify-package runtime-smoke collect-runtime clean

VERSION ?= 0.0.0
RUNTIME_DURATION ?= 300
RUNTIME_INTERVAL ?= 2

prepare-assets:
	python3 scripts/materialize_app_icon.py

bootstrap: prepare-assets
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

validate-tooling:
	python3 -m py_compile scripts/materialize_app_icon.py scripts/validate_localizations.py scripts/validate_release_metadata.py scripts/validate_runtime_metrics.py
	python3 scripts/materialize_app_icon.py --self-test
	python3 scripts/materialize_app_icon.py --check-only
	python3 scripts/validate_localizations.py
	python3 scripts/validate_release_metadata.py --self-test
	python3 scripts/validate_runtime_metrics.py --self-test
	bash -n scripts/package_release.sh scripts/verify_release.sh scripts/collect_runtime_metrics.sh scripts/run_ci_runtime_smoke.sh

package: validate-tooling
	bash scripts/package_release.sh "$(VERSION)"

verify-package: validate-tooling
	bash scripts/verify_release.sh "$(VERSION)"

runtime-smoke: package
	bash scripts/run_ci_runtime_smoke.sh build/MacVitals.xcarchive/Products/Applications/MacVitals.app

collect-runtime:
	bash scripts/collect_runtime_metrics.sh "$(RUNTIME_DURATION)" "$(RUNTIME_INTERVAL)"

clean:
	rm -rf MacVitals.xcodeproj build build-intel build-intel-tests dist runtime-smoke-results runtime-intel-results performance-results
	rm -f MacVitals/Resources/AppIcon.icns
