# External theme importer design

Native Xcalibur installation (`theme install`) and external theme analysis (`theme import analyze`) are separate. The latter currently produces a JSON report only.

## Current boundary

The command accepts a GitHub `owner/repo` reference or an HTTPS GitHub URL. It clones into a private temporary directory without submodules, records the checked-out commit, invokes `engine/importer/analyze.py`, and attempts staging cleanup on normal completion, failure, or handled shell exit signals. Cleanup errors are reported. Git clone and revision lookup use the same restricted configuration. The scanner walks nested directories without following symlinks and applies fixed limits. It reads supported text files as UTF-8 and parses color syntax as data. It never sources source files or copies them into live application configuration. The JSON report is the only intended retained analysis output.

The scanner's intermediate representation is the `inventory` array. Each entry records a path, format, likely application, extracted named colors, role candidates, and confidence. A role is included in top-level `semantic_roles` only when all candidates agree. Conflicts retain every candidate's path and source key. This is a conservative basis for future pack generation: raw source colors and provenance remain available without assigning unsupported roles.

Supported adapters:

- Kitty: literal six-digit hexadecimal values for background, foreground, cursor, selection, and ANSI color keys.
- CSS: literal six-digit hexadecimal custom properties and GTK `@define-color` declarations. Variable references, alpha expressions, and short hex are not resolved.
- Palette: literal `KEY=#RRGGBB` fields in palette or colors `.conf`/`.theme` files.

Known exact names such as `background`, `foreground`, `accent`, and `border` map to semantic roles. The scanner does not infer an accent from `color4` or from an arbitrary CSS selector. It does not resolve CSS variables or copy CSS styling, Kitty settings, scripts, or other application configuration. It does not generate, preview, install, or activate an Xcalibur theme.

## Planned milestones

1. Add fixture-based adapters for well-defined Hyprlock and GTK color forms, plus explicit unsupported-syntax reporting. Keep a source format specification with each adapter.
2. Add a staged pack generator that consumes the inventory, requires an unambiguous minimum set of roles, validates the generated native manifest and palette, and emits a reviewable preview. Do not activate during analysis or generation.
3. Add a reviewed install path using the native pack validator and a safe no-overwrite policy. Record repository and exact commit in separate provenance metadata. Check license obligations before redistribution.
4. Add optional application style adaptation only for settings owned by an explicit module contract. Never import commands, keybindings, startup scripts, or arbitrary dotfiles.

A repository with multiple variants may need user selection before conversion. Unknown licenses, unresolved role conflicts, and unsupported syntax should remain visible in the report. Git clone currently has a time limit but no strict network byte limit; staged import should address download bounds before treating large arbitrary repositories as routine input.
