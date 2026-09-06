#!/usr/bin/env bash
# breeze-onyx — Breeze Dark, but with a customizable dark background.
#
# Unlike a "patch what's currently installed" script, this ships its own
# copy of Breeze-Dark's GTK 2/3/4 theme and Plasma color scheme under
# src/, with the background-related color declarations replaced by a
# %%BG_HEX%%/%%BG_RGB%% token. install.sh "builds" the theme by
# substituting that token for the color you asked for, then copies the
# result into your theme directories. It never reads from or depends on
# whatever Breeze build happens to be installed on the system — the
# theme is fully self-contained here, the same way vinceliuice's
# WhiteSur-gtk-theme/WhiteSur-kde ship their own sources and build from
# them rather than re-coloring your live GTK/Adwaita install.
#
# libadwaita apps (gnome-calculator, Nautilus, ...) are a separate case:
# they ignore GTK theme directories and gtk-theme-name entirely. For
# those, src/gtk4-adwaita/adwaita-onyx.css.in vendors libadwaita's own
# named-color contract (pulled from libadwaita-1.so.0's
# defaults-dark.css) with only the *_bg_color tokens templated — same
# "diff against a real upstream file, touch only backgrounds" approach
# as the rest of this repo, just targeting libadwaita's own variables
# instead of Breeze's.

set -euo pipefail

REPO_SLUG="hmwassim/breeze-onyx"
REPO_REF="main"

resolve_root_dir() {
    # Normal case: script was cloned/downloaded and run as ./install.sh,
    # so its src/ tree sits right next to it.
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -d "$script_dir/src" ]; then
            ROOT_DIR="$script_dir"
            return
        fi
    fi

    # curl | bash case: only this script's text was piped in — ${BASH_SOURCE[0]}
    # isn't even set, and there's no src/ tree anywhere on disk. Fetch the
    # rest of the repo into a temp dir instead of failing.
    echo "==> Running standalone (no local src/ tree found) — fetching breeze-onyx from GitHub" >&2
    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        echo "error: need curl and tar to self-fetch; or clone the repo yourself and run ./install.sh" >&2
        exit 1
    fi
    local tmp
    tmp="$(mktemp -d)"
    if ! curl -fsSL "https://github.com/$REPO_SLUG/archive/refs/heads/$REPO_REF.tar.gz" \
            | tar -xz -C "$tmp" --strip-components=1; then
        echo "error: couldn't download https://github.com/$REPO_SLUG (ref: $REPO_REF)" >&2
        rm -rf "$tmp"
        exit 1
    fi
    FETCHED_ROOT_DIR="$tmp"
    ROOT_DIR="$tmp"
}

ROOT_DIR=""
FETCHED_ROOT_DIR=""
resolve_root_dir
SRC_GTK="$ROOT_DIR/src/gtk"
SRC_COLORS="$ROOT_DIR/src/colors/BreezeOnyx.colors.in"
SRC_ADWAITA="$ROOT_DIR/src/gtk4-adwaita/adwaita-onyx.css.in"

# --- presets --------------------------------------------------------------

declare -A PRESETS=(
    [onyx]="151515"
    [black]="000000"
    [charcoal]="181818"
    [graphite]="1e1e1e"
)

# --- defaults (overridable via flags) --------------------------------------

THEME_NAME="Breeze-Onyx"
SCHEME_NAME="Breeze Onyx"
BG_ARG="onyx"
GTK_DEST="$HOME/.local/share/themes"
COLORS_DEST="$HOME/.local/share/color-schemes"
CONFIG_ROOT="$HOME/.config"
DO_GTK=1
DO_PLASMA=1
APPLY=1
GTK4_OVERRIDE=1

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

  -n, --name NAME         Installed theme/colorscheme display name
                          (default: Breeze-Onyx)
  -b, --bg PRESET|HEX     Background color: a preset name (onyx, black,
                          charcoal, graphite) or a raw hex value like
                          1a1a1a (default: onyx / #151515)
  -d, --dest DIR          Where to install the GTK theme
                          (default: ~/.local/share/themes)
      --colors-dest DIR   Where to install the Plasma color scheme
                          (default: ~/.local/share/color-schemes)
      --global            Install to /usr/share instead of your home
                          directory (needs sudo; skips auto-apply)
  -g, --gtk-only          Only build/install the GTK 2/3/4 theme
  -p, --plasma-only       Only build/install the Plasma color scheme
      --no-apply          Build and install, but don't touch
                          settings.ini or auto-switch the colorscheme
      --no-gtk4-override  Don't touch ~/.config/gtk-4.0/gtk.css (see
                          "About GTK4/libadwaita apps" in the README —
                          without this, apps like gnome-calculator,
                          gnome-text-editor, and Nautilus won't pick up
                          the background color at all)
  -h, --help              Show this help
