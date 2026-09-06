# breeze-onyx

Breeze Dark, but the background is darker. Everything else — accent
blue, selection color, foregrounds, disabled-state colors — is
untouched.

## How this is different from the first version

The original version of this script copied your **currently installed**
Breeze-Dark (from `/usr/share`) and patched the copy at install time. It
worked, but it meant the "theme" wasn't really a thing you owned — it
was a runtime side effect of whatever `breeze-gtk-theme` build happened
to be on your system that day.

This version instead vendors its own copy of Breeze-Dark's GTK 2/3/4
theme and Plasma color scheme under `src/`, the same way projects like
[vinceliuice's WhiteSur-gtk-theme](https://github.com/vinceliuice/WhiteSur-gtk-theme)
and [WhiteSur-kde](https://github.com/vinceliuice/WhiteSur-kde) ship
their own theme sources instead of re-coloring whatever GNOME/Adwaita
or Breeze build is currently installed:

- `src/gtk/` — the Breeze-Dark GTK theme (assets, GTK2 widget rules,
  and GTK3/GTK4 CSS), with only the background-related color
  declarations replaced by a `%%BG_HEX%%` token.
- `src/colors/BreezeOnyx.colors.in` — the Breeze Dark Plasma color
  scheme, with the same background fields replaced by `%%BG_RGB%%`.

`install.sh` is now a small build step: it substitutes your chosen
color into those templates in a temp directory, then copies the result
into your theme directories. It never reads `/usr/share` at all, so it
doesn't care what version of Breeze (if any) is installed on the
system, and it can produce more than one variant side by side.

## Install

Either clone it and run the script locally:

```sh
git clone https://github.com/hmwassim/breeze-onyx.git
cd breeze-onyx
./install.sh
```

...or run it standalone with curl. install.sh detects when it's not
sitting next to its own `src/` tree (which is always true for a piped
script — none of the repo's other files travel with it) and fetches
the rest of the repo into a temp dir automatically before building:

```sh
curl -sL https://raw.githubusercontent.com/hmwassim/breeze-onyx/main/install.sh | bash
```

Flags work the same either way, just passed after `-s --` when piped:

```sh
curl -sL https://raw.githubusercontent.com/hmwassim/breeze-onyx/main/install.sh | bash -s -- --bg black
./install.sh                                   # Breeze-Onyx, #151515
./install.sh --bg black                        # a preset
./install.sh --bg 1a1a2e                       # any hex you like
./install.sh --name Breeze-Onyx-Black --bg black   # install two variants side by side
./install.sh --global                          # /usr/share instead of ~/.local/share (needs sudo)
```

Full options:

```
-n, --name NAME         Installed theme/colorscheme display name (default: Breeze-Onyx)
-b, --bg PRESET|HEX     onyx (#151515, default) | black | charcoal | graphite | any 6-digit hex
-d, --dest DIR          GTK theme install dir (default: ~/.local/share/themes)
    --colors-dest DIR   Plasma color scheme install dir (default: ~/.local/share/color-schemes)
    --global            Install to /usr/share instead (skips auto-apply)
-g, --gtk-only          Only build/install the GTK 2/3/4 theme
-p, --plasma-only       Only build/install the Plasma color scheme
    --no-apply          Install without touching settings.ini or auto-switching colors
    --no-gtk4-override  Don't touch ~/.config/gtk-4.0/gtk.css (see below)
-h, --help              Show help
```

By default `install.sh` also registers the GTK theme in
`~/.config/gtk-3.0/settings.ini` / `gtk-4.0/settings.ini` (backing up
whatever was there first) and tries `plasma-apply-colorscheme` to
switch your Qt colorscheme automatically.

## Uninstall

```sh
./uninstall.sh --name Breeze-Onyx
```

Pass the same `--name` (and `--dest`/`--colors-dest`/`--global`, if you
used them) you passed to `install.sh`, so it knows what to remove.
Restores your original `settings.ini` files, or deletes them if
`install.sh` created them from scratch.

## What it changes

- **Plasma** (`BackgroundNormal` in the `Window`, `View`, and `Header`
  color sets, plus the WM active/inactive titlebar background).
  `BackgroundAlternate`, buttons, tooltips, and selection colors are
  left alone.
- **GTK 2** (`gtkrc`): `bg_color` and `base_color`.
- **GTK 3 / GTK 4** (`gtk.css`): `theme_bg_color`, `theme_base_color`,
  their `unfocused` counterparts, `content_view_bg`, and the three
  titlebar background variants.

Disabled-widget backgrounds and tooltips aren't touched.

## About GTK4/libadwaita apps

Apps like `gnome-calculator`, `gnome-text-editor`, and Nautilus are
libadwaita apps. Libadwaita ignores `gtk-theme-name` completely — it
never reads `~/.local/share/themes/<name>/gtk-4.0/` at all, themed or
not. It also doesn't use Breeze's CSS variable names
(`theme_bg_color_breeze` etc.) — it has its own named-color contract
(`window_bg_color`, `view_bg_color`, `headerbar_bg_color`, ...).

So rather than copying Breeze's GTK4 stylesheet somewhere libadwaita
would never read the right variables from it, `src/gtk4-adwaita/adwaita-onyx.css.in`
is a small, purpose-built override containing only those named colors,
extracted straight from libadwaita's own dark palette
(`org/gnome/Adwaita/styles/defaults-dark.css`, pulled out of
`libadwaita-1.so.0` with `gresource extract` so the base values are
exactly upstream's, not guessed). Only the `*_bg_color` /
`*_backdrop_color` tokens are templated with `%%BG_HEX%%`; everything
else — foregrounds, `accent_color`, the destructive/success/warning/error
colors, `card_bg_color` (a translucent overlay, not an absolute color)
— is left for libadwaita to provide itself, same "touch only the
background" scope as the rest of this project.

`install.sh` writes the built file to `$XDG_CONFIG_HOME/gtk-4.0/gtk.css`
— confirmed from GTK's own source comments to be the one file GTK4
always loads from that directory, with higher priority than any theme
(there's no `gtk-dark.css` equivalent for this particular path, so
earlier revisions of this script writing one there was a no-op).
A few things worth knowing:

- It's a **global override**: every libadwaita app gets it, regardless
  of which GTK theme is selected anywhere. Only one theme can hold this
  file at a time — installing a different libadwaita-targeting theme
  later will overwrite it.
- It assumes your system is already using a **dark** color-scheme
  preference, same as the rest of breeze-onyx. It doesn't touch
  foreground colors, so if your system is in light mode this will
  produce a dark background with light-mode (dark) text — pass
  `--no-gtk4-override` if that's your setup.
- Whatever was at `~/.config/gtk-4.0/gtk.css` before is backed up to
  `gtk.css.bak-<SchemeId>` and restored by `uninstall.sh`. If nothing
  was there, `uninstall.sh` removes it outright.
- Libadwaita reads the file once at startup, so open apps need a
  restart — Nautilus in particular runs as a background service and
  may need `killall nautilus` or a logout.

Non-libadwaita GTK4 apps (there are very few — Transmission is the
usual example) read the theme directory normally via `gtk-theme-name`
and don't need this override.

## Provenance & license

This project is licensed under the GNU Lesser General Public License,
version 2.1 or (at your option) any later version (LGPL-2.1-or-later)
— see `LICENSE` for the full text.

`src/gtk/` is based on the `breeze-gtk-theme` package and `src/colors/`
on the `kde-style-breeze` package, both from KDE's
[breeze-gtk](https://invent.kde.org/plasma/breeze-gtk) and
[breeze](https://invent.kde.org/plasma/breeze) repositories
respectively, © 2015 The KDE development team
<kde-core-devel@kde.org>, licensed LGPL-2.1-or-later.

`src/gtk4-adwaita/adwaita-onyx.css.in`'s named-color values are taken
from libadwaita's own dark palette
([libadwaita](https://gitlab.gnome.org/GNOME/libadwaita),
`org/gnome/Adwaita/styles/defaults-dark.css`), © 2019 Alexander
Mikhaylenko and libadwaita contributors, Purism SPC, GNOME Foundation,
Red Hat Inc., and others, licensed LGPL-2.1-or-later.

Only the background-color declarations in these files were changed
from upstream; everything else (layout, other colors, assets) is
unmodified. `install.sh`, `uninstall.sh`, and this README are original
to this project, under the same license.

## Notes

- GTK2 apps generally need a re-login to pick up the theme change.
- If your locale isn't English, the colorscheme's translated `Name[xx]=`
  entries still say "Breeze Dark" in the picker — only the English
  `Name=` is rewritten, to keep the build simple.
