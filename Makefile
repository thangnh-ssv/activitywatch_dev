# =============================================
# Makefile for the InsightLoggerSystem bundle
# =============================================
#
# [GUIDE] How to install from source:
#  - https://activitywatch.readthedocs.io/en/latest/installing-from-source.html
#
# We recommend creating and activating a Python virtualenv before building.
# Instructions on how to do this can be found in the guide linked above.
.PHONY: build install test clean clean_all

SHELL := /usr/bin/env bash

OS := $(shell uname -s)

SUBMODULES := aw-core aw-client aw-qt aw-server aw-watcher-window

# Include extras if AW_EXTRAS is true
ifeq ($(AW_EXTRAS),true)
	SUBMODULES := $(SUBMODULES)
endif

# A function that checks if a target exists in a Makefile
# Usage: $(call has_target,<dir>,<target>)
define has_target
$(shell make -q -C $1 $2 >/dev/null 2>&1; if [ $$? -eq 0 -o $$? -eq 1 ]; then echo $1; fi)
endef

# Submodules with test/lint/typecheck targets (auto-detected)
TESTABLES := $(foreach dir,$(SUBMODULES),$(call has_target,$(dir),test))
LINTABLES := $(foreach dir,$(SUBMODULES),$(call has_target,$(dir),lint))
TYPECHECKABLES := $(foreach dir,$(SUBMODULES),$(call has_target,$(dir),typecheck))

# Packageable apps for distribution.
# We keep this explicit because `make -q` probes can return non-0 for complex targets
# (e.g. aw-server `package` depends on bump-version / git describe), which would
# incorrectly exclude it from the bundle.
PACKAGEABLES := aw-qt aw-server aw-watcher-window

# Build mode: release vs debug
ifeq ($(RELEASE), false)
	targetdir := debug
else
	targetdir := release
endif

# The `build` target
# ------------------
#
# What it does:
#  - Installs all the Python modules
#  - Builds the web UI and bundles it with aw-server
build:
#	needed due to https://github.com/pypa/setuptools/issues/1963
#	would ordinarily be specified in pyproject.toml, but is not respected due to https://github.com/pypa/setuptools/issues/1963
	python -m pip install 'setuptools>49.1.1'
	for module in $(SUBMODULES); do \
		echo "Building $$module"; \
		make --directory=$$module build SKIP_WEBUI=$(SKIP_WEBUI) || { echo "Error in $$module build"; exit 2; }; \
	done
#   The below is needed due to: https://github.com/ActivityWatch/activitywatch/issues/173
	make --directory=aw-client build
	make --directory=aw-core build
#	Needed to ensure that the server has the correct version set
	(cd aw-server && poetry run python -c "import aw_server; print(aw_server.__version__)")


# Install
# -------
#
# Installs things like desktop/menu shortcuts.
# Might in the future configure autostart on the system.
install:
	make --directory=aw-qt install
# Installation is already happening in the `make build` step currently.
# We might want to change this.
# We should also add some option to install as user (pip3 install --user)
# Update
# ------
#
# Pulls the latest version, updates all the submodules, then runs `make build`.
update:
	git pull
	git submodule update --init --recursive
	make build


lint:
	@for module in $(LINTABLES); do \
		echo "Linting $$module"; \
		make --directory=$$module lint || { echo "Error in $$module lint"; exit 2; }; \
	done

typecheck:
	@for module in $(TYPECHECKABLES); do \
		echo "Typechecking $$module"; \
		make --directory=$$module typecheck || { echo "Error in $$module typecheck"; exit 2; }; \
	done

# Uninstall
# ---------
#
# Uninstalls all the Python modules.
uninstall:
	modules=$$(pip3 list --format=legacy | grep 'aw-' | grep -o '^aw-[^ ]*'); \
	for module in $$modules; do \
		echo "Uninstalling $$module"; \
		pip3 uninstall -y $$module; \
	done

test:
	@for module in $(TESTABLES); do \
		echo "Running tests for $$module"; \
		if [ -f "$$module/pyproject.toml" ]; then \
			(cd $$module && poetry run make test) || { echo "Error in $$module tests"; exit 2; }; \
		else \
			make -C $$module test || { echo "Error in $$module tests"; exit 2; }; \
		fi; \
	done

test-integration:
	# TODO: Move "integration tests" to aw-client
	# FIXME: For whatever reason the script stalls on Appveyor
	#        Example: https://ci.appveyor.com/project/ErikBjare/activitywatch/build/1.0.167/job/k1ulexsc5ar5uv4v
	# aw-server-python
	@echo "== Integration testing aw-server =="
	@pytest ./scripts/tests/integration_tests.py ./aw-server/tests/ -v

%/.git:
	@echo "Submodules disabled (self-contained mono-repo)."

ICON := "aw-qt/media/logo/logo.png"

aw-qt/media/logo/logo.icns:
	mkdir -p build/MyIcon.iconset
	sips -z 16 16     $(ICON) --out build/MyIcon.iconset/icon_16x16.png
	sips -z 32 32     $(ICON) --out build/MyIcon.iconset/icon_16x16@2x.png
	sips -z 32 32     $(ICON) --out build/MyIcon.iconset/icon_32x32.png
	sips -z 64 64     $(ICON) --out build/MyIcon.iconset/icon_32x32@2x.png
	sips -z 128 128   $(ICON) --out build/MyIcon.iconset/icon_128x128.png
	sips -z 256 256   $(ICON) --out build/MyIcon.iconset/icon_128x128@2x.png
	sips -z 256 256   $(ICON) --out build/MyIcon.iconset/icon_256x256.png
	sips -z 512 512   $(ICON) --out build/MyIcon.iconset/icon_256x256@2x.png
	sips -z 512 512   $(ICON) --out build/MyIcon.iconset/icon_512x512.png
	cp				  $(ICON)       build/MyIcon.iconset/icon_512x512@2x.png
	iconutil -c icns build/MyIcon.iconset
	rm -R build/MyIcon.iconset
	mv build/MyIcon.icns aw-qt/media/logo/logo.icns

