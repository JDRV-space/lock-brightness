# lock-brightness

Prevent macOS from changing screen brightness when you plug or unplug the charger.

## Problem

Some Apple Silicon MacBooks keep separate brightness values for AC power and battery. Plugging or unplugging power can make macOS jump to the other value, so the screen gets brighter or dimmer even though you did not ask it to.

I could not find a system setting that disables this. The "Slightly dim the display on battery" toggle and `pmset lessbright` did not fix it for me.

## Install

This repo is source-only. There is no signed app, package, tagged source release,
or release binary. The default branch is a development snapshot; build it locally
and include its Git commit when reporting a problem.

Enforced prerequisites:

- macOS 12 or newer
- Apple Silicon Mac
- Active built-in display
- Xcode Command Line Tools: `xcode-select --install`

The build checks the macOS major version and Apple Silicon architecture. Current
automation covers compilation and non-display commands on one GitHub-hosted ARM
Mac runner; the repository does not yet publish a real-device support matrix.

```bash
git clone https://github.com/JDRV-space/lock-brightness.git
cd lock-brightness
make install
```

`make install` builds `brightness-ctl`, copies it to `~/.lock-brightness/bin/`, installs a LaunchAgent, and starts the daemon.

The polling interval defaults to 2 seconds. Set a persistent positive integer
when installing or reinstalling:

```bash
make install POLL_INTERVAL=3
```

If you use a custom `PREFIX`, pass the same `PREFIX` when reinstalling or
uninstalling.

## Local Checks

```bash
make check
make test-core
make test
```

`make check` runs static checks without reading or changing brightness.

`make test-core` builds the helper and runs non-display command checks. `make test`
also reads current brightness, but does not set it. A real plug/unplug cycle on a
supported Mac with an active built-in display remains the behavior test.

## Usage

Check status:

```bash
make status
```

Stop, start, or restart:

```bash
make stop
make start
make restart
```

Read logs:

```bash
cat ~/.lock-brightness/lock-brightness.log
```

Use the brightness keys or System Settings to change brightness. The daemon treats manual changes as the new value to preserve.

You can also call the helper directly:

```bash
~/.lock-brightness/bin/brightness-ctl get
~/.lock-brightness/bin/brightness-ctl set 0.75
```

## Uninstall

```bash
make uninstall
```

This removes the installed helper and daemon, the current and rotated logs, a
legacy stderr log, the PID file, and the LaunchAgent. Empty lock-brightness
directories are removed. Unrelated files inside a custom `PREFIX` are preserved;
uninstall with the same `PREFIX` used for installation.

## How It Works

The LaunchAgent runs `scripts/lock-brightness.sh` at login. The script polls `pmset -g batt` every 2 seconds to detect AC/battery changes.

When the power source changes, the script waits briefly for macOS to apply its own brightness change, then calls `brightness-ctl` to restore the last brightness value it saw. When there is no power change, it reads brightness and updates the stored value if you changed it manually.

If a restore fails, the daemon keeps the previous value and retries it rather
than adopting the brightness macOS applied. Successful reads and writes reset
the consecutive-failure counter.

`brightness-ctl` is a small Swift program that calls `DisplayServicesSetBrightness` and `DisplayServicesGetBrightness` from Apple's private `DisplayServices` framework. It only targets an active built-in display. If it cannot find one, it exits with a display error instead of calling the private API against an external display.

The polling loop is deliberate. It avoids deeper hooks into macOS power/display internals, but it also means this is not instant magic. There can be a small delay after plugging or unplugging power.

## Troubleshooting

```bash
make status
tail -n 50 ~/.lock-brightness/lock-brightness.log
make restart
```

Startup, runtime, and private-API errors all go to the same rotated log. Confirm
that the built-in display is active; closed-lid and external-only setups are not
supported. `make start` and `make restart` return nonzero if the LaunchAgent
cannot be loaded.

Installation is per-user and does not use `sudo`. The repository code does not
request Accessibility or Screen Recording access. If macOS shows an unexpected
permission prompt, include the macOS version and model in a bug report.

## Privacy

The daemon has no network or telemetry code. It stores local logs containing
timestamps, process IDs, power-source transitions, brightness values, and errors.
Review and redact logs or device details before posting them to a public issue.

## Limitations

- Uses Apple's private `DisplayServices` API. Apple can change or remove it in any macOS update, and this can break without warning.
- The build is restricted to Apple Silicon. Runtime compatibility beyond specifically reported test results is unverified; Intel Macs are not supported.
- No tagged or signed release asset exists. You build and run a development snapshot yourself.
- It polls every 2 seconds by default. Lowering the interval to 1 second may make it react faster, but it will wake more often.
- It requires an active built-in display. External display behavior is not supported.
- After 10 consecutive brightness failures, the daemon exits so LaunchAgent can restart it. That does not fix a broken API.

## License

Apache License 2.0. See [LICENSE](LICENSE).

Attribution notices are listed in [NOTICE](NOTICE).
