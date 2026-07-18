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
# The two mods build in parallel. Usage:
#   bash tools/build.sh          quiet
#   bash tools/build.sh -v       narrate every phase
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"

VERBOSE=""
for a in "$@"; do case $a in -v|--verbose) VERBOSE=1 ;; esac; done
export VERBOSE   # gen_panel honors the same flag
vlog() { [ -n "$VERBOSE" ] && echo ">> build: $*" >&2 || true; }

# What ships. Everything else in the repo (tools, docs, agot, assets, dot-dirs)
# stays out. The thumbnail is per-target - each mod gets its own from assets/ -
# so there is no shared root thumbnail.
GAME_DIRS="common gui events localization"
THUMB_VANILLA="assets/images/outputs/thumbnail_vanilla.png"
THUMB_AGOT="assets/images/outputs/thumbnail_agot.png"
# The three base files carrying # @AGOT:...@ markers.
MARKER_FILES="common/scripted_effects/leo_mvd_rules.txt common/scripted_triggers/leo_mvd_triggers.txt common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt"
# AGOT overlay files written by hand (so without a BOM); every other shipped file
# already has one (base files, and gen_panel writes its output with a BOM).
AGOT_BOMLESS="common/scripted_triggers/leo_mvd_agot_triggers.txt gui/leo_mvd_agot_texticons.gui common/scripted_effects/leo_mvd_agot_presets.txt common/scripted_guis/leo_mvd_agot_sguis.txt common/script_values/zz_leo_mvd_agot_values.txt"
# Files the AGOT build changes or adds that have braces worth re-checking.
AGOT_CHECK="$MARKER_FILES common/scripted_triggers/leo_mvd_agot_triggers.txt gui/leo_mvd_agot_texticons.gui common/scripted_effects/leo_mvd_agot_presets.txt common/scripted_guis/leo_mvd_agot_sguis.txt"

copy_base() {   # <destdir>
	local out=$1 d
	rm -rf "$out"; mkdir -p "$out"
	for d in $GAME_DIRS; do cp -r "$ROOT/$d" "$out/"; done
}

# Replace the one line containing <marker> in <file> with <fragment>'s contents.
# Byte-safe, so the file's BOM and everything else is untouched.
inject() {   # <file> <marker> <fragment>
	sed -e "/$2/r $3" -e "/$2/d" "$1" > "$1.tmp"; mv "$1.tmp" "$1"
}

has_bom()   { [ "$(head -c3 "$1" | od -An -tx1 | tr -d ' ')" = efbbbf ]; }
add_bom()   { has_bom "$1" || { printf '\xEF\xBB\xBF' | cat - "$1" > "$1.b"; mv "$1.b" "$1"; }; }
strip_bom() { has_bom "$1" && { tail -c +4 "$1" > "$1.n"; mv "$1.n" "$1"; } || true; }
check_brace() {   # <file>
	local o c; o=$(tr -cd '{' < "$1" | wc -c); c=$(tr -cd '}' < "$1" | wc -c)
	[ "$o" = "$c" ] || { echo "UNBALANCED: $1 ({=$o }=$c)" >&2; return 1; }
}

build_vanilla() {
	local out="$DIST/vanilla" f
	vlog "vanilla: copy base"; copy_base "$out"
	cp "$ROOT/descriptor.mod" "$out/descriptor.mod"; strip_bom "$out/descriptor.mod"
	cp "$ROOT/$THUMB_VANILLA" "$out/thumbnail.png"
	vlog "vanilla: generate panel"; TARGET=vanilla OUTDIR="$out" bash "$ROOT/tools/gen_panel.sh" >/dev/null
	vlog "vanilla: strip markers"; for f in $MARKER_FILES; do sed -i '/# @AGOT:/d' "$out/$f"; done
	vlog "vanilla: done"
}

build_agot() {
	local out="$DIST/agot" f
	vlog "agot: copy base"; copy_base "$out"
	cp "$ROOT/$THUMB_AGOT" "$out/thumbnail.png"
	vlog "agot: generate panel"; TARGET=agot OUTDIR="$out" bash "$ROOT/tools/gen_panel.sh" >/dev/null
	vlog "agot: inject fragments"
	inject "$out/common/scripted_effects/leo_mvd_rules.txt"                         "@AGOT:dispatch@"     "$ROOT/agot/fragments/dispatch.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                     "@AGOT:match@"        "$ROOT/agot/fragments/match.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                     "@AGOT:conditions@"   "$ROOT/agot/fragments/conditions.txt"
	inject "$out/common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt" "@AGOT:custloc_icon@" "$ROOT/agot/fragments/custloc_icon.txt"
	inject "$out/common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt" "@AGOT:custloc_text@" "$ROOT/agot/fragments/custloc_text.txt"
	vlog "agot: copy overlay + descriptor"
	cp -r "$ROOT/agot/files/." "$out/"
	cp "$ROOT/agot/descriptor.mod" "$out/descriptor.mod"; strip_bom "$out/descriptor.mod"
	vlog "agot: BOM + brace-check touched files"
	for f in $AGOT_BOMLESS; do add_bom "$out/$f"; done
	# Every AGOT overlay loc file (english source plus the translated ones).
	for f in "$out"/localization/*/leo_mvd_agot_l_*.yml; do add_bom "$f"; done
	for f in $AGOT_CHECK;   do check_brace "$out/$f"; done
	vlog "agot: done"
}

echo "building dist/vanilla and dist/agot (parallel)..."
build_vanilla & vpid=$!
build_agot    & apid=$!
wait "$vpid"
wait "$apid"
echo "done: dist/vanilla and dist/agot"