EOF
}

# --- arg parsing ------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--name) THEME_NAME="$2"; SCHEME_NAME="${2//-/ }"; shift 2 ;;
        -b|--bg) BG_ARG="$2"; shift 2 ;;
        -d|--dest) GTK_DEST="$2"; shift 2 ;;
        --colors-dest) COLORS_DEST="$2"; shift 2 ;;
        --global)
            GTK_DEST="/usr/share/themes"
            COLORS_DEST="/usr/share/color-schemes"
            APPLY=0
            shift ;;
        -g|--gtk-only) DO_PLASMA=0; shift ;;
        -p|--plasma-only) DO_GTK=0; shift ;;
        --no-apply) APPLY=0; shift ;;
        --no-gtk4-override) GTK4_OVERRIDE=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -n "${PRESETS[$BG_ARG]:-}" ]; then
    BG_HEX="${PRESETS[$BG_ARG]}"
else
    BG_HEX="$BG_ARG"
fi

BG_HEX="${BG_HEX#\#}"
if ! [[ "$BG_HEX" =~ ^[0-9a-fA-F]{6}$ ]]; then
    echo "error: '--bg' needs a 6-digit hex value (e.g. 151515) or one of: ${!PRESETS[*]}" >&2
    exit 1
fi
BG_HEX="$(echo "$BG_HEX" | tr 'A-F' 'a-f')"
BG_RGB="$((16#${BG_HEX:0:2})),$((16#${BG_HEX:2:2})),$((16#${BG_HEX:4:2}))"

SCHEME_ID="${THEME_NAME//-/}"

# --- build -------------------------------------------------------------

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR" "$FETCHED_ROOT_DIR"' EXIT

render() {
    # render <template-file> <output-file>
    sed \
        -e "s/%%BG_HEX%%/$BG_HEX/g" \
        -e "s/%%BG_RGB%%/$BG_RGB/g" \
        -e "s/%%SCHEME_ID%%/$SCHEME_ID/g" \
        -e "s/%%SCHEME_NAME%%/$SCHEME_NAME/g" \
        "$1" > "$2"
}

if [ "$DO_GTK" = 1 ]; then
    echo "==> Building GTK theme (background #$BG_HEX) -> $BUILD_DIR/gtk"
    cp -r "$SRC_GTK" "$BUILD_DIR/gtk"
    render "$SRC_GTK/gtk-2.0/gtkrc.in" "$BUILD_DIR/gtk/gtk-2.0/gtkrc"
    rm "$BUILD_DIR/gtk/gtk-2.0/gtkrc.in"
    for ver in 3.0 4.0; do
        render "$SRC_GTK/gtk-$ver/gtk.css.in" "$BUILD_DIR/gtk/gtk-$ver/gtk.css"
        rm "$BUILD_DIR/gtk/gtk-$ver/gtk.css.in"
    done

    echo "==> Installing GTK theme -> $GTK_DEST/$THEME_NAME"
    mkdir -p "$GTK_DEST"
    rm -rf "${GTK_DEST:?}/$THEME_NAME"
    cp -r "$BUILD_DIR/gtk" "$GTK_DEST/$THEME_NAME"
fi

if [ "$DO_GTK" = 1 ] && [ "$GTK4_OVERRIDE" = 1 ]; then
    echo "==> Building libadwaita background override"
    render "$SRC_ADWAITA" "$BUILD_DIR/adwaita-onyx.css"
fi

