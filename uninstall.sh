#!/usr/bin/env bash
# Removes a theme/colorscheme installed by install.sh and restores
# whatever settings.ini backups it made.
#
# Pass the same --name (and --dest/--colors-dest/--global, if you used
# them) that you passed to install.sh, so this can find what it made.

set -euo pipefail

THEME_NAME="Breeze-Onyx"
GTK_DEST="$HOME/.local/share/themes"
COLORS_DEST="$HOME/.local/share/color-schemes"
CONFIG_ROOT="$HOME/.config"
REVERT_TO="BreezeDark"

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [options]

  -n, --name NAME         Theme/colorscheme name to remove (default: Breeze-Onyx)
  -d, --dest DIR          Where the GTK theme was installed
  --colors-dest DIR       Where the color scheme was installed
  --global                Remove from /usr/share instead of your home directory
  --revert-to ID          Colorscheme to switch back to (default: BreezeDark)
  -h, --help              Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--name) THEME_NAME="$2"; shift 2 ;;
        -d|--dest) GTK_DEST="$2"; shift 2 ;;
        --colors-dest) COLORS_DEST="$2"; shift 2 ;;
        --global) GTK_DEST="/usr/share/themes"; COLORS_DEST="/usr/share/color-schemes"; shift ;;
        --revert-to) REVERT_TO="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

SCHEME_ID="${THEME_NAME//-/}"

echo "==> Removing GTK theme: $GTK_DEST/$THEME_NAME"
rm -rf "${GTK_DEST:?}/${THEME_NAME:?}"

echo "==> Removing Plasma color scheme: $COLORS_DEST/$SCHEME_ID.colors"
rm -f "$COLORS_DEST/$SCHEME_ID.colors"

echo "==> Restoring GTK settings.ini backups"
for ver in 3.0 4.0; do
    cfg="$CONFIG_ROOT/gtk-$ver/settings.ini"
    bak="$cfg.bak-$SCHEME_ID"
    marker="$cfg.created-by-$SCHEME_ID"
    if [ -f "$marker" ]; then
        rm -f "$cfg" "$marker"
        echo "    removed $cfg (was created by install.sh)"
    elif [ -f "$bak" ]; then
        mv "$bak" "$cfg"
        echo "    restored $cfg"
    elif [ -f "$cfg" ]; then
        sed -i "/^gtk-theme-name=$THEME_NAME\$/d" "$cfg"
        echo "    stripped gtk-theme-name from $cfg (no backup was present)"
    fi
done

echo "==> Restoring libadwaita background override in $CONFIG_ROOT/gtk-4.0/gtk.css"
cfg4="$CONFIG_ROOT/gtk-4.0"
target="$cfg4/gtk.css"
marker="$cfg4/gtk.css.created-by-$SCHEME_ID"
bak="$cfg4/gtk.css.bak-$SCHEME_ID"
if [ -f "$marker" ]; then
    rm -f "$target" "$marker"
    if [ -e "$bak" ]; then
        mv "$bak" "$target"
        echo "    restored $target"
    else
        echo "    removed $target (was created by install.sh)"
    fi
fi

if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    echo "==> Reverting to $REVERT_TO colorscheme"
    plasma-apply-colorscheme "$REVERT_TO" || \
        echo "    (couldn't auto-revert — pick a colorscheme manually in System Settings > Colors)"
fi

echo "==> Done. If a GTK app picker (e.g. System Settings > Application Style)"
echo "    still shows $THEME_NAME as selected, reselect a different theme there."
