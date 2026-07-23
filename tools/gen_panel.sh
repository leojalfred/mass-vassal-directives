#!/bin/bash
#
# Generates the repetitive parts of the configuration panel.
#
# The rule editor is the same handful of widgets repeated for every node of
# every priority, differing only in the variable name they bind to. There is no
# way to factor that out in GUI - blockoverride cannot parameterize the variable
# name inside a binding - so generating it keeps the repetition consistent and
# makes changing the pattern a one-line edit here.
#
# Emits three files, from one description of the rules, so that the panel, the
# scripted GUIs it calls, and the localization it names cannot drift apart:
#
#   gui/leo_mvd_panel.gui                            the panel
#   common/scripted_guis/leo_mvd_edit.txt            focus/set scripted GUIs
#   localization/english/leo_mvd_ui_l_english.yml    editor labels
#
# Hand edits to those three files will be overwritten. Tune the layout here
# instead - the skeleton and the margins live in emit_panel below.
#
# Usage: bash tools/gen_panel.sh        (from the mod root)

set -euo pipefail
cd "$(dirname "$0")/.."

# Build to temporary files and move them into place at the end, rather than
# writing the real ones as we go. A run takes the better part of a minute, and
# an interrupted one that had been appending directly would leave a half-written
# panel behind - or, if another run had started meanwhile, two of them
# interleaved into the same file.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

### How much to generate.
PRIORITIES=6          # main rule priorities to emit (max 6; see leo_mvd_rules.txt)
QPRIORITIES=3         # nomad rule priorities to emit (max 3)

### Build target and output.
#
# vanilla (default) or agot. The AGOT panel adds the settle_wilderness directive
# and drops the nomad section, which A Game of Thrones never populates;
# everything else is identical. tools/build.sh sets these; a bare run regenerates
# the vanilla files in place.
TARGET="${TARGET:-vanilla}"
OUTDIR="${OUTDIR:-.}"
# -v / --verbose (or VERBOSE=1) narrates each phase to stderr.
VERBOSE="${VERBOSE:-}"
for _a in "$@"; do case $_a in -v|--verbose) VERBOSE=1 ;; esac; done
vlog() { [ -n "$VERBOSE" ] && echo ">> gen_panel[$TARGET]: $*" >&2 || true; }

### Look.
DD_INSET=3            # px an open dropdown list is narrower than its button,
                      # each side - see emit_dd_start for why it needs to be

### The rules, described once.

# Directive codes -> the name they go by.
#
# Vanilla has a loc key per directive that pairs the name with its icon, but
# that icon is 35x35 at offset { 0 11 } - meant for a row of its own in the
# Subjects tab. In a sentence it forces the line apart and strands the name on
# the next one, and it overflows a 30px dropdown row. So these name the
# directive themselves and reach for the inline-sized icons in
# gui/leo_mvd_texticons.gui instead. Wording follows vanilla's.
DIRS="1 2 3 4 5 6 7 8 9"
# settle_wilderness (AGOT's one extra directive) rides the main waterfall, and
# only in the AGOT build.
if [ "$TARGET" = agot ]; then DIRS="$DIRS 14"; fi
# Only nomads can be given these four, and they can be given nothing else.
NOMAD_DIRS="10 11 12 13"
# Every directive there is. A setter and a label are needed for each, whichever
# waterfall offers it.
ALL_DIRS="$DIRS $NOMAD_DIRS"
dir_icon() { case $1 in
	1) echo convert_faith ;;                2) echo convert_culture ;;
	3) echo improve_development ;;          4) echo train_commanders ;;
	5) echo build_maa ;;                    6) echo improve_cultural_acceptance ;;
	7) echo building_focus_fortification ;; 8) echo building_focus_military ;;
	9) echo building_focus_economy ;;
	14) echo settle_wilderness ;;
	10) echo manage_fertility ;;             11) echo explore_cultures ;;
	12) echo raid_innovation_intent ;;      13) echo raid_herd_intent ;;
esac; }
dir_name() { case $1 in
	1) echo "Convert [faith|E]" ;;
	2) echo "Promote [culture|E]" ;;
	3) echo "Improve [development|E]" ;;
	4) echo "Boost [men_at_arms|E]" ;;
	5) echo "Recruit [men_at_arms|E]" ;;
	6) echo "Improve [cultural_acceptance|E]" ;;
	7) echo "Construct [fortification_buildings|E]" ;;
	8) echo "Construct [military_buildings|E]" ;;
	9) echo "Construct [economic_buildings|E]" ;;
	14) echo "Settle [wilderness|E]" ;;
	10) echo "Increase [county_fertility|E]" ;;
	11) echo "Explore [cultures|E]" ;;
	12) echo "Set [raid_intent|E] to [innovations|E]" ;;
	13) echo "Set [raid_intent|E] to [herd|E]" ;;
esac; }

# Condition codes. Must match leo_mvd_cond_holds_trigger.
#
# This list is also the order the panel offers them in, which is why 19, 20 and
# 21 sit beside the questions they refine rather than at the end: Same House
# reads next to Same Dynasty, Governor Theme next to Administrative Government,
# Average Development next to Capital Development. The codes themselves are
# append-only - they are stored in player variables that persist in saves, so
# renumbering would silently rewrite existing rule sets.
CONDS="1 2 3 4 5 19 6 20 7 8 9 10 21 11 12 13 14"
# Westeros conditions (15-18: Ironborn and three faith blocs) are boolean and
# AGOT-only; the AGOT build injects their evaluation branches.
if [ "$TARGET" = agot ]; then CONDS="$CONDS 15 16 17 18"; fi

# Preset dropdown order: None, the four built-ins, Govern by Theme, then (AGOT
# build) two Westeros presets, then Custom. Custom stays index 5 - the engine
# keys on it - so everything added since takes 6 and up and slots in ahead of it.
PRESET_RANGE="0 1 2 3 4 8 5"
if [ "$TARGET" = agot ]; then PRESET_RANGE="0 1 2 3 4 8 6 7 5"; fi
# 6 (Administrative Government) and 20 (Governor Theme) are left out for nomads:
# no nomad is administrative, so both could only ever answer no.
NOMAD_CONDS="1 2 3 4 5 19 7 8 9 10 21 11 12 13 14"
cond_name() { case $1 in
	1) echo "[faith|E] is Yours" ;;
	2) echo "[culture|E] is Yours" ;;
	3) echo "Holds [counties|E] of Another [faith|E]" ;;
	4) echo "Holds [counties|E] of Another [culture|E]" ;;
	5) echo "Same [dynasty|E] as You" ;;
	6) echo "[administrative|E] [government|E]" ;;
	7) echo "Is a [powerful_vassal|E]" ;;
	8) echo "Is on Your [council|E]" ;;
	9) echo "Military Strength is at Least" ;;
	10) echo "[title|E] Tier is at Least" ;;
	11) echo "Capital [development|E] is at Least" ;;
	12) echo "[opinion|E] of You is at Least" ;;
	13) echo "[counties|E] Held is at Least" ;;
	14) echo "[cultural_acceptance|E] with You is at Least" ;;
	19) echo "Same [house|E] as You" ;;
	20) echo "[governor|E] Theme is" ;;
	21) echo "Average [development|E] is at Least" ;;
	15) echo "Is Ironborn" ;;
	16) echo "Follows the Faith of the Seven" ;;
	17) echo "Follows the Old Gods" ;;
	18) echo "Follows R'hllor" ;;
esac; }

# Thresholds, per numeric condition. All non-negative: a label key is built by
# pasting the value onto a prefix at runtime, and a minus sign in a key is not
# worth the risk.
NUMERIC_CONDS="9 10 11 12 13 14 20 21"
# Whether a condition takes a threshold (is measured) rather than being a plain
# yes/no. Not the same as "code >= 9": the AGOT conditions (15-18) are numbered
# above the numeric ones but are boolean.
#
# 20 (Governor Theme) rides the threshold machinery without being measured: it
# needed one picker out of a fixed set, which is what a threshold already is.
# Its trigger reads the value as equality rather than a floor. Being "numeric"
# also keeps it selectable underneath itself, which is what lets one priority
# ask about two themes in turn.
is_numeric() { case " $NUMERIC_CONDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
cond_thresh() { case $1 in
	9)  if [ "$TARGET" = agot ]; then echo "1000 2000 4000 10000"; else echo "500 1000 2000 5000"; fi ;;
	10) echo "2 3 4 5" ;;
	11) echo "10 20 40 60 80" ;;
	12) echo "0 25 50 75" ;;
	13) echo "1 2 3 5 10" ;;
	14) echo "10 25 50 75 90" ;;
	20) echo "1 2 3 4 5 6" ;;
	# Lower than Capital Development's ladder: the capital is usually the best
	# county a vassal holds, so an average over the whole domain runs behind it.
	21) echo "5 10 20 40 60" ;;
esac; }

# Picking a condition also sets this, so a threshold is never left at 0 - which
# would name a label key that does not exist.
cond_default_thresh() { case $1 in
	9) if [ "$TARGET" = agot ]; then echo 2000; else echo 1000; fi ;; 10) echo 3 ;; 11) echo 40 ;; 12) echo 50 ;; 13) echo 3 ;; 14) echo 50 ;; 20) echo 3 ;; 21) echo 20 ;;
	*) echo 0 ;;
esac; }

