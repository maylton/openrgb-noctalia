# OpenRGB Noctalia

A standalone **Noctalia v5 plugin** that synchronizes OpenRGB devices with the
active Noctalia primary color.

It also integrates with:

- **Album Aura**, by reading the active `AlbumAura.json` palette;
- **Nocky**, by reading its native Album Aura bridge when an exact palette is
  available;
- the normal Noctalia theme system through a small plugin-managed template
  bridge.

## What it does

- applies one color to every detected OpenRGB device in a single OpenRGB process;
- uses **Direct** mode by default, so it does not depend on device order;
- preserves exact colors normally;
- corrects only bright, low-saturation pastel colors that physical LEDs tend to
  reproduce as white;
- exposes native settings under **Noctalia Settings → Plugins**;
- provides an optional Control Center shortcut for pausing/resuming sync;
- supports enable, disable, toggle, refresh, status and cleanup IPC commands;
- keeps logs and last-state diagnostics under the XDG state directory.

## Repository layout

```text
.
├── catalog.toml
├── install.sh
├── uninstall.sh
├── scripts/
│   └── validate.sh
├── tests/
│   └── test_color_transform.py
└── openrgb-noctalia/
    ├── plugin.toml
    ├── service.luau
    ├── shortcut.luau
    ├── apply_color.py
    └── translations/
        ├── en.json
        ├── pt-BR.json
        └── pt_BR.json
```

The plugin folder matches the tail of its canonical ID:

```text
maylton/openrgb-noctalia
```

## Requirements

- Noctalia v5 with Luau plugin support;
- OpenRGB available as `openrgb`;
- Python 3;
- user permissions/udev rules required by OpenRGB.

## Install from the Noctalia plugin manager

Add this repository as a Git source:

```bash
noctalia msg plugins source add openrgb-noctalia git \
  https://github.com/maylton/openrgb-noctalia
```

Then enable the plugin:

```bash
noctalia msg plugins update openrgb-noctalia
noctalia msg plugins enable maylton/openrgb-noctalia
```

The same flow is available in:

```text
Noctalia Settings → Plugins → Add source
```

## Install with the script

After cloning:

```bash
git clone https://github.com/maylton/openrgb-noctalia.git
cd openrgb-noctalia
./install.sh
```

For local development:

```bash
./install.sh --local
```

## Settings

Open:

```text
Noctalia Settings → Plugins → OpenRGB Noctalia
```

Main controls:

- enable or disable synchronization;
- follow Album Aura;
- follow Nocky;
- choose Direct or Static mode;
- enable or disable pastel correction;
- choose notification behavior;
- expose advanced pastel thresholds and SDK-server behavior.

## Control Center shortcut

The plugin includes the shortcut entry:

```text
maylton/openrgb-noctalia:toggle
```

Add it from the Control Center shortcut settings.

- left click: pause/resume RGB synchronization;
- right click: reapply the current color.

The plugin setting remains the master switch. The shortcut controls a persistent
runtime pause state.

## Album Aura integration

When Noctalia reports:

```text
custom AlbumAura
```

the service reads:

```text
~/.config/noctalia/palettes/AlbumAura.json
```

and applies its active light/dark `mPrimary` color directly. This means Album
Aura does not need to refresh every unrelated application template just to
update the LEDs.

## Nocky integration

The service watches:

```text
$XDG_RUNTIME_DIR/nocky/album-aura.json
```

When Nocky publishes an inline exact palette or `palette_path`, the service reads
the active `mPrimary` color and applies it directly. Artwork-only bridge payloads
continue to flow through Album Aura.

## Standard Noctalia themes

The plugin creates and maintains:

```text
~/.config/noctalia/openrgb-noctalia.toml
~/.config/noctalia/templates/openrgb-noctalia-primary.txt.in
```

The generated post-hook sends the exact active primary color back to the plugin
service over Noctalia IPC.

## IPC

```bash
noctalia msg plugin maylton/openrgb-noctalia:sync all apply
noctalia msg plugin maylton/openrgb-noctalia:sync all enable
noctalia msg plugin maylton/openrgb-noctalia:sync all disable
noctalia msg plugin maylton/openrgb-noctalia:sync all toggle
noctalia msg plugin maylton/openrgb-noctalia:sync all status
```

## Logs

```bash
tail -f "${XDG_STATE_HOME:-$HOME/.local/state}/openrgb-noctalia/openrgb-noctalia.log"
```

Example:

```text
album-aura #99B6F2 -> OpenRGB #4C7AD9 (pastel corrected)
noctalia #39BAE6 -> OpenRGB #39BAE6 (exact)
```

## Validation

```bash
./scripts/validate.sh
```

## Uninstall

```bash
./uninstall.sh
```

Remove settings and logs too:

```bash
./uninstall.sh --purge
```

## Current limitation

Noctalia v5 plugins are experimental and their API may change. Direct mode is
the default because it is common across many controllers, but a computer with a
device that lacks Direct mode may need a future per-device fallback.

## License

MIT.
