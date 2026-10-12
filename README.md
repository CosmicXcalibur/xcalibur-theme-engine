# ⚔️ Xcalibur Theme Engine

> A modular, extensible desktop theming framework for Hyprland powered by **cwal**.

---

## Overview

Xcalibur Theme Engine is a modular theming framework designed to automate desktop customization on Hyprland.

Instead of manually configuring every application, Xcalibur provides a unified engine that:

- Generates colors from wallpapers
- Applies themes across multiple applications
- Manages wallpaper state
- Renders templates dynamically
- Reloads applications automatically

The project is designed around a layered architecture to keep the engine scalable and maintainable.

---

## Current Status

🚧 Under Active Development

Current Release:

**v0.1.0 CLI version; external palette adapters and theme-pack lifecycle management completed.**

---

## Architecture

```text
Theme Engine
│
├── CLI
│
├── Commands
│
├── Services
│
├── Libraries
│
├── Runtime
│
└── Modules
```

---

## Directory Structure

```text
theme/
├── assets/
├── config/
├── docs/
├── engine/
│   ├── bin/
│   ├── commands/
│   ├── services/
│   └── lib/
├── modules/
└── runtime/
```

---

## Current Capabilities

- Native GitHub theme-pack installation
- Catppuccin, Rosé Pine, and Nord palette imports
- Validated semantic palette overlays on the existing CWAL color pipeline
- Inspection, validation, inventory, and safe removal of installed packs

See [the roadmap](ROADMAP.md) for planned work and
[external adapter documentation](docs/external-adapters.md) for sources,
color mappings, security boundaries, and test instructions.

---

## Theme Installation

```bash
theme help
theme install owner/repo
theme install catppuccin/palette --format catppuccin --variant mocha
theme install rose-pine/rose-pine-palette --format rose-pine --variant moon
theme install nordtheme/nord --format nord
theme list
theme current
theme info <theme-id>
theme validate <theme-id>
theme validate --all
theme set <theme-id>
theme remove <theme-id>
```

Installation validates and stores a theme. `theme set` selects and applies it.
External imports require their official repository and an explicit variant
when that palette has more than one. `theme info` shows validated metadata and
semantic colors; `theme validate --all` reports every pack and exits nonzero if
any is invalid. `theme remove` deletes only an inactive pack and never switches
themes. See [theme-pack lifecycle](docs/theme-pack-lifecycle.md) for output,
failure behavior, and security limits; use `theme help` for command syntax.

---

## Philosophy

> Build a framework, not a collection of scripts.

Every component has a single responsibility and follows a modular design to ensure long-term maintainability.

---

## Roadmap

See **ROADMAP.md**

---

## Vision

Xcalibur aims to become a modular, open-source desktop theming framework for Linux, making dynamic theming simple, extensible, and maintainable.

The long-term goal is to support not only Hyprland but also a growing ecosystem of Linux desktop applications through a unified theming engine.

---

## Author

Akshay Patel

GitHub:
https://github.com/CosmicXcalibur
