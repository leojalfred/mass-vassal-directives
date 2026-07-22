#!/usr/bin/env bash
# The in-game half of the compatibility harness: inject the runtime check into a
# built mod, or remove it.
#
# tools/check_compat_static.sh is the primary tool and runs against files in seconds.
# This one covers what a file scan cannot: that the panel's GUI mechanisms still
# work when composed at runtime. Reach for it after check_compat_static.sh passes but
# something still misbehaves in game, or on a major patch where you want to see
# the tricks run rather than trust that the names are enough.
#
# It lives in compat_ingame/, which tools/build.sh does not copy (GAME_DIRS is
# only common/gui/events/localization), so it can never reach a real build by
# accident. This script puts it into a dist so the game loads it, and takes it
# back out. Re-running build.sh also wipes it.
#
#   bash tools/check_compat_ingame.sh            inject into dist/vanilla
#   bash tools/check_compat_ingame.sh dist/agot  inject into another build
#   bash tools/check_compat_ingame.sh --remove   take it back out
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=dist/vanilla
REMOVE=no
for a in "$@"; do
	case $a in
		--remove) REMOVE=yes ;;
		*) TARGET=$a ;;
	esac
done
OUT="$ROOT/$TARGET"

[ -d "$OUT" ] || { echo "no such build: $TARGET (run tools/build.sh first)" >&2; exit 1; }

# Every file the check owns, so removal is exact rather than a guess.
FILES="
gui/leo_mvd_compat.gui
gui/scripted_widgets/leo_mvd_compat_widgets.txt
common/scripted_guis/leo_mvd_compat_sguis.txt
localization/english/leo_mvd_compat_l_english.yml
"

if [ "$REMOVE" = yes ]; then
	for f in $FILES; do rm -f "$OUT/$f"; done
	echo "runtime check removed from $TARGET"
	exit 0
fi

# The game needs a UTF-8 BOM on .txt/.gui/.yml, same as the real build.
add_bom() {
	head -c3 "$1" | grep -q $'\xef\xbb\xbf' && return 0
	printf '\xef\xbb\xbf' | cat - "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

for f in $FILES; do
	mkdir -p "$OUT/$(dirname "$f")"
	cp "$ROOT/compat_ingame/$f" "$OUT/$f"
	add_bom "$OUT/$f"
done

echo "runtime check injected into $TARGET"
echo "load that build with -debug_mode. A window appears top-left: press Build,"
echo "open the dropdown, click a row. Rows should read real condition names and"
echo "the picked code should match what you click. Watch error.log for"
echo "leo_mvd_compat, then run tools/check_compat_ingame.sh --remove (or tools/build.sh)."
