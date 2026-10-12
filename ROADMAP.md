# Xcalibur Theme Engine Roadmap

---

# v0.1.0 ✅ Bootstrap

Completed

- CLI
- Command Dispatcher
- Configuration System
- Common Library
- Modular Architecture
- Runtime Layout
- Git Repository

---

# v0.2.0 🚧 Wallpaper Manager

Goals

- Wallpaper listing
- Current wallpaper detection
- Wallpaper switching
- Random wallpaper
- Wallpaper state management

---

# v0.3.0 🎨 Color Generation

Goals

- cwal integration
- Automatic palette generation
- Runtime palette storage

---

# v0.4.0 🧩 Template Engine

Goals

- Variable parser
- Template renderer
- Generated outputs

---

# v0.5.0 🖥 Kitty Module

Goals

- Kitty template
- Apply configuration
- Reload terminal

---

# v0.6.0 📊 Waybar Module

Goals

- CSS rendering
- JSON rendering
- Automatic reload

---

# v0.7.0 🖌 GTK Module

Goals

- GTK3 support
- GTK4 support
- Icon themes

---

# v0.8.0 ⚙ Qt Module

Goals

- Qt5 support
- Qt6 support

---

# v0.9.0 📦 Theme Packs

Goals

- Install themes
- Export themes
- Share themes

---

# Phase 4 ✅ External Theme Adapters

Completed on `develop` independently of the version milestones above:

- Native GitHub theme-pack installation remains the shared validation path.
- Catppuccin, Rosé Pine, and Nord official palette formats have dedicated,
  data-only adapters with deterministic native output.
- Installer options, official repository restrictions, source validation,
  atomic destination creation, and temporary cleanup are covered by local
  fixture tests, including the destination creation race.
- User commands, color mappings, adapter contract, limitations, and security
  boundaries are documented in [External theme adapters](docs/external-adapters.md).

---

# Phase 5 ✅ Theme-Pack Lifecycle Management

Completed on `develop` independently of the version milestones above:

- Installed packs have one shared structural validation path for installation,
  inspection, selection, listing, and palette overlay.
- `theme info`, individual and whole-library `theme validate`, and an inventory
  that exposes damaged packs provide read-only diagnostics.
- `theme remove` protects the active pack, rejects unsafe paths and state, and
  does not switch or apply themes.
- Temporary-directory tests cover native and external pack lifecycle, malformed
  packs, symlinks, failed removal, state preservation, and installer regressions.
- Commands, validation limits, and removal behavior are documented in
  [Theme-pack lifecycle](docs/theme-pack-lifecycle.md).

Next: Phase 6 reliability and rollback.

---

# v1.0.0 🚀 Stable Release

Goals

- Documentation
- Testing
- Packaging
- Installation script
- Release
