#!/bin/bash
#
# Builds the three shippable mods from the shared source in this repo:
#
#   dist/vanilla/  the base mod, no total-conversion content
#   dist/agot/     the same plus AGOT's settle_wilderness directive and the
#                  Westeros conditions, referencing AGOT's own assets
#   dist/tfe/      the same plus what The Fallen Eagle needs: its own way into
#                  the panel, since TFE's realm window has no directives button
#
# Each dist holds game files only - no tools, docs, or dev files - so it can be
# pointed at by the launcher and uploaded to the Workshop as-is. dist/ is
# gitignored.
#
# How a total-conversion build differs from the base, all applied here rather
# than gated at runtime (there is no runtime detection of either mod):
#   - the panel is regenerated in that mode (AGOT: settle_wilderness in, nomad
#     out; TFE: its own opener and administration types)
#   - small fragments are injected at the base files' # @AGOT:...@ and
#     # @TFE:...@ markers
#   - that target's own files under agot/files/ or tfe/files/ are copied in
#   - its descriptor replaces the base one
#
# A marker belongs to exactly one target: every build strips the markers that
# are not its own, so a marker only ever survives as the content it names.
#
# The three mods build in parallel. Usage:
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
THUMB_TFE="assets/images/outputs/thumbnail_tfe.png"
# The base files carrying # @<TARGET>:...@ markers, whichever target owns them.
MARKER_FILES="common/scripted_effects/leo_mvd_rules.txt common/scripted_triggers/leo_mvd_triggers.txt common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt common/scripted_effects/leo_mvd_effects.txt common/customizable_localization/leo_mvd_admin_type_loc.txt"
# Every marker prefix in use. A build injects its own and strips all of them at
# the end, so nothing target-specific can leak into another mod.
MARKER_TAGS="AGOT TFE"
# AGOT overlay files written by hand (so without a BOM); every other shipped file
# already has one (base files, and gen_panel writes its output with a BOM).
AGOT_BOMLESS="common/scripted_triggers/leo_mvd_agot_triggers.txt gui/leo_mvd_agot_texticons.gui common/scripted_effects/leo_mvd_agot_presets.txt common/scripted_guis/leo_mvd_agot_sguis.txt common/script_values/zz_leo_mvd_agot_values.txt"
# Files the AGOT build changes or adds that have braces worth re-checking.
AGOT_CHECK="$MARKER_FILES common/scripted_triggers/leo_mvd_agot_triggers.txt gui/leo_mvd_agot_texticons.gui common/scripted_effects/leo_mvd_agot_presets.txt common/scripted_guis/leo_mvd_agot_sguis.txt"
# The same two lists for the TFE build: files written by hand (so without a BOM)
# and files worth re-checking for balanced braces.
TFE_BOMLESS="gui/leo_mvd_tfe_opener.gui gui/scripted_widgets/leo_mvd_tfe_widgets.txt common/scripted_triggers/leo_mvd_tfe_triggers.txt"
TFE_CHECK="$MARKER_FILES gui/leo_mvd_tfe_opener.gui common/scripted_triggers/leo_mvd_tfe_triggers.txt"

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

# Drop every marker line still standing. Run last in each build: injection
# already removed the lines that target replaced, so whatever is left belongs to
# another target and must not ship.
strip_markers() {   # <destdir>
	local out=$1 f tag
	for f in $MARKER_FILES; do
		for tag in $MARKER_TAGS; do sed -i "/# @$tag:/d" "$out/$f"; done
	done
}

# Each mod gets its own thumbnail. A target whose art does not exist yet falls
# back to the base one rather than failing the build - the descriptor names a
# thumbnail.png that has to be there.
copy_thumb() {   # <destdir> <thumbnail path>
	local out=$1 thumb=$2
	if [ -f "$ROOT/$thumb" ]; then cp "$ROOT/$thumb" "$out/thumbnail.png"
	else
		echo "note: $thumb missing, using the base thumbnail" >&2
		cp "$ROOT/$THUMB_VANILLA" "$out/thumbnail.png"
	fi
}

has_bom()   { [ "$(head -c3 "$1" | od -An -tx1 | tr -d ' ')" = efbbbf ]; }
add_bom()   { has_bom "$1" || { printf '\xEF\xBB\xBF' | cat - "$1" > "$1.b"; mv "$1.b" "$1"; }; }
strip_bom() { has_bom "$1" && { tail -c +4 "$1" > "$1.n"; mv "$1.n" "$1"; } || true; }
check_brace() {   # <file>
	local o c; o=$(tr -cd '{' < "$1" | wc -c); c=$(tr -cd '}' < "$1" | wc -c)
	[ "$o" = "$c" ] || { echo "UNBALANCED: $1 ({=$o }=$c)" >&2; return 1; }
}