if [ "$DO_PLASMA" = 1 ]; then
    echo "==> Building Plasma color scheme -> $SCHEME_ID.colors"
    render "$SRC_COLORS" "$BUILD_DIR/$SCHEME_ID.colors"

    echo "==> Installing color scheme -> $COLORS_DEST/$SCHEME_ID.colors"
    mkdir -p "$COLORS_DEST"
    cp "$BUILD_DIR/$SCHEME_ID.colors" "$COLORS_DEST/$SCHEME_ID.colors"
fi

# --- apply (best-effort, non-fatal, skipped for --global) ------------------

if [ "$APPLY" = 1 ] && [ "$DO_GTK" = 1 ]; then
    echo "==> Registering GTK theme with kde-gtk-config (GTK3/GTK4 apps)"
    for ver in 3.0 4.0; do
        cfg="$CONFIG_ROOT/gtk-$ver/settings.ini"
        marker="$cfg.created-by-$SCHEME_ID"
        mkdir -p "$(dirname "$cfg")"
        if [ -f "$cfg" ] && [ ! -f "$marker" ]; then
            [ -f "$cfg.bak-$SCHEME_ID" ] || cp "$cfg" "$cfg.bak-$SCHEME_ID"
            if grep -q '^gtk-theme-name=' "$cfg"; then
                sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$THEME_NAME/" "$cfg"
            elif grep -q '^\[Settings\]' "$cfg"; then
                sed -i "/^\[Settings\]/a gtk-theme-name=$THEME_NAME" "$cfg"
            else
                printf '[Settings]\ngtk-theme-name=%s\n' "$THEME_NAME" >> "$cfg"
            fi
        elif [ ! -f "$cfg" ]; then
            printf '[Settings]\ngtk-theme-name=%s\n' "$THEME_NAME" > "$cfg"
            touch "$marker"
        else
            sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$THEME_NAME/" "$cfg"
        fi
    done
fi

if [ "$APPLY" = 1 ] && [ "$DO_GTK" = 1 ] && [ "$GTK4_OVERRIDE" = 1 ]; then
    echo "==> Installing libadwaita background override -> $CONFIG_ROOT/gtk-4.0/gtk.css"
    cfg4="$CONFIG_ROOT/gtk-4.0"
    target="$cfg4/gtk.css"
    marker="$cfg4/gtk.css.created-by-$SCHEME_ID"
    bak="$cfg4/gtk.css.bak-$SCHEME_ID"
    mkdir -p "$cfg4"
    if [ -e "$target" ] && [ ! -f "$marker" ]; then
        # Pre-existing user stylesheet we haven't touched before:
        # back it up once so uninstall.sh can put it back.
        [ -e "$bak" ] || mv "$target" "$bak"
    fi
    rm -f "$target"
    cp "$BUILD_DIR/adwaita-onyx.css" "$target"
    touch "$marker"
    echo "    NOTE: this is a single global override — it applies to every"
    echo "    libadwaita/GTK4 app regardless of which GTK theme is selected,"
    echo "    and only one theme can hold it at a time. It assumes your"
    echo "    system uses a dark color-scheme preference (see README)."
fi

if [ "$APPLY" = 1 ] && [ "$DO_PLASMA" = 1 ]; then
    if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        echo "==> Applying Qt colorscheme via plasma-apply-colorscheme"
        plasma-apply-colorscheme "$SCHEME_ID" || \
            echo "    (couldn't auto-apply — select '$SCHEME_NAME' manually in System Settings > Colors)"
    else
        echo "==> plasma-apply-colorscheme not found — select '$SCHEME_NAME' manually in System Settings > Colors"
    fi
fi

echo "==> Done."
echo "    Installed as '$THEME_NAME' / '$SCHEME_NAME' ($SCHEME_ID)."
echo "    GTK2 apps: log out/in, or set GTK2_RC_FILES / ~/.gtkrc-2.0 to pick it up."
echo "    GTK3 apps: pick it up immediately, or after a re-login."
if [ "$APPLY" = 1 ] && [ "$DO_GTK" = 1 ] && [ "$GTK4_OVERRIDE" = 1 ]; then
    echo "    GTK4/libadwaita apps: restart them (or log out) to pick up the override."
fi
echo "    Run './uninstall.sh --name $THEME_NAME' to remove it."
