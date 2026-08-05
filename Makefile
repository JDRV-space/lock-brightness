PREFIX ?= $(HOME)/.lock-brightness
POLL_INTERVAL ?= 2
SWIFT = swiftc
SWIFTFLAGS = -O
SRC = src/brightness-ctl.swift
BIN = brightness-ctl
PLIST_SRC = com.lock-brightness.plist
PLIST_DEST ?= $(HOME)/Library/LaunchAgents/$(PLIST_SRC)
AGENT_LABEL = com.lock-brightness
LAUNCHCTL ?= launchctl
UID := $(shell id -u)

.PHONY: all build validate-config render-plist install uninstall remove-install-files start stop restart status check test-core test clean

all: build

build:
	@[ $$(sw_vers -productVersion | cut -d. -f1) -ge 12 ] || \
		(echo "error: lock-brightness requires macOS 12 (Monterey) or later" && exit 1)
	@[ "$$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] || \
		(echo "error: lock-brightness is only supported on Apple Silicon Macs" && exit 1)
	@echo "Compiling brightness-ctl..."
	$(SWIFT) $(SWIFTFLAGS) $(SRC) -o $(BIN) \
		-framework CoreGraphics \
		-F /System/Library/PrivateFrameworks \
		-framework DisplayServices
	@echo "Build complete: ./$(BIN)"

validate-config:
	@case "$(POLL_INTERVAL)" in \
		''|*[!0-9]*) echo "error: POLL_INTERVAL must be a positive integer" >&2; exit 1 ;; \
	esac
	@[ "$(POLL_INTERVAL)" -ge 1 ] || \
		(echo "error: POLL_INTERVAL must be at least 1 second" >&2 && exit 1)

render-plist: validate-config
	@mkdir -p "$(dir $(PLIST_DEST))"
	@cp "$(PLIST_SRC)" "$(PLIST_DEST)"
	@plutil -replace ProgramArguments.0 -string \
		"$(PREFIX)/bin/lock-brightness" "$(PLIST_DEST)"
	@plutil -replace EnvironmentVariables.LOCK_BRIGHTNESS_DIR -string \
		"$(PREFIX)" "$(PLIST_DEST)"
	@plutil -replace EnvironmentVariables.LOCK_BRIGHTNESS_INTERVAL -string \
		"$(POLL_INTERVAL)" "$(PLIST_DEST)"
	@plutil -replace StandardErrorPath -string \
		"$(PREFIX)/lock-brightness.log" "$(PLIST_DEST)"
	@plutil -lint "$(PLIST_DEST)" >/dev/null

install: build render-plist
	@echo "Installing to $(PREFIX)..."
	@mkdir -p "$(PREFIX)/bin"
	@cp "$(BIN)" "$(PREFIX)/bin/"
	@cp scripts/lock-brightness.sh "$(PREFIX)/bin/lock-brightness"
	@chmod +x "$(PREFIX)/bin/lock-brightness"
	@echo "Loading LaunchAgent..."
	@$(LAUNCHCTL) bootout gui/$(UID)/$(AGENT_LABEL) 2>/dev/null || true
	@$(LAUNCHCTL) bootstrap gui/$(UID) "$(PLIST_DEST)"
	@echo ""
	@echo "Installed and running."
	@echo "  Binary:  $(PREFIX)/bin/brightness-ctl"
	@echo "  Daemon:  $(PREFIX)/bin/lock-brightness"
	@echo "  Agent:   $(PLIST_DEST)"
	@echo "  Log:     $(PREFIX)/lock-brightness.log"
	@echo "  Poll:    $(POLL_INTERVAL) seconds"

uninstall: stop
	@$(MAKE) --no-print-directory remove-install-files
	@rm -f "$(PLIST_DEST)"

remove-install-files:
	@echo "Removing lock-brightness..."
	@found=0; \
	for path in \
		"$(PREFIX)/bin/brightness-ctl" \
		"$(PREFIX)/bin/lock-brightness" \
		"$(PREFIX)/lock-brightness.log" \
		"$(PREFIX)/lock-brightness.log.1" \
		"$(PREFIX)/lock-brightness.log.2" \
		"$(PREFIX)/stderr.log" \
		"$(PREFIX)/lock-brightness.pid"; do \
		if [ -e "$$path" ]; then \
			rm -f "$$path"; \
			found=1; \
		fi; \
	done; \
	rmdir "$(PREFIX)/bin" 2>/dev/null || true; \
	rmdir "$(PREFIX)" 2>/dev/null || true; \
	if [ "$$found" -eq 1 ]; then \
		echo "Uninstalled."; \
	else \
		echo "Nothing to remove (not installed)."; \
	fi

start:
	@if ! $(LAUNCHCTL) bootstrap gui/$(UID) "$(PLIST_DEST)" 2>/dev/null; then \
		$(LAUNCHCTL) kickstart gui/$(UID)/$(AGENT_LABEL) 2>/dev/null || { \
			echo "error: failed to load lock-brightness" >&2; \
			exit 1; \
		}; \
	fi
	@sleep 1
	@if $(LAUNCHCTL) print gui/$(UID)/$(AGENT_LABEL) >/dev/null 2>&1; then \
		echo "Started."; \
	else \
		echo "error: failed to start. Check: cat $(PREFIX)/lock-brightness.log" >&2; \
		exit 1; \
	fi

