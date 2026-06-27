# Architecture

## Data flow

```text
Normal Noctalia palette
        │
        ├─ plugin-managed template post-hook ───────────────┐
        │                                                   │
Album Aura palette (`AlbumAura.json`) ── direct read ──────┤
        │                                                   ├─ service.luau
Nocky bridge (`album-aura.json`) ── exact palette read ─────┘
                                                            │
                                                            ▼
                                                  apply_color.py
                                                            │
                                      exact color or pastel-only correction
                                                            │
                                                            ▼
                                    one OpenRGB process for all devices
```

## Why a template bridge still exists

Noctalia's plugin runtime exposes configuration, state, subprocesses and files,
but not a direct API for reading the currently resolved palette role values.
The plugin therefore installs a minimal Noctalia app-theme template whose
post-hook sends `colors.primary.default.hex_stripped` back to the service over
plugin IPC.

This bridge is managed by the plugin and is not the product's user interface.
All user-facing controls remain native plugin settings.

## Source priority

1. Nocky exact palette, when its bridge contains `palette` or `palette_path`.
2. Album Aura active palette, when the current scheme is `custom AlbumAura`.
3. Normal Noctalia primary color from the template bridge.

Identical color/source updates are deduplicated.

## State separation

- Plugin settings: owned by Noctalia.
- Runtime pause state: persisted under the XDG state directory.
- Last applied color and diagnostics: shared through `noctalia.state`.
- OpenRGB process lock: stored under `XDG_RUNTIME_DIR`.

## Color correction

HSV correction is applied only when all conditions are true:

- correction is enabled;
- saturation is at least `0.08`, avoiding hue-shifting white/gray;
- saturation is below the configured pastel threshold;
- brightness is above the configured brightness threshold.

The hue is never changed.
