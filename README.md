# lock-brightness

Prevent macOS from changing screen brightness when you plug or unplug the charger.

## Problem

Some Apple Silicon MacBooks keep separate brightness values for AC power and battery. Plugging or unplugging power can make macOS jump to the other value, so the screen gets brighter or dimmer even though you did not ask it to.

I could not find a system setting that disables this. The "Slightly dim the display on battery" toggle and `pmset lessbright` did not fix it for me.

## Install

This repo is source-only. There is no signed app, package, or release binary. Build it locally.

Requirements:

- macOS 12 or newer
- Apple Silicon Mac
- Active built-in display
- Xcode Command Line Tools: `xcode-select --install`

```bash
git clone https://github.com/JDRV-space/lock-brightness.git
cd lock-brightness
make install
```

`make install` builds `brightness-ctl`, copies it to `~/.lock-brightness/bin/`, installs a LaunchAgent, and starts the daemon.

## Local Checks

```bash
make check
make test
```

`make check` runs static checks without reading or changing brightness.

`make test` builds the helper and runs command checks. It reads current brightness, but does not set brightness. It requires a supported Mac with an active built-in display.

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

The polling interval defaults to 2 seconds. To change it, edit the LaunchAgent environment or run the script with `LOCK_BRIGHTNESS_INTERVAL` set to a positive integer number of seconds.

## Uninstall

```bash
make uninstall
```

This removes only lock-brightness files, its log, and the LaunchAgent. Empty
lock-brightness directories are removed. Unrelated files inside a custom
`PREFIX` are preserved. If you installed with a custom `PREFIX`, uninstall
with the same `PREFIX`.

## How It Works

The LaunchAgent runs `scripts/lock-brightness.sh` at login. The script polls `pmset -g batt` every 2 seconds to detect AC/battery changes.

When the power source changes, the script waits briefly for macOS to apply its own brightness change, then calls `brightness-ctl` to restore the last brightness value it saw. When there is no power change, it reads brightness and updates the stored value if you changed it manually.

`brightness-ctl` is a small Swift program that calls `DisplayServicesSetBrightness` and `DisplayServicesGetBrightness` from Apple's private `DisplayServices` framework. It only targets an active built-in display. If it cannot find one, it exits with a display error instead of calling the private API against an external display.

The polling loop is deliberate. It avoids deeper hooks into macOS power/display internals, but it also means this is not instant magic. There can be a small delay after plugging or unplugging power.

## Limitations

- Uses Apple's private `DisplayServices` API. Apple can change or remove it in any macOS update, and this can break without warning.
- Apple Silicon only unless tested otherwise. Intel Macs are not supported by this repo.
- No signed release asset exists. You build and run the local binary yourself.
- It polls every 2 seconds by default. Lowering the interval to 1 second may make it react faster, but it will wake more often.
- It requires an active built-in display. External display behavior is not supported.
- If brightness reads or writes keep failing, the daemon exits so LaunchAgent can restart it. That does not fix a broken API.

## License

Apache License 2.0. See [LICENSE](LICENSE).

Attribution notices are listed in [NOTICE](NOTICE).
