# Changelog

All notable changes to this project will be documented in this file.

This project follows the Keep a Changelog format.

---

## Unreleased

### Added

- Local directory and Git source import, license evidence, conversion provenance, raw ANSI preservation, and installation conflict preview.
- Authoritative `make check` runner, CI workflow, Python unit tests, and failure propagation probe.
- GitHub import preview, data-only conversion, explicit local installation, and Hyprlock color adapter.
- Explicit-prefix package installation and ownership-checked uninstall.

### Changed

- Application installation snapshots and restores known destinations on failures.
- Wallpaper and theme state commits occur after application stages succeed.
- CWAL generation uses isolated configuration and output, with a timeout.
- Waybar and SwayNC use supported reload signals or clients; Wofi and GTK avoid disrupting user sessions.
- Legacy wallpaper scripts delegate to the repository CLI.
- Engine settings are parsed as validated data; generated module files are staged until application succeeds.

### Security

- Import scanning bounds directories and opens candidate files without following final-component symlinks.
- Native theme manifest versions are validated, and malformed state returns a failure status.

## [v0.1.0] - Bootstrap Framework

### Added

- Initial project structure
- Theme CLI
- Command dispatcher
- Configuration loader
- Common utility library
- Runtime directories
- Modular architecture
- Wallpaper command skeleton
- Doctor command
- Status command
- Version command
- Git repository
- Development branch
