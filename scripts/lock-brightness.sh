#!/bin/bash
# lock-brightness: Prevent macOS from changing brightness on power source changes
#
# How it works:
#   1. Polls power state every 2 seconds by default (negligible CPU, zero GPU)
#   2. When charger is plugged/unplugged, restores brightness to the last known value
#   3. Manual brightness changes are respected and become the new locked value
#
# This exists because macOS on Apple Silicon stores separate brightness values
# for AC and battery power, and there is no setting to disable this behavior.
#
# Targets bash 3.2 (macOS system default)

INSTALL_DIR="${LOCK_BRIGHTNESS_DIR:-$HOME/.lock-brightness}"
CTL="$INSTALL_DIR/bin/brightness-ctl"
LOG="$INSTALL_DIR/lock-brightness.log"
PIDFILE="$INSTALL_DIR/lock-brightness.pid"
POLL_INTERVAL="${LOCK_BRIGHTNESS_INTERVAL:-2}"
MAX_FAILURES=10

validate_poll_interval() {
    case "$POLL_INTERVAL" in
        ''|*[!0-9]*)
            echo "error: LOCK_BRIGHTNESS_INTERVAL must be a positive integer" >&2
            exit 1
            ;;
    esac

    if [ "$POLL_INTERVAL" -lt 1 ]; then
        echo "error: LOCK_BRIGHTNESS_INTERVAL must be at least 1 second" >&2
        exit 1
    fi
}

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

rotate_log() {
    if [ -f "$LOG" ]; then
        local size
        size=$(stat -f%z "$LOG" 2>/dev/null || echo 0)
        if [ "$size" -gt 102400 ]; then
            [ -f "$LOG.2" ] && rm -f "$LOG.2"
            [ -f "$LOG.1" ] && mv "$LOG.1" "$LOG.2"
            mv "$LOG" "$LOG.1"
        fi
    fi
}

cleanup() {
    rm -f "$PIDFILE"
    log_msg "Stopped (PID $$)"
    exit 0
}

trap cleanup SIGTERM SIGINT

validate_poll_interval
rotate_log
exec 2>> "$LOG"

# Check for stale instances
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "error: already running (PID $OLD_PID)" >&2
        exit 1
    fi
    rm -f "$PIDFILE"
fi

# Validate binary exists
if [ ! -x "$CTL" ]; then
    echo "error: brightness-ctl not found at $CTL" >&2
    echo "Run 'make install' from the lock-brightness repository." >&2
    exit 1
fi

# Write PID file
echo $$ > "$PIDFILE"

log_msg "Started (PID $$)"

# Capture initial state
LAST_STATE=$(pmset -g batt | head -1 | grep -o "'.*'" | tr -d "'")
LOCKED_BRIGHTNESS=$("$CTL" get 2>/dev/null || echo "")

if [ -z "$LOCKED_BRIGHTNESS" ]; then
    log_msg "ERROR: could not read initial brightness"
    rm -f "$PIDFILE"
    exit 2
fi

log_msg "Power: $LAST_STATE | Brightness: $LOCKED_BRIGHTNESS"

FAIL_COUNT=0
RESTORE_PENDING=0

while true; do
    STATE=$(pmset -g batt | head -1 | grep -o "'.*'" | tr -d "'")

    if [ "$STATE" != "$LAST_STATE" ] && [ -n "$LAST_STATE" ]; then
        # Power source changed. Poll until brightness stabilizes, then restore.
        sleep 0.2
        for _ in 1 2 3 4 5; do
            AFTER=$("$CTL" get 2>/dev/null || echo "")
            if [ -n "$AFTER" ] && [ "$AFTER" != "$LOCKED_BRIGHTNESS" ]; then
                break
            fi
            sleep 0.1
        done
        if "$CTL" set "$LOCKED_BRIGHTNESS" 2>/dev/null; then
            log_msg "Power: $LAST_STATE -> $STATE | Restored brightness to $LOCKED_BRIGHTNESS"
            FAIL_COUNT=0
            RESTORE_PENDING=0
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            RESTORE_PENDING=1
            log_msg "WARN: failed to restore brightness (attempt $FAIL_COUNT/$MAX_FAILURES)"
        fi
    elif [ "$RESTORE_PENDING" -eq 1 ]; then
        # Keep retrying the original value. Do not adopt the unwanted value
        # that macOS applied during the power-source change.
        if "$CTL" set "$LOCKED_BRIGHTNESS" 2>/dev/null; then
            log_msg "Restored brightness to $LOCKED_BRIGHTNESS after retry"
            FAIL_COUNT=0
            RESTORE_PENDING=0
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log_msg "WARN: failed to restore brightness (attempt $FAIL_COUNT/$MAX_FAILURES)"
        fi
    else
        # No power change. Track manual brightness adjustments so we
        # always restore to the user's preferred level.
        CURRENT=$("$CTL" get 2>/dev/null || echo "")
        if [ -n "$CURRENT" ]; then
            FAIL_COUNT=0
            if [ "$CURRENT" != "$LOCKED_BRIGHTNESS" ]; then
                LOCKED_BRIGHTNESS="$CURRENT"
            fi
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log_msg "WARN: brightness read failed (attempt $FAIL_COUNT/$MAX_FAILURES)"
        fi
    fi

    # Exit after too many consecutive failures so KeepAlive can restart us
    if [ "$FAIL_COUNT" -ge "$MAX_FAILURES" ]; then
        log_msg "ERROR: $MAX_FAILURES consecutive failures, exiting for restart"
        rm -f "$PIDFILE"
        exit 2
    fi

    LAST_STATE="$STATE"
    sleep "$POLL_INTERVAL" || true
done
