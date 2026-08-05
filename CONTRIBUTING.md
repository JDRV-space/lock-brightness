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

## Documentation Ownership

- Keep `README.md` focused on public purpose, prerequisites, usage, limitations, and authoritative links.
- Treat code, tests, `Makefile`, and the LaunchAgent plist as the source of implemented behavior; documentation does not prove implementation, release, or current external state.
- Keep released history in `CHANGELOG.md` and changing work in GitHub Issues or dated evidence, not stable guides.
- Update the existing owner instead of adding competing guides, copied policy, progress notes, or session notes.
- Require test evidence before publishing platform, hardware, security, performance, or release claims.

## Useful Bug Reports

- Source commit (`git rev-parse HEAD`) and helper version (`brightness-ctl version`)
- macOS version (`sw_vers`)
- Mac model (`sysctl hw.model`)
- Output of `make status`
- Relevant, reviewed log lines from `~/.lock-brightness/lock-brightness.log`
- Whether the bug happens on plug, unplug, login, wake, or manual brightness changes

Do not disclose vulnerabilities in a public issue. Follow [SECURITY.md](SECURITY.md).
