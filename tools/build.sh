#!/bin/bash
#
# Builds the two shippable mods from the shared source in this repo:
#
#   dist/vanilla/  the base mod, no A Game of Thrones content
#   dist/agot/     the same plus AGOT's settle_wilderness directive (and, in time,
#                  the Westeros conditions/presets), referencing AGOT's own assets
#
# Each dist holds game files only - no tools, docs, or dev files - so it can be
# pointed at by the launcher and uploaded to the Workshop as-is. dist/ is
# gitignored.
#
# How the AGOT build differs from the base, all applied here rather than gated at
# runtime (there is no runtime AGOT detection):
#   - the panel is regenerated in AGOT mode (settle_wilderness in, nomad out)
#   - small fragments are injected at the base files' # @AGOT:...@ markers
#     (the directive's dispatch, ownership match, and two cust-loc entries)
#   - the AGOT-only files under agot/files/ are copied in (its gate trigger, the
#     wilderness texticons, and the exempt loc keys)
#   - the AGOT descriptor replaces the base one
#
# Usage: bash tools/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"

# The paths that ship. Everything else in the repo (tools, docs, agot, dot-dirs)
# stays out of the built mods.
GAME_DIRS="common gui events localization"
GAME_FILES="thumbnail.png"

copy_base() {   # <destdir>
	local out=$1
	rm -rf "$out"; mkdir -p "$out"
	local d f
	for d in $GAME_DIRS; do cp -r "$ROOT/$d" "$out/"; done
	for f in $GAME_FILES; do cp "$ROOT/$f" "$out/"; done
}

# Replace the one line containing <marker> in <file> with the contents of
# <fragment>. sed's r queues the fragment after the marker line; d then drops the
# marker line, leaving the fragment in its place. Byte-safe, so the file's BOM
# and the rest of its content are untouched.
inject() {   # <file> <marker> <fragment>
	local file=$1 marker=$2 frag=$3
	sed -e "/$marker/r $frag" -e "/$marker/d" "$file" > "$file.tmp"
	mv "$file.tmp" "$file"
}

# Drop any leftover injection markers. The AGOT build's injects already consumed
# them; the vanilla build never injects, so its shared files still carry them.
strip_markers() {   # <destdir>
	find "$1" -type f -name '*.txt' -exec sed -i '/# @AGOT:/d' {} +
}

# The game wants a UTF-8 BOM on every .txt/.gui/.yml and none on descriptor.mod.
# The base files and generated files already comply; this normalizes anything the
# build copied in (the agot/files/ overlay) and the AGOT descriptor.
ensure_bom() {   # <destdir>
	local f
	find "$1" -type f \( -name '*.txt' -o -name '*.gui' -o -name '*.yml' \) | while read -r f; do
		if [ "$(head -c3 "$f" | od -An -tx1 | tr -d ' ')" != efbbbf ]; then
			printf '\xEF\xBB\xBF' | cat - "$f" > "$f.bom"; mv "$f.bom" "$f"
		fi
	done
	local desc="$1/descriptor.mod"
	if [ -f "$desc" ] && [ "$(head -c3 "$desc" | od -An -tx1 | tr -d ' ')" = efbbbf ]; then
		tail -c +4 "$desc" > "$desc.nb"; mv "$desc.nb" "$desc"
	fi
}

check_braces() {   # <destdir>
	local f o c bad=0
	while read -r f; do
		o=$(tr -cd '{' < "$f" | wc -c); c=$(tr -cd '}' < "$f" | wc -c)
		if [ "$o" != "$c" ]; then echo "  UNBALANCED: $f ({=$o }=$c)"; bad=1; fi
	done < <(find "$1" -type f \( -name '*.txt' -o -name '*.gui' \))
	[ "$bad" = 0 ] && echo "  braces balanced"
}

echo "== vanilla =="
copy_base "$DIST/vanilla"
cp "$ROOT/descriptor.mod" "$DIST/vanilla/descriptor.mod"
TARGET=vanilla OUTDIR="$DIST/vanilla" bash "$ROOT/tools/gen_panel.sh" >/dev/null
strip_markers "$DIST/vanilla"
ensure_bom "$DIST/vanilla"
check_braces "$DIST/vanilla"

echo "== agot =="
copy_base "$DIST/agot"
TARGET=agot OUTDIR="$DIST/agot" bash "$ROOT/tools/gen_panel.sh" >/dev/null
inject "$DIST/agot/common/scripted_effects/leo_mvd_rules.txt"                        "@AGOT:dispatch@"     "$ROOT/agot/fragments/dispatch.txt"
inject "$DIST/agot/common/scripted_triggers/leo_mvd_triggers.txt"                    "@AGOT:match@"        "$ROOT/agot/fragments/match.txt"
inject "$DIST/agot/common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt" "@AGOT:custloc_icon@" "$ROOT/agot/fragments/custloc_icon.txt"
inject "$DIST/agot/common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt" "@AGOT:custloc_text@" "$ROOT/agot/fragments/custloc_text.txt"
cp -r "$ROOT/agot/files/." "$DIST/agot/"
cp "$ROOT/agot/descriptor.mod" "$DIST/agot/descriptor.mod"
strip_markers "$DIST/agot"
ensure_bom "$DIST/agot"
check_braces "$DIST/agot"

echo "done: dist/vanilla and dist/agot"