dist/InsightLoggerSystem.app: aw-qt/media/logo/logo.icns
	# Build the macOS app bundle using the aw-qt Poetry env (has PyInstaller).
	# We also install flask-restx into that env so aw.spec can import it.
	(cd aw-qt && poetry install --with pyqt)
	# Ensure local aw-client is importable for aw-server proxy/token store.
	(cd aw-qt && poetry run python -m pip install -q -e ../aw-client)
	# Ensure aw-server deps used by aw.spec exist in this env too
	(cd aw-qt && poetry run python -m pip install -q -U \
		"flask<3" "werkzeug<3" \
		flask-restx flask-cors requests charset_normalizer persist-queue)
	(cd aw-qt && poetry run pyinstaller --clean --noconfirm --distpath ../dist --workpath ../build ../aw.spec)
	mkdir -p dist/InsightLoggerSystem.app/Contents/Resources
	cp scripts/package/macos/net.ils.ILS.plist dist/InsightLoggerSystem.app/Contents/Resources/

dist/InsightLoggerSystem.dmg: dist/InsightLoggerSystem.app
	# NOTE: This does not codesign the dmg, that is done in the CI config
	python3 -m pip install dmgbuild
	dmgbuild -s scripts/package/dmgbuild-settings.py -D app=dist/InsightLoggerSystem.app "InsightLoggerSystem" dist/InsightLoggerSystem.dmg

dist/notarize:
	./scripts/notarize.sh

package:
	rm -rf dist
	mkdir -p dist/activitywatch
	for dir in $(PACKAGEABLES); do \
		echo "==> Packaging $$dir"; \
		make --directory=$$dir package || { echo "ERROR: Failed to package $$dir"; exit 1; }; \
		if [ -d "$$dir/dist/$$dir" ]; then \
			echo "    Copying $$dir/dist/$$dir to dist/activitywatch"; \
			cp -r "$$dir/dist/$$dir" dist/activitywatch/ || { echo "ERROR: Failed to copy $$dir"; exit 1; }; \
		else \
			echo "ERROR: Expected $$dir/dist/$$dir not found"; \
			exit 1; \
		fi; \
	done
# Move aw-qt files to the root of the dist folder (use cp+rm instead of mv to avoid permission issues)
	if [ -d "dist/activitywatch/aw-qt" ]; then \
		cp -r "dist/activitywatch/aw-qt/"* "dist/activitywatch/" || { echo "ERROR: Failed to copy aw-qt files"; exit 1; }; \
		rm -rf "dist/activitywatch/aw-qt"; \
	fi
# Copy version file for installer
	if [ -f "ILS_VERSION" ]; then \
		cp "ILS_VERSION" "dist/activitywatch/" || { echo "ERROR: Failed to copy ILS_VERSION"; exit 1; }; \
		echo "Copied ILS_VERSION to dist/activitywatch/"; \
	fi
# Windows: create lightweight wrappers so aw-qt can discover bundled modules.
# PyInstaller outputs each module into its own directory (dist/<module>/<module>.exe).
# aw-qt only discovers executables in its own directory, so we provide .cmd shims
# that invoke the real executable inside the module directory.
	@uname_output=$$(uname 2>/dev/null || echo ""); \
	if echo "$$uname_output" | grep -qE '^MINGW|^MSYS'; then \
		for m in aw-server aw-watcher-window; do \
			if [ -f "dist/activitywatch/$$m/$$m.exe" ]; then \
				printf '%s\r\n' "@echo off" "setlocal" "\"%~dp0$${m}/$${m}.exe\" %*" > "dist/activitywatch/$$m.cmd"; \
			fi; \
		done; \
	fi
# Remove problem-causing binaries
	rm -f dist/activitywatch/libdrm.so.2       # see: https://github.com/ActivityWatch/activitywatch/issues/161
	rm -f dist/activitywatch/libharfbuzz.so.0  # see: https://github.com/ActivityWatch/activitywatch/issues/660#issuecomment-959889230
# These should be provided by the distro itself
# Had to be removed due to otherwise causing the error:
#   aw-qt: symbol lookup error: /opt/activitywatch/libQt5XcbQpa.so.5: undefined symbol: FT_Get_Font_Format
	rm -f dist/activitywatch/libfontconfig.so.1
	rm -f dist/activitywatch/libfreetype.so.6
# Remove unnecessary files
	rm -rf dist/activitywatch/pytz
# Note: package-all.sh is NOT called here anymore.
# It should be called from build-window.sh AFTER ils-updater.exe is built.
# On non-Windows platforms, you'll need to call it manually or from a platform-specific build script.

clean:
	rm -rf build dist

# Clean all subprojects
clean_all: clean
	for dir in $(SUBMODULES); do \
		make --directory=$$dir clean; \
	done

clean-auto:
	rm -rIv **/aw-android/mobile/build
	rm -rIfv **/node_modules
