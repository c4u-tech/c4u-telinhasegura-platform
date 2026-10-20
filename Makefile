# The full gate is `make check`: CI runs exactly this, and it is the done bar.
# Modules are discovered, not listed: every go.mod is a Go module and every
# pubspec.yaml a Dart/Flutter package, wherever the layout puts them. Files
# git ignores (build output, tool caches) are not searched.
GO_MODULES := $(sort $(dir $(shell git ls-files -co --exclude-standard -- go.mod '*/go.mod')))
DART_PACKAGES := $(sort $(dir $(shell git ls-files -co --exclude-standard -- pubspec.yaml '*/pubspec.yaml')))

.PHONY: check fast go-fmt go-vet go-test go-build dart-fmt dart-analyze dart-test

check: go-fmt go-vet go-test go-build dart-fmt dart-analyze dart-test

# The fast subset to run while working: format and static analysis, no tests.
fast: go-fmt go-vet dart-fmt dart-analyze

go-fmt:
	@for m in $(GO_MODULES); do \
	  out="$$(cd $$m && gofmt -l .)" || exit 1; \
	  [ -z "$$out" ] || { echo "gofmt: needs formatting in $$m (run: gofmt -w .)"; echo "$$out"; exit 1; }; \
	done

go-vet:
	@for m in $(GO_MODULES); do (cd $$m && go vet ./...) || exit 1; done

go-test:
	@for m in $(GO_MODULES); do (cd $$m && go test ./...) || exit 1; done

go-build:
	@for m in $(GO_MODULES); do (cd $$m && go build ./...) || exit 1; done

dart-fmt:
	@for p in $(DART_PACKAGES); do (cd $$p && dart format --output=none --set-exit-if-changed .) || exit 1; done

dart-analyze:
	@for p in $(DART_PACKAGES); do (cd $$p && flutter analyze) || exit 1; done

# Tests marked @TestOn('browser') also run in Chrome: the VM run skips them.
dart-test:
	@for p in $(DART_PACKAGES); do (cd $$p || exit 1; flutter test || exit 1; \
		b=$$(grep -rl "@TestOn('browser')" test 2>/dev/null); \
		if [ -n "$$b" ]; then flutter test --platform chrome $$b || exit 1; fi) \
		|| exit 1; done

# Mobile development (docs/development/mobile.md). None of these is a gate.
AVD ?= Medium_Phone_API_37.0
ANDROID_DEVICE ?= emulator
IOS_DEVICE ?=
LOCAL_DEFINES := --dart-define-from-file=config/local.json

.PHONY: doctor emulators api run-android run-ios build-android build-ios

doctor:
	@sh scripts/doctor.sh

emulators:
	@cd app && flutter emulators; xcrun simctl list devices available

api:
	@sh scripts/api.sh

run-android:
	@sh scripts/require-local-config.sh
	@sh scripts/boot-android.sh $(AVD)
	@cd app && flutter run -d $(ANDROID_DEVICE) $(LOCAL_DEFINES) --dart-define=API_BASE_URL=http://10.0.2.2:8080

# IOS_DEVICE empty: the simulator boot-ios.sh booted (its UDID).
run-ios:
	@sh scripts/require-local-config.sh
	@udid="$$(sh scripts/boot-ios.sh)" && cd app && \
	  flutter run -d "$(or $(IOS_DEVICE),$$udid)" $(LOCAL_DEFINES) --dart-define=API_BASE_URL=http://localhost:8080

# Release builds of one environment: ENV=stg|prd.
ENV ?= prd

build-android:
	@case "$(ENV)" in stg|prd) ;; *) echo "ENV must be stg or prd (got '$(ENV)')" >&2; exit 2 ;; esac
	@cd app && dart run tool/check_app_env.dart config/$(ENV).json
	@cd app && flutter build apk --release --dart-define-from-file=config/$(ENV).json && \
	  flutter build appbundle --release --dart-define-from-file=config/$(ENV).json

build-ios:
	@case "$(ENV)" in stg|prd) ;; *) echo "ENV must be stg or prd (got '$(ENV)')" >&2; exit 2 ;; esac
	@cd app && dart run tool/check_app_env.dart config/$(ENV).json
	@cd app && flutter build ios --release --no-codesign --dart-define-from-file=config/$(ENV).json
