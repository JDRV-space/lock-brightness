# Contributing

This is a small local Mac utility, not a general display framework. Keep changes narrow and test them on the machine behavior this repo exists for: brightness changes after plugging or unplugging power.

## Local Checks

```bash
make check
make build
make test
```

`make check` runs static checks without reading or changing brightness.

`make test` is only meaningful on a supported Mac with an active built-in display. It reads current brightness, but does not set brightness. A real plug/unplug cycle is still the important behavior test.

## Notes

- Swift source is in `src/`
- Daemon script is in `scripts/`
- Target bash 3.2 (macOS system default) for shell scripts
- Do not add broad platform claims without testing them

## Useful Bug Reports

- macOS version (`sw_vers`)
- Mac model (`sysctl hw.model`)
- Output of `make status`
- Relevant log lines from `~/.lock-brightness/lock-brightness.log`
- Whether the bug happens on plug, unplug, login, wake, or manual brightness changes
