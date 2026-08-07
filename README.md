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

**v0.1.0 – Bootstrap Framework**

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

## Planned Features

- Wallpaper Manager
- cwal Integration
- Template Rendering Engine
- Kitty Module
- Waybar Module
- GTK Theme Support
- Qt Theme Support
- Theme Packs
- Automatic Reload System
- Modular Plugin Architecture

---

## Current Commands

```bash
theme help
theme version
theme status
theme doctor
```

Upcoming:

```bash
theme wallpaper list
theme wallpaper current
theme wallpaper set
theme wallpaper random
```

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