build_vanilla() {
	local out="$DIST/vanilla"
	vlog "vanilla: copy base"; copy_base "$out"
	cp "$ROOT/descriptor.mod" "$out/descriptor.mod"; strip_bom "$out/descriptor.mod"
	copy_thumb "$out" "$THUMB_VANILLA"
	vlog "vanilla: generate panel"; TARGET=vanilla OUTDIR="$out" bash "$ROOT/tools/gen_panel.sh" >/dev/null
	vlog "vanilla: strip markers"; strip_markers "$out"
	vlog "vanilla: done"
}

build_agot() {
	local out="$DIST/agot" f
	vlog "agot: copy base"; copy_base "$out"
	copy_thumb "$out" "$THUMB_AGOT"
	vlog "agot: generate panel"; TARGET=agot OUTDIR="$out" bash "$ROOT/tools/gen_panel.sh" >/dev/null
	vlog "agot: inject fragments"
	inject "$out/common/scripted_effects/leo_mvd_rules.txt"                         "@AGOT:dispatch@"     "$ROOT/agot/fragments/dispatch.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                     "@AGOT:family_rtp@"  "$ROOT/agot/fragments/family_rtp.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                     "@AGOT:match@"        "$ROOT/agot/fragments/match.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                     "@AGOT:conditions@"   "$ROOT/agot/fragments/conditions.txt"
	inject "$out/common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt" "@AGOT:custloc_icon@" "$ROOT/agot/fragments/custloc_icon.txt"
	inject "$out/common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt" "@AGOT:custloc_text@" "$ROOT/agot/fragments/custloc_text.txt"
	vlog "agot: copy overlay + descriptor"
	cp -r "$ROOT/agot/files/." "$out/"
	cp "$ROOT/agot/descriptor.mod" "$out/descriptor.mod"; strip_bom "$out/descriptor.mod"
	vlog "agot: strip other targets' markers"; strip_markers "$out"
	vlog "agot: BOM + brace-check touched files"
	for f in $AGOT_BOMLESS; do add_bom "$out/$f"; done
	# Every AGOT overlay loc file (english source plus the translated ones).
	for f in "$out"/localization/*/leo_mvd_agot_l_*.yml; do add_bom "$f"; done
	for f in $AGOT_CHECK;   do check_brace "$out/$f"; done
	vlog "agot: done"
}

build_tfe() {
	local out="$DIST/tfe" f
	vlog "tfe: copy base"; copy_base "$out"
	copy_thumb "$out" "$THUMB_TFE"
	vlog "tfe: generate panel"; TARGET=tfe OUTDIR="$out" bash "$ROOT/tools/gen_panel.sh" >/dev/null
	vlog "tfe: inject fragments"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                 "@TFE:family_rtp@"     "$ROOT/tfe/fragments/family_rtp.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                 "@TFE:family_any@"     "$ROOT/tfe/fragments/family_any.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                 "@TFE:theme_civilian@" "$ROOT/tfe/fragments/theme_civilian.txt"
	inject "$out/common/scripted_triggers/leo_mvd_triggers.txt"                 "@TFE:theme_extra@"    "$ROOT/tfe/fragments/theme_extra.txt"
	inject "$out/common/scripted_effects/leo_mvd_effects.txt"                   "@TFE:family_value@"   "$ROOT/tfe/fragments/family_value.txt"
	inject "$out/common/scripted_effects/leo_mvd_rules.txt"                     "@TFE:preset_8@"       "$ROOT/tfe/fragments/preset_8.txt"
	inject "$out/common/customizable_localization/leo_mvd_admin_type_loc.txt"   "@TFE:term@"           "$ROOT/tfe/fragments/term.txt"
	inject "$out/common/customizable_localization/leo_mvd_admin_type_loc.txt"   "@TFE:preset_8_tt@"    "$ROOT/tfe/fragments/preset_8_tt.txt"
	vlog "tfe: copy overlay + descriptor"
	[ -d "$ROOT/tfe/files" ] && cp -r "$ROOT/tfe/files/." "$out/"
	cp "$ROOT/tfe/descriptor.mod" "$out/descriptor.mod"; strip_bom "$out/descriptor.mod"
	vlog "tfe: strip other targets' markers"; strip_markers "$out"
	vlog "tfe: BOM + brace-check touched files"
	for f in $TFE_BOMLESS; do [ -f "$out/$f" ] || continue; add_bom "$out/$f"; done
	for f in "$out"/localization/*/leo_mvd_tfe_l_*.yml; do [ -f "$f" ] || continue; add_bom "$f"; done
	for f in $TFE_CHECK;   do [ -f "$out/$f" ] || continue; check_brace "$out/$f"; done
	vlog "tfe: done"
}

echo "building dist/vanilla, dist/agot and dist/tfe (parallel)..."
build_vanilla & vpid=$!
build_agot    & apid=$!
build_tfe     & tpid=$!
wait "$vpid"
wait "$apid"
wait "$tpid"
echo "done: dist/vanilla, dist/agot and dist/tfe"
