#!/bin/bash
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d)
DAEMON_PID=""

cleanup() {
    if [ -n "$DAEMON_PID" ]; then
        kill -TERM "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM

write_fakes() {
    scenario_root=$1
    mkdir -p "$scenario_root/bin" "$scenario_root/fake-bin"

    cat > "$scenario_root/fake-bin/pmset" <<'EOF'
#!/bin/bash
count_file="$TEST_STATE_DIR/pmset-count"
count=0
[ -f "$count_file" ] && read -r count < "$count_file"
count=$((count + 1))
echo "$count" > "$count_file"

if [ "$TEST_SCENARIO" = retry ] && [ "$count" -gt 1 ]; then
    state="AC Power"
else
    state="Battery Power"
fi
printf "Now drawing from '%s'\n" "$state"
EOF

    cat > "$scenario_root/bin/brightness-ctl" <<'EOF'
#!/bin/bash
case "$1" in
    get)
        count_file="$TEST_STATE_DIR/get-count"
        count=0
        [ -f "$count_file" ] && read -r count < "$count_file"
        count=$((count + 1))
        echo "$count" > "$count_file"

        if [ "$TEST_SCENARIO" = intermittent ] && [ "$count" -gt 1 ] && [ $((count % 2)) -eq 0 ]; then
            exit 2
        elif [ "$TEST_SCENARIO" = retry ] && [ "$count" -gt 1 ]; then
            echo 0.8000
        else
            echo 0.5000
        fi
        ;;
    set)
        count_file="$TEST_STATE_DIR/set-count"
        count=0
        [ -f "$count_file" ] && read -r count < "$count_file"
        count=$((count + 1))
        echo "$count" > "$count_file"

        if [ "$TEST_SCENARIO" = retry ] && [ "$count" -eq 1 ]; then
            exit 2
        fi
        echo "$2" > "$TEST_STATE_DIR/restored-value"
        ;;
    *)
        exit 1
        ;;
esac
EOF

    cat > "$scenario_root/fake-bin/sleep" <<'EOF'
#!/bin/bash
count_file="$TEST_STATE_DIR/sleep-count"
count=0
[ -f "$count_file" ] && read -r count < "$count_file"
count=$((count + 1))
echo "$count" > "$count_file"

if [ "$count" -ge "$TEST_SLEEP_LIMIT" ]; then
    kill -TERM "$PPID"
fi
EOF

    chmod +x \
        "$scenario_root/bin/brightness-ctl" \
        "$scenario_root/fake-bin/pmset" \
        "$scenario_root/fake-bin/sleep"
}

run_daemon() {
    scenario=$1
    sleep_limit=$2
    scenario_root="$TEST_ROOT/$scenario"
    write_fakes "$scenario_root"

    PATH="$scenario_root/fake-bin:$PATH" \
        TEST_STATE_DIR="$scenario_root" \
        TEST_SCENARIO="$scenario" \
        TEST_SLEEP_LIMIT="$sleep_limit" \
        LOCK_BRIGHTNESS_DIR="$scenario_root" \
        LOCK_BRIGHTNESS_INTERVAL=1 \
        bash "$REPO_ROOT/scripts/lock-brightness.sh" &
    DAEMON_PID=$!

    status=0
    wait "$DAEMON_PID" || status=$?
    DAEMON_PID=""

    if [ "$status" -ne 0 ]; then
        echo "FAIL: $scenario daemon exited $status" >&2
        exit 1
    fi
}

run_daemon retry 3
test "$(cat "$TEST_ROOT/retry/set-count")" -eq 2
test "$(cat "$TEST_ROOT/retry/restored-value")" = 0.5000
grep -q "Restored brightness to 0.5000 after retry" \
    "$TEST_ROOT/retry/lock-brightness.log"

run_daemon intermittent 25
test "$(cat "$TEST_ROOT/intermittent/get-count")" -gt 20

echo "Daemon recovery checks passed."