# A threshold's label depends on the condition asking for it.
thresh_label() { local c=$1 t=$2
	case $c in
	10) case $t in 2) echo "[county|E]" ;; 3) echo "[duchy|E]" ;; 4) echo "[kingdom|E]" ;; 5) echo "[empire|E]" ;; esac ;;
	14) echo "$t%" ;;
	13) case $t in 1) echo "1 [county|E]" ;; *) echo "$t [counties|E]" ;; esac ;;
	# The themes have no game concept, but they do have the game's own names,
	# icon and all. Referencing those keys keeps the labels identical to the
	# contract screen and translates them everywhere for free. Their order is
	# the order the contract itself lists them in.
	20) case $t in
		1) echo "\$admin_theme_balanced\$" ;;
		2) echo "\$admin_theme_civilian\$" ;;
		3) echo "\$admin_theme_military\$" ;;
		4) echo "\$admin_theme_frontier\$" ;;
		5) echo "\$admin_theme_imperial\$" ;;
		6) echo "\$admin_theme_naval\$" ;;
	esac ;;
	*)  echo "$t" ;;
	esac
}

all_thresh_values() { for c in $NUMERIC_CONDS; do cond_thresh "$c"; done | tr ' ' '\n' | sort -un; }

# A priority's node tree: n1 root, n2/n3 its branches, n4..n7 the grandchildren.
# n4..n7 are leaves - no condition - which is the depth cap standing in for the
# recursion the script language does not allow.
node_children() { case $1 in 1) echo "2 3" ;; 2) echo "4 5" ;; 3) echo "6 7" ;; esac; }

### Emit helpers.

# Indent by parameter expansion, not a subshell per line: six priorities is
# around 12000 lines, and forking twice for each of them takes minutes.
TABS=$'\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t'
I=""
ind() { I="${TABS:0:$1}"; }
p() { echo "${I}$1"; }

# A GUI bool: does variable <1> equal <2>?
veq() { echo "EqualTo_CFixedPoint( GetPlayer.MakeScope.Var('$1').GetValue, '(CFixedPoint)$2' )"; }
# A GUI bool: does variable <1> equal variable <2>? (both read as values)
vveq() { echo "EqualTo_CFixedPoint( GetPlayer.MakeScope.Var('$1').GetValue, GetPlayer.MakeScope.Var('$2').GetValue )"; }
# A GUI bool: does the datamodel row's own code (looked up by its flag in the
# leo_mvd_x_ table) equal node variable <1>? Both are numbers - the row's flag is
# a string that could not be compared against a number any other way.
xeq() { echo "EqualTo_CFixedPoint( GetPlayer.MakeScope.Var( Concatenate( 'leo_mvd_x_', Scope.GetFlagName ) ).GetValue, GetPlayer.MakeScope.Var('$1').GetValue )"; }
# A GUI bool: is variable <1> at least <2>?
vge() { echo "GreaterThanOrEqualTo_CFixedPoint( GetPlayer.MakeScope.Var('$1').GetValue, '(CFixedPoint)$2' )"; }
# Variable <1> as an int, for pasting into a string.
vint() { echo "IntToString(FixedPointToInt(GetPlayer.MakeScope.Var('$1').GetValue))"; }
# The loc key <prefix><value of variable>, resolved. This is what lets a button
# show its current selection without a 14-way branch: vanilla builds keys the
# same way (window_ledger.gui:417, shared/coa_designer.gui:1659).
vkey() { echo "Localize(Concatenate('$1', $(vint "$2")))"; }
# Run scripted GUI <1> with the player as root.
sgui() { echo "[GetScriptedGui('$1').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"; }
# Whether scripted GUI <1> is currently allowed, for an `enabled` binding.
sgui_valid() { echo "[GetScriptedGui('$1').IsValid( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"; }

# The list a dropdown's rows come from: <2> while dropdown <1> is open, and
# leo_mvd_x while it is shut.
#
# leo_mvd_x is never created. A datamodel over a list that does not exist has no
# items, so a closed dropdown holds no row widgets rather than hidden ones -
# which is the difference between a panel that costs its whole option count on
# first open and one that does not. <2> is an expression, not a name, so a
# threshold picker can name its list from the condition beside it.
dd_list() { echo "Select_CString( GetVariableSystem.HasValue( 'leo_mvd_dd', '$1' ), $2, 'leo_mvd_x' )"; }

# A GUI bool: is DLC feature <1> active? Vanilla gates its own admin/nomad UI
# this way (frontend_bookmarks.gui, shared/mapmodes.gui). References to the
# gated governments stay safe without the DLC - they simply never occur - so
# this only spares a DLC-less player options that could never do anything.
vdlc() { echo "HasDlcFeature( '$1' )"; }
# Combine visibility sub-expressions with And(), dropping empties. Returns one
# expression, or nothing when every input is empty - so an unneeded gate leaves
# the original binding untouched.
vis_and() { local out=; for e in "$@"; do [ -z "$e" ] && continue
	if [ -z "$out" ]; then out=$e; else out="And( $out, $e )"; fi; done; echo "$out"; }
# The DLC gate a directive/condition needs, if any, as a has_dlc_feature name.
# The three administrative directives (improve development, train commanders,
# build men-at-arms) and the Administrative Government and Governor Theme
# conditions need Roads to Power - 'roads_to_power', the expansion flag vanilla's
# own vassal_follows_directive trigger gates administrative on, not the finer
# 'admin_gov', which does not track DLC ownership. The nomad directives need
# Khans of the Steppe, but their whole section is gated as a block, so they need
# nothing here.
#
# Empty when the option needs no DLC. The option list keeps every entry in its
# declared order and wraps just the gated ones in their own has_dlc_feature
# check, so a DLC's options sit where they belong rather than being appended
# after everything else.
dir_dlc_feature()  { case $1 in 3|4|5) echo roads_to_power ;; esac; }
cond_dlc_feature() { case $1 in 6|20)  echo roads_to_power ;; esac; }
# A preset is hidden outright when the DLC it is built around is missing, rather
# than falling back the way 1/3/4 do. Govern by Theme sorts governors by their
# theme, and without Roads to Power there are neither, so every rule it could
# write would collapse to "everyone builds economy" - which is exactly what Grow
# the Economy already offers. Two presets that do the same thing is worse than
# one that is absent.
preset_dlc_vis() { case $1 in 8) vdlc roads_to_power ;; esac; }

# Explanatory tooltip for a condition option, if it needs one. Three do.
# Military Strength's threshold is a duchy-tier baseline scaled by the vassal's
# rank (leo_mvd_effective_threshold), which the plain label cannot convey.
# Governor Theme picks a value rather than a floor, the one place the panel
# departs from "is at least", so it says so. Average Development's label cannot
# say which counties are averaged (the personally held ones).
cond_tt() { case $1 in 9) echo "leo_mvd_ui_cond_9_tt" ;; 20) echo "leo_mvd_ui_cond_20_tt" ;; 21) echo "leo_mvd_ui_cond_21_tt" ;; esac; }

# One shared threshold picker per node serves every numeric condition, instead
# of one hidden picker per condition (which multiplied the panel's widget count).
# Its label is built at runtime from the node's chosen condition and value,
# leo_mvd_ui_thresh_c<cond>_<thresh>, and it is shown only while a numeric
# condition is selected. <1> = the node's cond variable, <2> = its thresh var.
# The picker's own label, showing what is currently chosen. Same key shape the
# rows build - leo_mvd_ui_c<cond>_thresh_<value> - reached from the two variables
# rather than from an item's flag.
thresh_label_dyn() { echo "Localize(Concatenate(Concatenate('leo_mvd_ui_c', Concatenate($(vint "$1"), '_thresh_')), $(vint "$2")))"; }
# A GUI bool: is a condition that takes a threshold selected in variable <1>?
numeric_cond_sel() { local var=$1 expr=; for c in $NUMERIC_CONDS; do local t; t="$(veq "$var" "$c")"
	if [ -z "$expr" ]; then expr=$t; else expr="Or( $expr, $t )"; fi; done; echo "$expr"; }

# Kind 0 means "fall through to the next priority" - but on the last priority
# there is no next one, and it means "leave this vassal without a directive".
# Same behavior either way, so only the label changes.
kind0_key() { echo "SelectLocalization( $(vge "$COUNT_VAR" $(($1 + 1))), 'leo_mvd_ui_kind_0', 'leo_mvd_ui_kind_0_last' )"; }
# The kind-0 tooltip tracks its label: the continue text when a later priority
# exists, the leave text when this is the last one.
kind0_tt_key() { echo "SelectLocalization( $(vge "$COUNT_VAR" $(($1 + 1))), 'leo_mvd_ui_kind_0_tt', 'leo_mvd_ui_kind_0_last_tt' )"; }

