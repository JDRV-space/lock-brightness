# Changelog

## Unreleased

- Refuse brightness reads and writes when no active built-in display is found.
- Reject non-finite brightness values before calling the private DisplayServices API.
- Reject zero or invalid polling intervals to avoid tight daemon loops.
- Add static local checks and make `make test` exit nonzero on failed assertions.
- Retry failed restores without adopting the unwanted brightness value.
- Reset failure tracking after successful reads and writes.
- Make install configuration persistent and validate the rendered LaunchAgent.
- Make start failures return nonzero and consolidate errors in the rotated log.
- Remove all application-owned files during complete or partial uninstall.

## [1.0.0] - 2026-03-08

- `brightness-ctl` binary for native brightness control on Apple Silicon
- `lock-brightness` daemon that watches for power source changes
- LaunchAgent for automatic startup on login
- `make install` / `make uninstall` for one-command setup
- PID file to prevent duplicate daemon instances
- Log rotation, capped at 100 KB with 2 backups
- Built-in display detection for multi-monitor setups
- Consecutive failure tracking with automatic restart
