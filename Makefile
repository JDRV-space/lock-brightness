PREFIX ?= $(HOME)/.lock-brightness
SWIFT = swiftc
SWIFTFLAGS = -O
SRC = src/brightness-ctl.swift
BIN = brightness-ctl
PLIST_SRC = com.lock-brightness.plist
PLIST_DEST = $(HOME)/Library/LaunchAgents/$(PLIST_SRC)
AGENT_LABEL = com.lock-brightness
UID := $(shell id -u)

.PHONY: all build install uninstall remove-install-files start stop restart status check test-core test clean

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

install: build
	@echo "Installing to $(PREFIX)..."
	@mkdir -p "$(PREFIX)/bin"
	@cp "$(BIN)" "$(PREFIX)/bin/"
	@cp scripts/lock-brightness.sh "$(PREFIX)/bin/lock-brightness"
	@chmod +x "$(PREFIX)/bin/lock-brightness"
	@sed "s|__INSTALL_DIR__|$(PREFIX)|g" "$(PLIST_SRC)" > "$(PLIST_DEST)"
	@echo "Loading LaunchAgent..."
	@launchctl bootout gui/$(UID)/$(AGENT_LABEL) 2>/dev/null || true
	@launchctl bootstrap gui/$(UID) "$(PLIST_DEST)"
	@echo ""
	@echo "Installed and running."
	@echo "  Binary:  $(PREFIX)/bin/brightness-ctl"
	@echo "  Daemon:  $(PREFIX)/bin/lock-brightness"
	@echo "  Agent:   $(PLIST_DEST)"
	@echo "  Log:     $(PREFIX)/lock-brightness.log"

uninstall: stop
	@$(MAKE) --no-print-directory remove-install-files
	@rm -f "$(PLIST_DEST)"

remove-install-files:
	@echo "Removing lock-brightness..."
	@if [ -f "$(PREFIX)/bin/brightness-ctl" ]; then \
		rm -f \
			"$(PREFIX)/bin/brightness-ctl" \
			"$(PREFIX)/bin/lock-brightness" \
			"$(PREFIX)/lock-brightness.log"; \
		rmdir "$(PREFIX)/bin" 2>/dev/null || true; \
		rmdir "$(PREFIX)" 2>/dev/null || true; \
		echo "Uninstalled."; \
	else \
		echo "Nothing to remove (not installed)."; \
	fi

start:
	@launchctl bootstrap gui/$(UID) "$(PLIST_DEST)" 2>/dev/null || \
		launchctl kickstart gui/$(UID)/$(AGENT_LABEL) 2>/dev/null || true
	@sleep 1
	@if launchctl print gui/$(UID)/$(AGENT_LABEL) >/dev/null 2>&1; then \
		echo "Started."; \
	else \
		echo "error: failed to start. Check: cat $(PREFIX)/lock-brightness.log"; \
	fi

stop:
	@launchctl bootout gui/$(UID)/$(AGENT_LABEL) 2>/dev/null || true
	@echo "Stopped."

restart: stop
	@sleep 1
	@$(MAKE) start

status:
	@if launchctl print gui/$(UID)/$(AGENT_LABEL) >/dev/null 2>&1; then \
		echo "lock-brightness is running"; \
		launchctl print gui/$(UID)/$(AGENT_LABEL) 2>/dev/null | grep -E "pid|state" | head -5; \
	else \
		echo "lock-brightness is not running"; \
	fi

check:
	@echo "Running static checks..."
	@bash -n scripts/lock-brightness.sh
	@plutil -lint "$(PLIST_SRC)"
	@$(SWIFT) -typecheck $(SRC) -framework CoreGraphics
	@set -e; \
		test_root=$$(mktemp -d); \
		trap 'rm -rf "$$test_root"' EXIT; \
		test_prefix="$$test_root/install"; \
		mkdir -p "$$test_prefix/bin"; \
		touch "$$test_prefix/bin/brightness-ctl"; \
		touch "$$test_prefix/bin/lock-brightness"; \
		touch "$$test_prefix/keep.me"; \
		$(MAKE) --no-print-directory remove-install-files \
			PREFIX="$$test_prefix" >/dev/null; \
		test -f "$$test_prefix/keep.me"; \
		test ! -e "$$test_prefix/bin/brightness-ctl"; \
		test ! -e "$$test_prefix/bin/lock-brightness"
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