### Dropdowns.
#
# The rules are shown and editable whichever preset is selected, so a preset can
# be read rather than taken on trust, and used as a starting point rather than a
# take-it-or-leave-it. Nothing here gates on which preset is loaded: changing
# anything makes the rules the player's own, because leo_mvd_edit_effect
# switches the selection to Custom - so a built-in is never edited in place into
# something that is no longer the preset it claims to be.
#
# These open in flow, pushing the rows below them down, rather than floating
# over them. That is forced, not preferred.
#
# Draw order is tree order and there is no z-index for a non-window widget, so a
# list living inside its row is painted over by every row after it. Floating
# would mean hoisting the open list into a later sibling and aligning it to a
# button whose screen position no datafunction returns. Vanilla hits the same
# wall: game_rules.gui is this same panel - a scrollbox of rows each needing a
# selector - and puts its dropdowns in the header outside the scrollbox, while
# the rows inside use an arrow cycler.
#
# The old note here also said rule nodes could not be datamodel items because
# script variable lists hold scopes. That part was wrong: flags are legal
# entries and carry a readable name, which is what the option lists now rely on.
# It does not rescue floating, though, because the blocker there is alignment,
# not identity.
# Escaping the scrollarea's scissor (preload/defaults.gui:252) is possible via
# viewportwidget, but un-clips the whole viewport, so scrolled-out rows would
# bleed over the panel's own frame.
#
# The parts are vanilla's own dropdown parts, so it still reads as one.
#
# Which dropdown is open lives in a single GUI variable, so opening one closes
# any other for free. GUI variables are client-local and never touch script.

# Opens a dropdown: a group holding the button and its list, then the button,
# then the list. Caller emits the rows, then calls emit_dd_end.
#
# The group exists to glue the two together. They are siblings, so whatever
# spacing their parent uses would otherwise open a gap between the button and
# the list hanging off it; the group's own spacing = 0 overrides that.
#
# <1> depth  <2> id  <3> label expression  <4> tooltip (may be empty)
# <5> enabled expression (may be empty - always enabled)
emit_dd_start() { local depth=$1 id=$2 label=$3
	ind "$depth"
	p "vbox = {"
	ind $((depth+1))
	p "layoutpolicy_horizontal = expanding"
	p "spacing = 0"
	p ""
	p "leo_mvd_button_drop = {"
	ind $((depth+2))
	p "layoutpolicy_horizontal = expanding"
	# Opening a data-driven dropdown makes sure its list exists first. The panel
	# is opened by a vanilla button, so a session can reach this point with no
	# script of ours having run - and then the list would be empty. Runs before
	# the variable that opens the list, and the two onclicks run in order.
	[ -n "${4:-}" ] && p "onclick = \"$(sgui leo_mvd_ensure_options)\""
	p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', Select_CString( GetVariableSystem.HasValue( 'leo_mvd_dd', '$id' ), 'none', '$id' ) )]\""
	p "text = \"[$label]\""
	ind $((depth+1)); p "}"
	p ""
	# A wrapper whose only job is to be narrower than the button.
	#
	# The button and the list are the same width on paper, but
	# leo_mvd_button_drop is Corneredtiled with spriteborder = { 75 11 }, so its
	# texture stops short of its own box and it reads as narrower. The list has
	# to actually shrink to match what the eye sees - and margin on the list
	# itself will not do that, because an expanding widget is still stretched to
	# its parent's width and the margin only insets what is inside it, leaving
	# the background full width. So the inset goes here, on a parent, and the
	# list expands into what is left. DD_INSET is the number to tune; horizontal
	# only, since vertical would gap the list off the button above it.
	ind $((depth+1))
	p "vbox = {"
	ind $((depth+2))
	p "layoutpolicy_horizontal = expanding"
	p "margin = { $DD_INSET 0 }"
	p ""
	p "vbox = {"
	ind $((depth+3))
	p "visible = \"[GetVariableSystem.HasValue( 'leo_mvd_dd', '$id' )]\""
	p "layoutpolicy_horizontal = expanding"
	# The rows run the full width of the list and sit flush against each other,
	# as vanilla's do. Their text is already inset by leo_mvd_button_dropdown.
	p "using = Background_DropDown"
	p "spacing = 0"
	# <4>, when given, names the script list this dropdown's rows come from.
	# Every such expression resolves to leo_mvd_x while the dropdown is shut - a
	# list nothing ever creates - so a closed dropdown holds no row widgets at
	# all. That is the whole point: rows that merely hid still had to be built
	# and laid out, and 86% of this file used to be rows that were never shown.
	[ -n "${4:-}" ] && p "datamodel = \"[$4]\""

	# Where the caller's rows go. Returned this way so that changing the shape
	# above does not mean re-counting indents at every call site.
	DD_ROW_DEPTH=$((depth+4))
}

# The one row template a datamodel dropdown needs, in place of a literal widget
# per option. The item's flag is both halves of its identity: cond_5 names the
# label key leo_mvd_ui_cond_5 and the scripted GUI leo_mvd_set_cond_5, so the
# existing per-option scripted GUIs are reused untouched.
#
# <1> depth <2> node <3> label expr <4> tooltip expr, if any <5> visible expr,
# if any
emit_dd_item() { local depth=$1 node=$2 label=$3 tt=${4:-} vis=${5:-}
	ind "$depth"
	p "item = {"
	ind $((depth+1))
	p "leo_mvd_button_dropdown = {"
	ind $((depth+2))
	p "layoutpolicy_horizontal = expanding"
	p "size = { -1 30 }"
	[ -n "$vis" ] && p "visible = \"[$vis]\""
	[ -n "$tt" ] && p "tooltip = \"[$tt]\""
	p "onclick = \"[GetScriptedGui('leo_mvd_focus_${node}').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]\""
	p "onclick = \"[GetScriptedGui( Concatenate( 'leo_mvd_set_', Scope.GetFlagName ) ).Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]\""
	p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', 'none' )]\""
	p "text = \"[$label]\""
	ind $((depth+1)); p "}"
	ind "$depth"; p "}"
}

# Closes a dropdown: the list, a gap, then the group.
#
# The gap is its own widget because margin is padding on the inside of a widget:
# putting it on the list would just make the list's background taller. Since an
# open list pushes what is below it down rather than floating over it, it needs
# to hold that content off - but only while it is open, hence the same test the
# list itself uses.
#
# <1> depth  <2> id
emit_dd_end() { local depth=$1 id=$2
	ind $((depth+2)); p "}"
	ind $((depth+1)); p "}"
	p ""
	p "widget = {"
	ind $((depth+2))
	p "visible = \"[GetVariableSystem.HasValue( 'leo_mvd_dd', '$id' )]\""
	p "size = { 1 12 }"
	ind $((depth+1)); p "}"
	ind "$depth"; p "}"
}

# One option row. Three clicks in order: point the cursor at the node, write the
# value to it, close the list. GUI cannot hand script a number, so the node
# cannot simply be an argument - the cursor is what stands in for it.
# <1> depth <2> node <3> id <4> setter sgui <5> label expr-or-key <6> visible?
# <7> tooltip key?
emit_dd_row() { local depth=$1 node=$2 id=$3 setter=$4 label=$5 vis=${6:-} tt=${7:-}
	ind "$depth"
	p "leo_mvd_button_dropdown = {"
	ind $((depth+1))
	p "layoutpolicy_horizontal = expanding"
	p "size = { -1 30 }"
	[ -n "$vis" ] && p "visible = \"[$vis]\""
	[ -n "$tt" ] && p "tooltip = \"$tt\""
	# sgui() inlined here on purpose: this is the hot path - one row per directive,
	# condition and threshold option, several thousand in all - and a command
	# substitution per call forks a subshell, which dominates run time on git-bash.
	p "onclick = \"[GetScriptedGui('leo_mvd_focus_${node}').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]\""
	p "onclick = \"[GetScriptedGui('$setter').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]\""
	p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', 'none' )]\""
	p "text = \"$label\""
	ind "$depth"; p "}"
}

### One node's editor.