stop:
	@$(LAUNCHCTL) bootout gui/$(UID)/$(AGENT_LABEL) 2>/dev/null || true
	@echo "Stopped."

restart: stop
	@sleep 1
	@$(MAKE) start

status:
	@if $(LAUNCHCTL) print gui/$(UID)/$(AGENT_LABEL) >/dev/null 2>&1; then \
		echo "lock-brightness is running"; \
		$(LAUNCHCTL) print gui/$(UID)/$(AGENT_LABEL) 2>/dev/null | grep -E "pid|state" | head -5; \
	else \
		echo "lock-brightness is not running"; \
	fi

check:
	@echo "Running static checks..."
	@bash -n scripts/lock-brightness.sh
	@bash tests/daemon-recovery.sh
	@plutil -lint "$(PLIST_SRC)"
	@$(SWIFT) -typecheck $(SRC) -framework CoreGraphics
	@set -e; \
		test_root=$$(mktemp -d); \
		trap 'rm -rf "$$test_root"' EXIT; \
		test_prefix="$$test_root/install & special"; \
		test_plist="$$test_root/LaunchAgents/$(PLIST_SRC)"; \
		$(MAKE) --no-print-directory render-plist \
			PREFIX="$$test_prefix" \
			POLL_INTERVAL=3 \
			PLIST_DEST="$$test_plist" >/dev/null; \
		test "$$(plutil -extract ProgramArguments.0 raw -o - "$$test_plist")" = \
			"$$test_prefix/bin/lock-brightness"; \
		test "$$(plutil -extract EnvironmentVariables.LOCK_BRIGHTNESS_INTERVAL raw -o - "$$test_plist")" = 3; \
		mkdir -p "$$test_prefix/bin"; \
		for path in \
			"$$test_prefix/bin/brightness-ctl" \
			"$$test_prefix/bin/lock-brightness" \
			"$$test_prefix/lock-brightness.log" \
			"$$test_prefix/lock-brightness.log.1" \
			"$$test_prefix/lock-brightness.log.2" \
			"$$test_prefix/stderr.log" \
			"$$test_prefix/lock-brightness.pid"; do \
			touch "$$path"; \
		done; \
		touch "$$test_prefix/keep.me"; \
		$(MAKE) --no-print-directory remove-install-files \
			PREFIX="$$test_prefix" >/dev/null; \
		test -f "$$test_prefix/keep.me"; \
		test ! -e "$$test_prefix/bin/brightness-ctl"; \
		test ! -e "$$test_prefix/bin/lock-brightness"; \
		test ! -e "$$test_prefix/lock-brightness.log"; \
		test ! -e "$$test_prefix/lock-brightness.log.1"; \
		test ! -e "$$test_prefix/lock-brightness.log.2"; \
		test ! -e "$$test_prefix/stderr.log"; \
		test ! -e "$$test_prefix/lock-brightness.pid"; \
		partial_prefix="$$test_root/partial"; \
		mkdir -p "$$partial_prefix/bin"; \
		touch "$$partial_prefix/bin/lock-brightness"; \
		touch "$$partial_prefix/lock-brightness.log"; \
		$(MAKE) --no-print-directory remove-install-files \
			PREFIX="$$partial_prefix" >/dev/null; \
		test ! -e "$$partial_prefix/bin/lock-brightness"; \
		test ! -e "$$partial_prefix/lock-brightness.log"; \
		status=0; \
		$(MAKE) --no-print-directory start \
			LAUNCHCTL=false \
			PLIST_DEST="$$test_plist" >/dev/null 2>&1 || status=$$?; \
		test "$$status" -ne 0; \
		status=0; \
		$(MAKE) --no-print-directory validate-config \
			POLL_INTERVAL=0 >/dev/null 2>&1 || status=$$?; \
		test "$$status" -ne 0
	@echo "Static checks passed."

test-core: check build
	@echo "Running core tests..."
	@set -e; \
		./$(BIN) version | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$'; \
		echo "  PASS: version"; \
		./$(BIN) --help >/dev/null; \
		echo "  PASS: help"; \
		status=0; ./$(BIN) badcommand >/dev/null 2>&1 || status=$$?; \
		if [ "$$status" -ne 1 ]; then \
			echo "  FAIL: bad command exits 1 (got $$status)"; \
			exit 1; \
		fi; \
		echo "  PASS: bad command exits 1"; \
		status=0; ./$(BIN) set nan >/dev/null 2>&1 || status=$$?; \
		if [ "$$status" -ne 1 ]; then \
			echo "  FAIL: non-finite brightness exits 1 (got $$status)"; \
			exit 1; \
		fi; \
		echo "  PASS: non-finite brightness exits 1"; \
		status=0; LOCK_BRIGHTNESS_INTERVAL=0 scripts/lock-brightness.sh >/dev/null 2>&1 || status=$$?; \
		if [ "$$status" -ne 1 ]; then \
			echo "  FAIL: invalid poll interval exits 1 (got $$status)"; \
			exit 1; \
		fi; \
		echo "  PASS: invalid poll interval exits 1"
	@echo "Core tests complete."

test: test-core
	@echo "Running display test..."
	@set -e; \
		./$(BIN) get >/dev/null; \
		echo "  PASS: get brightness"
	@echo "Tests complete."

clean:
	@rm -f $(BIN)
	@echo "Cleaned."