# <1> depth <2> priority <3> node number <4> level <5> parent's cond var, if any
emit_node() { local depth=$1 prio=$2 n=$3 level=$4 parent_cond=${5:-} sibling=${6:-}
	local node="${NODE_PREFIX}${prio}_n${n}"
	local kinds="1 2 0"; [ "$level" -ge 2 ] && kinds="1 0"

	# Sibling gates: a branch may not be made identical to the other branch of the
	# same condition. Each is purely a visibility rule on dropdown rows - it reads
	# node variables, never writes them, so an existing rule set that already has
	# identical branches keeps its values and runs unchanged; the dropdown simply
	# stops offering the row that would re-create the match.
	#
	# The root node (no sibling) gets none of these. Directive gate: hide the
	# directive the sibling assigns, when the sibling is also assigning. Condition
	# gate: hide the yes/no condition the sibling checks (measured conditions carry
	# -1 in the x table and never match, so a shared measured condition is allowed
	# and its threshold is gated instead). Threshold gate: hide the sibling's value
	# only when both branches check the same measured condition.
	local dir_sib= cond_sib= thresh_sib=
	if [ -n "$sibling" ]; then
		dir_sib="Not( And( $(veq "leo_mvd_${sibling}_kind" 1), $(xeq "leo_mvd_${sibling}_dir") ) )"
		cond_sib="Not( And( $(veq "leo_mvd_${sibling}_kind" 2), $(xeq "leo_mvd_${sibling}_cond") ) )"
		thresh_sib="Not( And( And( $(veq "leo_mvd_${sibling}_kind" 2), $(vveq "leo_mvd_${node}_cond" "leo_mvd_${sibling}_cond") ), $(xeq "leo_mvd_${sibling}_thresh") ) )"
	fi

	# What this node does. Kind 0's label depends on whether a next priority
	# exists, so the button has to ask before falling back to the generic key.
	local kind_label="SelectLocalization( $(veq "leo_mvd_${node}_kind" 0), $(kind0_key "$prio"), $(vkey 'leo_mvd_ui_kind_' "leo_mvd_${node}_kind") )"
	emit_dd_start "$depth" "${node}_kind" "$kind_label"
	for k in $kinds; do
		local kl="leo_mvd_ui_kind_$k" ktt="leo_mvd_ui_kind_${k}_tt"
		if [ "$k" = 0 ]; then
			kl="[$(kind0_key "$prio")]"
			ktt="[$(kind0_tt_key "$prio")]"
		fi
		emit_dd_row "$DD_ROW_DEPTH" "$node" "${node}_kind" "leo_mvd_set_kind_$k" "$kl" "" "$ktt"
	done
	emit_dd_end "$depth" "${node}_kind"

	# Assign a Directive
	ind "$depth"; p ""
	p "vbox = {"
	ind $((depth+1))
	p "visible = \"[$(veq "leo_mvd_${node}_kind" 1)]\""
	p "layoutpolicy_horizontal = expanding"
	p "margin_left = 16"
	p "spacing = 2"
	# The directive list. Which directives a player may pick is decided in script
	# (leo_mvd_build_options_effect), so the DLC gate that used to sit on every
	# administrative row is gone: an option they cannot use is simply absent.
	emit_dd_start $((depth+1)) "${node}_dir" "$(vkey 'leo_mvd_ui_dir_' "leo_mvd_${node}_dir")" \
		"GetPlayer.MakeScope.GetList( $(dd_list "${node}_dir" "$CUR_DIR_LIST") )"
	emit_dd_item "$DD_ROW_DEPTH" "$node" "Localize( Concatenate( 'leo_mvd_ui_', Scope.GetFlagName ) )" "" "$dir_sib"
	emit_dd_end $((depth+1)) "${node}_dir"
	ind "$depth"; p "}"

	[ "$level" -ge 2 ] && return

	# Check a Condition
	ind "$depth"; p ""
	p "vbox = {"
	ind $((depth+1))
	p "visible = \"[$(veq "leo_mvd_${node}_kind" 2)]\""
	p "layoutpolicy_horizontal = expanding"
	p "margin_left = 16"
	p "spacing = 2"
	# The condition list. DLC gating lives in script, as it does for directives.
	#
	# The redundancy gate stays, but it can no longer be written per row: an
	# item's identity is a string and the parent's answer is a number, and GUI
	# has no way to compare the two. So each condition's code is kept in a
	# variable named after its flag, and the row compares that against the
	# parent - measured conditions carry -1 there and so stay selectable under
	# themselves, which is how a middle band is carved out.
	#
	# Every condition gets a tooltip key. Most resolve to an empty string, which
	# renders no tooltip at all, so only the two that need explaining have one.
	# The parent-redundancy gate and the sibling gate combine: a condition row is
	# offered only if it is neither the parent's already-settled question nor the
	# yes/no condition the sibling is already checking.
	local citem_vis=
	[ -n "$parent_cond" ] && citem_vis="NotEqualTo_CFixedPoint( GetPlayer.MakeScope.Var( Concatenate( 'leo_mvd_x_', Scope.GetFlagName ) ).GetValue, GetPlayer.MakeScope.Var('$parent_cond').GetValue )"
	citem_vis=$(vis_and "$citem_vis" "$cond_sib")
	emit_dd_start $((depth+1)) "${node}_cond" "$(vkey 'leo_mvd_ui_cond_' "leo_mvd_${node}_cond")" \
		"GetPlayer.MakeScope.GetList( $(dd_list "${node}_cond" "$CUR_COND_LIST") )"
	emit_dd_item "$DD_ROW_DEPTH" "$node" \
		"Localize( Concatenate( 'leo_mvd_ui_', Scope.GetFlagName ) )" \
		"Localize( Concatenate( Concatenate( 'leo_mvd_ui_', Scope.GetFlagName ), '_tt' ) )" \
		"$citem_vis"
	emit_dd_end $((depth+1)) "${node}_cond"

	# Its threshold, if it takes one. One picker per node rather than one per
	# numeric condition: every numeric condition's rows live in a single dropdown,
	# each row gated so only the chosen condition's values show, and the picker as
	# a whole is hidden unless the chosen condition takes a threshold. The label is
	# built from the chosen condition and value at runtime.
	ind $((depth+1)); p ""
	p "vbox = {"
	ind $((depth+2))
	p "visible = \"[$(numeric_cond_sel "leo_mvd_${node}_cond")]\""
	p "layoutpolicy_horizontal = expanding"
	p "spacing = 2"
	# The threshold picker names its list from the node's own condition, so it
	# shows one ladder instead of carrying every condition's values at once,
	# each gated. A condition that takes no threshold has no such list, which
	# leaves the picker empty - and it is hidden then anyway.
	emit_dd_start $((depth+2)) "${node}_t" "$(thresh_label_dyn "leo_mvd_${node}_cond" "leo_mvd_${node}_thresh")" \
		"GetPlayer.MakeScope.GetList( $(dd_list "${node}_t" "Concatenate( 'leo_mvd_t_', $(vint "leo_mvd_${node}_cond") )") )"
	# The label needs both halves - which condition is asking, and which value -
	# so the key is leo_mvd_ui_c<cond>_<flag>, e.g. leo_mvd_ui_c9_thresh_1000.
	emit_dd_item "$DD_ROW_DEPTH" "$node" \
		"Localize( Concatenate( Concatenate( 'leo_mvd_ui_c', $(vint "leo_mvd_${node}_cond") ), Concatenate( '_', Scope.GetFlagName ) ) )" \
		"" "$thresh_sib"
	emit_dd_end $((depth+2)) "${node}_t"
	ind $((depth+1)); p "}"
	ind "$depth"; p "}"

	# Its branches. Only rendered once this node is actually a condition, so an
	# unused level costs the player nothing to look at.
	local kids kt kf; kids=$(node_children "$n")
	kt=$(echo "$kids" | cut -d' ' -f1); kf=$(echo "$kids" | cut -d' ' -f2)
	ind "$depth"; p ""
	p "vbox = {"
	ind $((depth+1))
	p "visible = \"[$(veq "leo_mvd_${node}_kind" 2)]\""
	p "layoutpolicy_horizontal = expanding"
	p "margin_left = 16"
	p "spacing = 2"
	for b in "true:$kt:$kf" "false:$kf:$kt"; do
		local which=${b%%:*} kid rest=${b#*:}
		kid=${rest%%:*}
		local sib_n=${rest##*:}
		ind $((depth+1)); p ""
		p "text_label_left = {"
		ind $((depth+2)); p "layoutpolicy_horizontal = expanding"
		p "text = \"leo_mvd_ui_branch_$which\""
		ind $((depth+1)); p "}"
		# The other branch of this condition is the sibling, so identical picks
		# can be gated out.
		emit_node $((depth+1)) "$prio" "$kid" $((level+1)) "leo_mvd_${node}_cond" "${NODE_PREFIX}${prio}_n${sib_n}"
	done
	ind "$depth"; p "}"
}

### A waterfall.
#
# There are two, and they are the same editor over different rules: the main one
# for settled vassals, and the nomads' own. Nomads have four directives no one
# else can be given and can be given none of the other nine, so they cannot
# share a running order with the rest - the two sets divide the eligible vassals
# exactly between them.
#
# Which one is being emitted lives in these, since emit_node reaches for them
# several levels down.
NODE_PREFIX=r
COUNT_VAR=leo_mvd_rule_count
CUR_DIRS="$DIRS"; CUR_DIR_LIST="'leo_mvd_dirs'"
CUR_CONDS="$CONDS"; CUR_COND_LIST="'leo_mvd_conds'"

# <1> main | nomad
emit_waterfall() {
	local which=$1
	local max heading add_sgui remove_prefix prio_loc remove_tt
	# Hides the whole nomad section without Khans of the Steppe: no vassal is a
	# nomad without it, so these rules could never fire. Empty for the main
	# waterfall, so vis_and leaves its shared bindings untouched.
	local dlc=; [ "$which" = nomad ] && dlc=$(vdlc khans_of_the_steppe)
	# Both waterfalls label their rows "Priority N", so they share one set of loc
	# keys (emit_loc covers the larger count). The nomad heading is what sets the
	# section apart, not the row labels.
	prio_loc=leo_mvd_ui_priority
	if [ "$which" = nomad ]; then
		NODE_PREFIX=q; COUNT_VAR=leo_mvd_qrule_count
		CUR_DIRS="$NOMAD_DIRS"; CUR_CONDS="$NOMAD_CONDS"; CUR_DIR_LIST="'leo_mvd_qdirs'"; CUR_COND_LIST="'leo_mvd_qconds'"
		max=$QPRIORITIES; heading=leo_mvd_ui_heading_nomads
		add_sgui=leo_mvd_add_qpriority; remove_prefix=leo_mvd_remove_qpriority
		# This waterfall may empty; the main one may not. Same button, different
		# promise.
		remove_tt=leo_mvd_ui_remove_qpriority_tt
	else
		NODE_PREFIX=r; COUNT_VAR=leo_mvd_rule_count
		CUR_DIRS="$DIRS"; CUR_CONDS="$CONDS"; CUR_DIR_LIST="'leo_mvd_dirs'"; CUR_COND_LIST="'leo_mvd_conds'"
		max=$PRIORITIES; heading=leo_mvd_ui_heading_priorities
		add_sgui=leo_mvd_add_priority; remove_prefix=leo_mvd_remove_priority
		remove_tt=leo_mvd_ui_remove_priority_tt
	fi

	# Heads the waterfall, so the rules read as their own thing rather than as
	# more of the preset's description.
	#
	# The nomad heading stays put even with no nomad rules, since its Add is the
	# only way to make some; the main one goes with None, which has no waterfall
	# and no way to start one short of picking a preset.
	ind 5; p ""
	p "### The $which waterfall."
	p "text_label_left = {"
	ind 6
	if [ "$which" = nomad ]; then
		p "visible = \"[$(vis_and "$dlc" "$(vge leo_mvd_rule_count 1)")]\""
	else
		p "visible = \"[$(vge "$COUNT_VAR" 1)]\""
	fi
	p "layoutpolicy_horizontal = expanding"
	p "text = \"$heading\""
	ind 5; p "}"

	# One collapsible section per priority in use.
	for prio in $(seq 1 "$max"); do
		ind 5; p ""
		p "### $which priority $prio (collapsible). Shown whenever the rule set in"
		p "### place reaches this far - for a built-in preset too, so its plan can"
		p "### be read rather than taken on trust."
		p "vbox = {"
		ind 6
		p "visible = \"[$(vis_and "$dlc" "$(vge "$COUNT_VAR" "$prio")")]\""
		p "layoutpolicy_horizontal = expanding"
		p "oncreate = \"[BindFoldOutContext]\""
		p "oncreate = \"[PdxGuiFoldOut.Unfold]\""
		p ""
		p "button_expandable_toggle_field = {"
		ind 7; p "blockoverride \"text\" {"
		ind 8; p "text = \"${prio_loc}_$prio\""
		ind 7; p "}"
		ind 6; p "}"
		p ""
		p "vbox = {"
		ind 7
		p "visible = \"[PdxGuiFoldOut.IsUnfolded]\""
		p "layoutpolicy_horizontal = expanding"
		p "margin = { 6 4 }"
		p "spacing = 2"
		p ""
		emit_node 7 "$prio" 1 0

		# Extend or shorten the waterfall.
		#
		# Add only appears on the end of it, and only while there is room to
		# extend it - a priority is always appended, so offering it halfway up
		# would say otherwise. Everywhere else Remove has the row to itself,
		# which it gets because the visible sits on Add's half rather than on
		# Add: a hidden widget takes no space, so the half collapses instead of
		# standing empty.
		ind 7; p ""
		p "hbox = {"
		ind 8
		p "layoutpolicy_horizontal = expanding"
		p "margin_top = 8"
		p "spacing = 6"

		# The last slot can never be the end of a waterfall with room left in
		# it, so it gets no Add at all rather than one that cannot show.
		if [ "$prio" -lt "$max" ]; then
			p ""
			p "hbox = {"
			ind 9
			# Only "is this the end", since prio < max already settles the rest.
			p "visible = \"[$(veq "$COUNT_VAR" "$prio")]\""
			p "layoutpolicy_horizontal = expanding"
			p ""
			p "button_standard = {"
			ind 10
			p "layoutpolicy_horizontal = expanding"
			p "text = \"leo_mvd_ui_add_priority\""
			p "onclick = \"$(sgui "$add_sgui")\""
			p "tooltip = \"leo_mvd_ui_add_priority_tt\""
			ind 9; p "}"
			ind 8; p "}"
		fi

		ind 8; p ""
		p "hbox = {"
		ind 9
		p "layoutpolicy_horizontal = expanding"
		p ""
		p "button_standard = {"
		ind 10
		p "layoutpolicy_horizontal = expanding"
		p "text = \"leo_mvd_ui_remove_priority\""
		p "onclick = \"$(sgui "${remove_prefix}_${prio}")\""
		# The nomad waterfall may empty, so its Remove has no is_valid and needs
		# no enabled - the binding would only ever answer yes.
		[ "$which" = main ] && p "enabled = \"$(sgui_valid "${remove_prefix}_${prio}")\""
		p "tooltip = \"$remove_tt\""
		ind 9; p "}"
		ind 8; p "}"
		ind 7; p "}"

		ind 6; p "}"
		ind 5; p "}"
	done

	# With no nomad rules there is no priority to hang an Add off, so the
	# section needs one of its own to get started.
	if [ "$which" = nomad ]; then
		ind 5; p ""
		p "### Start a nomad waterfall, when there is not one yet."
		p "hbox = {"
		ind 6
		p "visible = \"[$(vis_and "$dlc" "And( $(vge leo_mvd_rule_count 1), Not( $(vge "$COUNT_VAR" 1) ) )")]\""
		p "layoutpolicy_horizontal = expanding"
		p "margin = { 6 4 }"
		p ""
		p "button_standard = {"
		ind 7
		p "layoutpolicy_horizontal = expanding"
		p "text = \"leo_mvd_ui_add_priority\""
		p "onclick = \"$(sgui "$add_sgui")\""
		p "tooltip = \"leo_mvd_ui_nomads_empty_tt\""
		ind 6; p "}"
		ind 5; p "}"
	fi
}

### The panel.

emit_panel() {
cat << 'HEAD'
### Leo VI's Mass Vassal Directives - docked configuration panel.
###
### GENERATED by tools/gen_panel.sh - edits here will be overwritten.
###
### Registered as a standalone widget via gui/scripted_widgets/, so no
### vanilla file is overridden. Shown/hidden by the vanilla Subjects-tab
### directives button, which toggles the 'mass_directives_window' GUI
### variable (and which the realm window clears when it closes).
###
### Structure: a fixed header, a scrollbox that fills the middle (so content
### scrolls instead of overflowing), and a fixed action-button footer.
###
### Only the priorities collapse (BindFoldOutContext +
### button_expandable_toggle_field + visible = PdxGuiFoldOut.IsUnfolded, as the
### vanilla Subjects tab does for its vassal categories) - they stack up and get
### long. The other sections are short and always apply, so they are plain
### headings.
###
### A control reads its state straight out of the script variable it
### represents rather than through a scripted GUI's is_shown - either as a
### bool (EqualTo_CFixedPoint against Var(...).GetValue) or, for the text on
### a dropdown, by pasting the value onto a loc key prefix and resolving it.
### Only clicking a control runs script, so the panel costs no per-frame
### script evaluation however many controls it grows. Note that .GetValue
### yields a CFixedPoint, so literals take the form '(CFixedPoint)1'.

### The dropdown parts.
###
### These copy vanilla's button_drop and button_dropdown (shared/buttons.gui
### :1427 and :1456) so the dropdowns look like the game's own - minus one
### line. Both vanilla types set button_trigger = none, because they are only
### ever used inside a C++ dropDown, which handles the click itself; inheriting
### that leaves our own onclick never firing. Copies rather than overrides, so
### no vanilla file is touched. Re-diff after a game patch.
types leo_mvd_dropdown_types {
	type leo_mvd_button_drop = button_normal {
		size = { 100% 33 }
		gfxtype = framedbuttongfx
		effectname = "NoHighlight"
		upframe = 1
		overframe = 2
		downframe = 3
		disableframe = 4
		texture = "gfx/interface/buttons/button_drop_down.dds"
		framesize = { 225 33 }
		spriteType = Corneredtiled
		spriteborder = { 75 11 }
		clicksound = "event:/SFX/UI/Generic/sfx_ui_generic_checkbox"

		buttonText = {
			text_single = {
				size = { 100% 100% }
				autoresize = no
				margin = { 15 0 }
				margin_right = 25
				align = left|nobaseline
				default_format = "#clickable"
				alwaystransparent = yes
			}
		}
	}

	type leo_mvd_button_dropdown = button_normal {
		size = { 225 30 }
		gfxtype = framedbuttongfx
		effectname = "NoHighlight"
		shaderfile = "gfx/FX/pdxgui_pushbutton.shader"
		upframe = 1
		overframe = 2
		downframe = 3
		disableframe = 1
		texture = "gfx/interface/buttons/button_interaction_menu.dds"
		framesize = { 317 30 }
		clicksound = "event:/SFX/UI/Generic/sfx_ui_generic_checkbox"

		buttonText = {
			text_single = {
				size = { 100% 100% }
				autoresize = no
				margin_left = 10
				align = left|nobaseline
				alwaystransparent = yes
			}
		}
	}
}

window = {
	name = "leo_mvd_panel"
	# Sized off the character finder, the panel this most resembles: as wide as
	# its Filters (window_character_filter.gui:77, size = { 510 800 }, and which
	# is likewise a movable Window_Background_Subwindow), and as tall as the
	# finder itself (shared/windows.gui:79, Window_Size_CharacterList, 88%). A
	# full rule set is long, and 88% is what vanilla considers as much of the
	# screen as a window may take.
	size = { 510 88% }

	parentanchor = top|right
	position = { -645 70 }

	using = Window_Background_Subwindow
	# The layer the Realm window itself uses (window_my_realm.gui), so the panel
	# sits at the same depth as the Subjects tab it belongs to and beneath the
	# Character Finder (which is on the layer above), rather than floating over
	# everything as it did on 'top'.
	layer = windows_layer
	movable = yes

	### Shown by the vanilla button, or for one moment at startup to pre-warm.
	###
	### The tree is created at startup (gui/scripted_widgets/), but it is only
	### measured, laid out and its text shaped the first time the window becomes
	### visible - which is the whole of the hitch on first open, and why it does
	### not scale with how much of the panel a rule set actually shows. So show
	### it once at creation and that pass happens during the loading screen.
	###
	### Its own variable, not vanilla's mass_directives_window: that one also
	### drives the Subjects tab's compact list (window_my_realm.gui:3688), so
	### borrowing it would disturb vanilla's own UI.
	visible = "[Or( GetVariableSystem.Exists('mass_directives_window'), GetVariableSystem.Exists('leo_mvd_prewarm') )]"

	### Transparent while pre-warming, so laying out is all it does. Bound to the
	### same variable that ends the pre-warm rather than animated, so the panel
	### cannot get stuck invisible: the moment that clears, this reads 1 again.
	### alpha (rather than an off-screen position) because it is the same on every
	### resolution and UI scale, and its worst case is only that the warm does not
	### fully take and the old hitch returns - never a visible panel on load, which
	### is what a movable window clamped back on-screen could otherwise give.
	###
	### No input guard is needed alongside it. The pre-warm lives only between the
	### widget's creation and the load-to-session transition, and the engine wipes
	### GUI variables at that transition - which is what clears leo_mvd_prewarm,
	### and it is also before the player has mouse control. So there is no frame in
	### which this invisible panel could take a click. (alwaystransparent would not
	### help anyway: it is a per-widget pass-through, not a subtree blocker.)
	alpha = "[Select_float( GetVariableSystem.Exists('leo_mvd_prewarm'), '(float)0', '(float)1' )]"

	oncreate = "[GetVariableSystem.Set( 'leo_mvd_prewarm', '1' )]"

	### Ends the pre-warm a moment after creation. Copies vanilla's self-firing
	### timed state (achievements/popup.gui:58).
	state = {
		name = leo_mvd_prewarm_done
		trigger_on_create = yes
		duration = 0
		delay = 0.3
		on_finish = "[GetVariableSystem.Clear( 'leo_mvd_prewarm' )]"
	}

	state = {
		name = _show
		using = Animation_FadeIn_Quick
	}

	### Closing the panel also closes any open dropdown, so it does not come
	### back open the next time.
	state = {
		name = _hide
		using = Animation_FadeOut_Quick
		on_start = "[GetVariableSystem.Set( 'leo_mvd_dd', 'none' )]"
	}

	vbox = {
		layoutpolicy_horizontal = expanding
		layoutpolicy_vertical = expanding

		header_pattern = {
			layoutpolicy_horizontal = expanding

			blockoverride "header_text" {
				text = "leo_mvd_panel_title"
			}

			blockoverride "button_close" {
				onclick = "[GetVariableSystem.Clear('mass_directives_window')]"
			}
		}

		### Scrollable body - fills the space between header and footer, and
		### scrolls when the sections do not fit.
		scrollbox = {
			layoutpolicy_horizontal = expanding
			layoutpolicy_vertical = expanding

			blockoverride "scrollbox_content" {
				vbox = {
					layoutpolicy_horizontal = expanding
					spacing = 8

					### Automation section. Holds the two controls that decide
					### whether anything happens at all: the monthly run, and
					### which rule set it runs. Both always apply, so the section
					### is a plain heading - only the priorities, which stack up
					### and get long, are worth collapsing.
					###
					### The preset is a dropdown and names itself, so it needs no
					### heading of its own. None is selected by default: the mod
					### assigns nothing until a rule set is chosen. Custom keeps
					### whatever rules are loaded and opens them for editing.
					vbox = {
						layoutpolicy_horizontal = expanding

						text_label_left = {
							layoutpolicy_horizontal = expanding
							text = "leo_mvd_ui_heading_preset"
						}

						vbox = {
							layoutpolicy_horizontal = expanding
							margin = { 6 4 }
							margin_top = 8
							spacing = 4

HEAD

	# The preset comes first: it decides what the monthly run would even do.
	emit_dd_start 7 preset "$(vkey 'leo_mvd_ui_preset_' leo_mvd_preset)"
	for n in $PRESET_RANGE; do
		ind "$DD_ROW_DEPTH"
		p "leo_mvd_button_dropdown = {"
		ind $((DD_ROW_DEPTH+1))
		p "layoutpolicy_horizontal = expanding"
		p "size = { -1 30 }"
		p "onclick = \"$(sgui "leo_mvd_preset_${n}")\""
		p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', 'none' )]\""
		local pdv; pdv=$(preset_dlc_vis "$n")
		[ -n "$pdv" ] && p "visible = \"[$pdv]\""
		# Built-ins 1/3/4 describe a different flow without Roads to Power, since
		# their administrative directives drop out (see leo_mvd_rules.txt). The
		# _nodlc key holds that flow; presets with no such change alias it back to
		# the base description.
		p "tooltip = \"[SelectLocalization( HasDlcFeature( 'roads_to_power' ), 'leo_mvd_ui_preset_${n}_tt', 'leo_mvd_ui_preset_${n}_tt_nodlc' )]\""
		p "text = \"leo_mvd_ui_preset_${n}\""
		ind "$DD_ROW_DEPTH"; p "}"
	done
	emit_dd_end 7 preset

cat << 'MID'

							### The checkbox reflects a scripted GUI's is_shown
							### as its checked state and runs its effect on
							### click. It is expanding so its content left-aligns.
							button_checkbox_label = {
								layoutpolicy_horizontal = expanding
								onclick = "[GetScriptedGui('leo_mvd_toggle_auto').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
								enabled = "[GetScriptedGui('leo_mvd_toggle_auto').IsValid( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
								tooltip = "leo_mvd_ui_auto_tt"
								blockoverride "checkbox" {
									checked = "[GetScriptedGui('leo_mvd_toggle_auto').IsShown( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
									### Vanilla's checkbox is 30x30, which reads as
									### heavy next to a dropdown. The block sits
									### after the type's own size, so this wins.
									size = { 22 22 }
								}
								blockoverride "text" {
									text = "leo_mvd_ui_auto"
								}
							}
						}
					}
MID

	# What the chosen preset actually does, in the panel rather than only in a
	# tooltip. Selects the same _tt / _tt_nodlc pair the dropdown's own tooltip
	# does, so the two can never disagree - including which flow is shown without
	# Roads to Power. Hidden for Custom, where the rules are spelled out below
	# anyway; on None it is what tells a new player where to start.
	ind 5; p ""
	p "### Description section. Hidden while the player's own rules are"
	p "### selected, since the editor below says the same thing."
	p "vbox = {"
	ind 6
	p "visible = \"[Not( $(veq leo_mvd_preset 5) )]\""
	p "layoutpolicy_horizontal = expanding"
	p ""
	p "text_label_left = {"
	ind 7
	p "layoutpolicy_horizontal = expanding"
	p "text = \"leo_mvd_ui_heading_description\""
	ind 6; p "}"
	p ""
	p "vbox = {"
	ind 7
	p "layoutpolicy_horizontal = expanding"
	p "margin = { 6 4 }"
	p "margin_top = 12"
	p ""
	p "text_multi = {"
	ind 8
	p "layoutpolicy_horizontal = expanding"
	p "autoresize = yes"
	p "max_width = 440"
	p "align = left|nobaseline"
	p "text = \"[Localize(Concatenate(Concatenate('leo_mvd_ui_preset_', $(vint leo_mvd_preset)), Select_CString( HasDlcFeature( 'roads_to_power' ), '_tt', '_tt_nodlc' )))]\""
	ind 7; p "}"
	ind 6; p "}"
	ind 5; p "}"

	emit_waterfall main
	# A Game of Thrones never places nomads, so the AGOT build drops the section.
	if [ "$TARGET" != agot ]; then emit_waterfall nomad; fi

cat << 'TAIL'
				}
			}
		}

		### Action buttons - fixed footer, expanding so they split the row.
		hbox = {
			layoutpolicy_horizontal = expanding
			margin_top = 10
			margin_right = 16
			margin_bottom = 14
			margin_left = 16
			spacing = 6

			button_standard = {
				layoutpolicy_horizontal = expanding
				text = "leo_mvd_ui_apply"
				onclick = "[GetScriptedGui('leo_mvd_apply_now').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
				enabled = "[GetScriptedGui('leo_mvd_apply_now').IsValid( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
				tooltip = "leo_mvd_ui_apply_tt"
			}

			button_standard = {
				layoutpolicy_horizontal = expanding
				text = "leo_mvd_ui_remove_all"
				onclick = "[GetScriptedGui('leo_mvd_remove_all').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
				tooltip = "leo_mvd_ui_remove_all_tt"
			}
		}
	}
}
TAIL
}

### The scripted GUIs the panel's dropdowns call.

emit_sguis() {
cat << 'HEAD'
# Leo VI's Mass Vassal Directives - rule editor scripted GUIs
#
# GENERATED by tools/gen_panel.sh - edits here will be overwritten.
#
# Choosing an option runs two of these in order: a focus, which points a cursor
# at the node being edited, then a set, which writes one field to whatever the
# cursor points at. That split is what keeps this file to one entry per node
# plus one per option, instead of one per node-and-option pair - GUI cannot hand
# script a number, so the node cannot simply be an argument.
#
# None of these need is_shown: a control reads its own state straight from the
# variable it represents.
HEAD

	for prio in $(seq 1 "$PRIORITIES"); do
		echo
		echo "### Priority $prio nodes."
		for n in 1 2 3 4 5 6 7; do
			echo "leo_mvd_focus_r${prio}_n${n} = {"
			echo -e "\tscope = character"
			echo -e "\teffect = { leo_mvd_focus_effect = { CODE = $((prio*10+n)) } }"
			echo "}"
		done
	done

	# The nomad tree, addressed from 100 up so the two cannot collide.
	for prio in $(seq 1 "$QPRIORITIES"); do
		echo
		echo "### Nomad priority $prio nodes."
		for n in 1 2 3 4 5 6 7; do
			echo "leo_mvd_focus_q${prio}_n${n} = {"
			echo -e "\tscope = character"
			echo -e "\teffect = { leo_mvd_focus_effect = { CODE = $((100+prio*10+n)) } }"
			echo "}"
		done
	done

	echo
	echo "### Adding and removing priorities."
	echo "leo_mvd_add_priority = {"
	echo -e "\tscope = character"
	echo -e "\teffect = { leo_mvd_add_priority_effect = yes }"
	echo "}"
	for prio in $(seq 1 "$PRIORITIES"); do
		echo "leo_mvd_remove_priority_${prio} = {"
		echo -e "\tscope = character"
		echo -e "\t# Never down to nothing: a rule set with no priorities is None."
		echo -e "\tis_valid = { var:leo_mvd_rule_count > 1 }"
		echo -e "\teffect = { leo_mvd_remove_priority_${prio}_effect = yes }"
		echo "}"
	done

	echo "leo_mvd_add_qpriority = {"
	echo -e "\tscope = character"
	echo -e "\teffect = { leo_mvd_add_qpriority_effect = yes }"
	echo "}"
	for prio in $(seq 1 "$QPRIORITIES"); do
		echo "leo_mvd_remove_qpriority_${prio} = {"
		echo -e "\tscope = character"
		echo -e "\t# This one may empty: a realm with no nomads has no use for it."
		echo -e "\teffect = { leo_mvd_remove_qpriority_${prio}_effect = yes }"
		echo "}"
	done

	echo
	echo "### Opening a dropdown. Its rows come out of a variable list, which a"
	echo "### save made before those lists existed will not have - and the panel is"
	echo "### reached through a vanilla button, so nothing else need have run."
	echo "leo_mvd_ensure_options = {"
	echo -e "\tscope = character"
	echo -e "\teffect = { leo_mvd_ensure_options_effect = yes }"
	echo "}"

	echo
	echo "### Node kind."
	for k in 0 1 2; do
		echo "leo_mvd_set_kind_${k} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = { leo_mvd_edit_effect = { FIELD = 1 VALUE = $k } }"
		echo "}"
	done

	echo
	echo "### Conditions. Each also sets a sensible threshold, so that a numeric"
	echo "### condition is never left sitting at a value it has no label for."
	for c in $CONDS; do
		echo "leo_mvd_set_cond_${c} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = {"
		echo -e "\t\tleo_mvd_edit_effect = { FIELD = 2 VALUE = $c }"
		echo -e "\t\tleo_mvd_edit_effect = { FIELD = 3 VALUE = $(cond_default_thresh "$c") }"
		echo -e "\t}"
		echo "}"
	done

	echo
	echo "### Thresholds. Shared by value across conditions; only labels differ."
	for t in $(all_thresh_values); do
		echo "leo_mvd_set_thresh_${t} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = { leo_mvd_edit_effect = { FIELD = 3 VALUE = $t } }"
		echo "}"
	done

	echo
	echo "### Directives."
	for d in $ALL_DIRS; do
		echo "leo_mvd_set_dir_${d} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = { leo_mvd_edit_effect = { FIELD = 4 VALUE = $d } }"
		echo "}"
	done
}

### The option lists the dropdowns iterate.
#
# A dropdown's rows are not widgets in the panel any more. Script keeps a list
# of flags per dropdown family, the panel walks it with a datamodel, and one row
# template serves every option: a flag named cond_5 yields both the label key
# (leo_mvd_ui_cond_5) and the scripted GUI that writes it (leo_mvd_set_cond_5).
#
# Two things follow, and both are why this file exists rather than more GUI:
#
# DLC gating lives here now. An option a player cannot use is simply not in the
# list, instead of every row carrying a HasDlcFeature binding.
#
# Thresholds get one list per measured condition, named leo_mvd_t_<cond>, so the
# picker can name its list from the node's own condition and show only that
# ladder - where before every node carried every condition's values at once.
#
# Generated because the option sets differ per build target: the AGOT panel has
# conditions vanilla does not, and a different Military Strength ladder.

emit_options() {
cat << 'HEAD'
# Leo VI's Mass Vassal Directives - the panel's option lists
#
# GENERATED by tools/gen_panel.sh - edits here will be overwritten.
#
# Rebuilt at every game start rather than trusted from the save, so that
# installing or removing a DLC between sessions is picked up.
HEAD
	echo
	echo "leo_mvd_build_options_effect = {"

	# CONDS is the display order, so the list is built in that order and a gated
	# condition is wrapped in its own DLC check in place rather than pushed to the
	# end. That is what keeps Administrative Government and Governor Theme sitting
	# next to the questions they belong beside instead of after everything else.
	echo -e "\t# Conditions offered by the settled waterfall, in panel order."
	echo -e "\tclear_variable_list = leo_mvd_conds"
	for c in $CONDS; do
		local feat; feat=$(cond_dlc_feature "$c")
		if [ -n "$feat" ]; then
			echo -e "\tif = { limit = { has_dlc_feature = $feat } add_to_variable_list = { name = leo_mvd_conds target = flag:cond_$c } }"
		else
			echo -e "\tadd_to_variable_list = { name = leo_mvd_conds target = flag:cond_$c }"
		fi
	done

	echo
	echo -e "\t# Conditions offered by the nomad waterfall."
	echo -e "\tclear_variable_list = leo_mvd_qconds"
	for c in $NOMAD_CONDS; do
		echo -e "\tadd_to_variable_list = { name = leo_mvd_qconds target = flag:cond_$c }"
	done

	echo
	echo -e "\t# Directives, in panel order, gated in place like the conditions."
	echo -e "\tclear_variable_list = leo_mvd_dirs"
	for d in $DIRS; do
		local feat; feat=$(dir_dlc_feature "$d")
		if [ -n "$feat" ]; then
			echo -e "\tif = { limit = { has_dlc_feature = $feat } add_to_variable_list = { name = leo_mvd_dirs target = flag:dir_$d } }"
		else
			echo -e "\tadd_to_variable_list = { name = leo_mvd_dirs target = flag:dir_$d }"
		fi
	done
	echo -e "\tclear_variable_list = leo_mvd_qdirs"
	for d in $NOMAD_DIRS; do
		echo -e "\tadd_to_variable_list = { name = leo_mvd_qdirs target = flag:dir_$d }"
	done

	echo
	echo -e "\t# One threshold ladder per measured condition."
	for c in $NUMERIC_CONDS; do
		echo -e "\tclear_variable_list = leo_mvd_t_$c"
		for t in $(cond_thresh "$c"); do
			echo -e "\tadd_to_variable_list = { name = leo_mvd_t_$c target = flag:thresh_$t }"
		done
	done

	echo
	echo -e "\t# The code each option carries, keyed by its own flag, so a datamodel"
	echo -e "\t# row can read its identity as a number and compare it against a node"
	echo -e "\t# variable - which is a number too. GUI cannot compare the row's flag"
	echo -e "\t# string against a number directly, so this table stands in."
	echo -e "\t#"
	echo -e "\t# Two gates use it. A child hides the yes/no question its parent already"
	echo -e "\t# settled (measured conditions carry -1 and never match, staying"
	echo -e "\t# selectable under themselves to carve a band). And each branch of a"
	echo -e "\t# condition hides whatever its sibling already picked, so the two can"
	echo -e "\t# never be made identical: same directive, same yes/no condition, or"
	echo -e "\t# same measured condition at the same threshold."
	for c in $CONDS; do
		if is_numeric "$c"; then
			echo -e "\tset_variable = { name = leo_mvd_x_cond_$c value = -1 }"
		else
			echo -e "\tset_variable = { name = leo_mvd_x_cond_$c value = $c }"
		fi
	done
	for d in $ALL_DIRS; do
		echo -e "\tset_variable = { name = leo_mvd_x_dir_$d value = $d }"
	done
	for t in $(all_thresh_values); do
		echo -e "\tset_variable = { name = leo_mvd_x_thresh_$t value = $t }"
	done

	echo
	echo -e "\t# Stamps what these lists were built from, so a save carrying an"
	echo -e "\t# older option set is spotted and rebuilt rather than trusted."
	echo -e "\tset_variable = { name = leo_mvd_opts_version value = $(options_version) }"

	echo
	echo -e "\t# Everything above is read only by the panel's datamodels, and the"
	echo -e "\t# script validator does not count GUI use - left unnamed in script it"
	echo -e "\t# reports every flag and variable as \"set but never used\". Naming"
	echo -e "\t# them once here is what keeps error.log clean. The branch never runs."
	echo -e "\tif = {"
	echo -e "\t\tlimit = { leo_mvd_options_ack_trigger = yes }"
	echo -e "\t}"
	echo "}"

	echo
	echo "# Current scope: the player. Build the lists if they are missing or stale."
	echo "#"
	echo "# Cheap enough to sit on the common path: one comparison unless the option"
	echo "# set has actually changed. Game start rebuilds unconditionally instead, so"
	echo "# that installing or removing a DLC is picked up even when the version is"
	echo "# unchanged."
	echo "leo_mvd_ensure_options_effect = {"
	echo -e "\tif = {"
	echo -e "\t\tlimit = {"
	echo -e "\t\t\tOR = {"
	echo -e "\t\t\t\t# Reading the variable is guarded: a save from before the"
	echo -e "\t\t\t\t# lists existed has no such variable to compare."
	echo -e "\t\t\t\tNOT = { has_variable = leo_mvd_opts_version }"
	echo -e "\t\t\t\tNOT = { var:leo_mvd_opts_version = $(options_version) }"
	echo -e "\t\t\t}"
	echo -e "\t\t}"
	echo -e "\t\tleo_mvd_build_options_effect = yes"
	echo -e "\t}"
	echo "}"
}

# A number that changes whenever the option set does, so a save built against an
# older one rebuilds instead of showing a stale list. The count of every option
# the panel can offer, which no realistic edit leaves untouched.
options_version() {
	local n=0 c
	for c in $CONDS; do n=$((n+1)); done
	for c in $NOMAD_CONDS; do n=$((n+1)); done
	for c in $DIRS $NOMAD_DIRS; do n=$((n+1)); done
	for c in $NUMERIC_CONDS; do
		local t; for t in $(cond_thresh "$c"); do n=$((n+1)); done
	done
	echo $n
}

# The counterpart to the note above. Fails on its first line, so nothing after
# it is ever evaluated at run time - it exists to be read, not run.
emit_options_ack() {
cat << 'HEAD'
# Leo VI's Mass Vassal Directives - option list acknowledgement
#
# GENERATED by tools/gen_panel.sh - edits here will be overwritten.
#
# Names every flag and variable that only the panel reads, so the script
# validator stops reporting them as set-but-never-used. always = no is the first
# line, so this costs nothing at run time.
HEAD
	echo
	echo "leo_mvd_options_ack_trigger = {"
	echo -e "\talways = no"
	for c in $CONDS; do
		echo -e "\tis_target_in_variable_list = { name = leo_mvd_conds target = flag:cond_$c }"
		echo -e "\tvar:leo_mvd_x_cond_$c = $c"
	done
	for d in $ALL_DIRS; do
		echo -e "\tis_target_in_variable_list = { name = leo_mvd_dirs target = flag:dir_$d }"
		echo -e "\tvar:leo_mvd_x_dir_$d = $d"
	done
	for t in $(all_thresh_values); do
		echo -e "\tis_target_in_variable_list = { name = leo_mvd_t_9 target = flag:thresh_$t }"
		echo -e "\tvar:leo_mvd_x_thresh_$t = $t"
	done
	echo "}"
}

### The editor's labels.
#
# A dropdown builds its label key by pasting the variable's value onto a prefix,
# so every value a variable can hold needs a key here - including 0, which is
# what a node starts on.

emit_loc() {
	echo "l_english:"
	echo " ### Rule editor"
	echo " # GENERATED by tools/gen_panel.sh - edits here will be overwritten."
	echo " # Static panel text lives in leo_mvd_l_english.yml instead."
	echo
	# Both waterfalls share these "Priority N" labels, so cover whichever runs
	# longer (main today, but do not assume it).
	prio_labels=$PRIORITIES; [ "$QPRIORITIES" -gt "$prio_labels" ] && prio_labels=$QPRIORITIES
	for prio in $(seq 1 "$prio_labels"); do
		echo " leo_mvd_ui_priority_${prio}: \"Priority ${prio}\""
	done
	echo
	echo " leo_mvd_ui_kind_0: \"Continue to Next Priority\""
	echo " leo_mvd_ui_kind_0_last: \"Leave Without a [directive|E]\""
	echo " leo_mvd_ui_kind_0_tt: \"Do nothing here. The next priority decides this [vassal|E] instead.\""
	echo " leo_mvd_ui_kind_0_last_tt: \"Nothing further is tried. A [vassal|E] who reaches this last priority is left without a [directive|E].\""
	echo " leo_mvd_ui_kind_1: \"Assign a [directive|E]\""
	echo " leo_mvd_ui_kind_1_tt: \"Give the [vassal|E] a [directive|E].\\n\\n#weak Vassals who cannot be given it (the game's own rules still apply) fall through to the next priority instead.#!\""
	echo " leo_mvd_ui_kind_2: \"Check a Condition\""
	echo " leo_mvd_ui_kind_2_tt: \"Ask something about the [vassal|E], and send each answer its own way.\""
	echo
	echo " leo_mvd_ui_branch_true: \"If True\""
	echo " leo_mvd_ui_branch_false: \"If False\""
	echo
	echo " leo_mvd_ui_add_priority: \"Add Priority\""
	echo " leo_mvd_ui_add_priority_tt: \"Add a priority to the end of the waterfall, for [vassals|E] none of the ones above it claimed.\""
	echo " leo_mvd_ui_remove_priority: \"Remove\""
	echo " leo_mvd_ui_remove_priority_tt: \"Drop this priority. The ones below it move up to close the gap.\\n\\n#weak A rule set always keeps at least one priority. To assign nothing at all, choose the None preset.#!\""
	echo " leo_mvd_ui_remove_qpriority_tt: \"Drop this priority. The ones below it move up to close the gap.\n\n#weak Removing them all is allowed. Your [nomad|E] [vassals|E] are then left alone.#!\""
	echo
	echo " leo_mvd_ui_dir_0: \"#weak Choose a Directive#!\""
	for d in $ALL_DIRS; do
		echo " leo_mvd_ui_dir_${d}: \"@leo_mvd_dir_icon_$(dir_icon "$d")! $(dir_name "$d")\""
	done
	echo
	echo " leo_mvd_ui_cond_0: \"#weak Choose a Condition#!\""
	for c in $CONDS; do
		echo " leo_mvd_ui_cond_${c}: \"$(cond_name "$c")\""
	done
	echo
	# Every condition needs a tooltip key, because one row template serves them
	# all and builds the key from the option's own name. An empty value renders
	# no tooltip at all, so the ones with nothing to explain simply say nothing.
	# The two that do explain themselves are hand-written in leo_mvd_l_english.yml.
	for c in $CONDS; do
		[ -n "$(cond_tt "$c")" ] && continue
		echo " leo_mvd_ui_cond_${c}_tt: \"\""
	done
	echo
	# Keyed by the asking condition and the option's flag, since the row template
	# knows both: leo_mvd_ui_c<cond>_<flag>.
	for c in $NUMERIC_CONDS; do
		for t in $(cond_thresh "$c"); do
			echo " leo_mvd_ui_c${c}_thresh_${t}: \"$(thresh_label "$c" "$t")\""
		done
	done
}

### Write them out, each with the UTF-8 BOM the game requires.

# <1> emitter  <2> destination. Built aside, checked, then moved into place, so
# a run that dies partway leaves the real file untouched rather than truncated.
emit_to() {
	local emitter=$1
	local dest=$2
	local tmp="$TMP/$(basename "$dest")"
	printf '\xEF\xBB\xBF' > "$tmp"
	"$emitter" >> "$tmp"
	local o c
	o=$(tr -cd '{' < "$tmp" | wc -c); c=$(tr -cd '}' < "$tmp" | wc -c)
	if [ "$o" != "$c" ]; then
		echo "ABORT: $dest came out unbalanced ({=$o }=$c) - not written" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$dest")"
	mv "$tmp" "$dest"
}

vlog "panel -> $OUTDIR/gui/leo_mvd_panel.gui"
emit_to emit_panel "$OUTDIR/gui/leo_mvd_panel.gui"
vlog "scripted GUIs -> $OUTDIR/common/scripted_guis/leo_mvd_edit.txt"
emit_to emit_sguis "$OUTDIR/common/scripted_guis/leo_mvd_edit.txt"
vlog "localization -> $OUTDIR/localization/english/leo_mvd_ui_l_english.yml"
emit_to emit_loc   "$OUTDIR/localization/english/leo_mvd_ui_l_english.yml"
vlog "option lists -> $OUTDIR/common/scripted_effects/leo_mvd_options.txt"
emit_to emit_options "$OUTDIR/common/scripted_effects/leo_mvd_options.txt"
vlog "option ack -> $OUTDIR/common/scripted_triggers/leo_mvd_options_ack.txt"
emit_to emit_options_ack "$OUTDIR/common/scripted_triggers/leo_mvd_options_ack.txt"

echo "Generated $PRIORITIES priority editor(s) [target=$TARGET]:"
wc -l "$OUTDIR/gui/leo_mvd_panel.gui" "$OUTDIR/common/scripted_guis/leo_mvd_edit.txt" \
	"$OUTDIR/localization/english/leo_mvd_ui_l_english.yml" \
	"$OUTDIR/common/scripted_effects/leo_mvd_options.txt" \
	"$OUTDIR/common/scripted_triggers/leo_mvd_options_ack.txt"
