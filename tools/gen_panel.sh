#!/bin/bash
#
# Generates the repetitive parts of the configuration panel.
#
# The rule editor is the same handful of widgets repeated for every node of
# every priority, differing only in the variable name they bind to. There is no
# way to factor that out in GUI - blockoverride cannot parameterise the variable
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

### How much to generate.
PRIORITIES=1          # main rule priorities to emit (max 6; see leo_mvd_rules.txt)

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
dir_icon() { case $1 in
	1) echo convert_faith ;;                2) echo convert_culture ;;
	3) echo improve_development ;;          4) echo train_commanders ;;
	5) echo build_maa ;;                    6) echo improve_cultural_acceptance ;;
	7) echo building_focus_fortification ;; 8) echo building_focus_military ;;
	9) echo building_focus_economy ;;
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
esac; }

# Condition codes. Must match leo_mvd_cond_holds_trigger.
CONDS="1 2 3 4 5 6 7 8 9 10 11 12 13 14"
cond_name() { case $1 in
	1) echo "Faith is Yours" ;;
	2) echo "Culture is Yours" ;;
	3) echo "Holds Counties of Another Faith" ;;
	4) echo "Holds Counties of Another Culture" ;;
	5) echo "Same Dynasty as You" ;;
	6) echo "Administrative Government" ;;
	7) echo "Is a Powerful Vassal" ;;
	8) echo "Is on Your Council" ;;
	9) echo "Military Strength is at Least" ;;
	10) echo "Title Tier is at Least" ;;
	11) echo "Capital Development is at Least" ;;
	12) echo "Opinion of You is at Least" ;;
	13) echo "Counties Held is at Least" ;;
	14) echo "Cultural Acceptance with You is at Least" ;;
esac; }

# Thresholds, per numeric condition. All non-negative: a label key is built by
# pasting the value onto a prefix at runtime, and a minus sign in a key is not
# worth the risk.
NUMERIC_CONDS="9 10 11 12 13 14"
cond_thresh() { case $1 in
	9)  echo "500 1000 2000 5000" ;;
	10) echo "2 3 4 5" ;;
	11) echo "10 20 40 60 80" ;;
	12) echo "0 25 50 75" ;;
	13) echo "1 2 3 5 10" ;;
	14) echo "10 25 50 75 90" ;;
esac; }

# Picking a condition also sets this, so a threshold is never left at 0 - which
# would name a label key that does not exist.
cond_default_thresh() { case $1 in
	9) echo 1000 ;; 10) echo 3 ;; 11) echo 40 ;; 12) echo 50 ;; 13) echo 3 ;; 14) echo 50 ;;
	*) echo 0 ;;
esac; }

# A threshold's label depends on the condition asking for it.
thresh_label() { local c=$1 t=$2
	case $c in
	10) case $t in 2) echo "County" ;; 3) echo "Duchy" ;; 4) echo "Kingdom" ;; 5) echo "Empire" ;; esac ;;
	14) echo "$t%" ;;
	13) case $t in 1) echo "1 County" ;; *) echo "$t Counties" ;; esac ;;
	*)  echo "$t" ;;
	esac
}

all_thresh_values() { for c in $NUMERIC_CONDS; do cond_thresh "$c"; done | tr ' ' '\n' | sort -un; }

# A priority's node tree: n1 root, n2/n3 its branches, n4..n7 the grandchildren.
# n4..n7 are leaves - no condition - which is the depth cap standing in for the
# recursion the script language does not allow.
node_children() { case $1 in 1) echo "2 3" ;; 2) echo "4 5" ;; 3) echo "6 7" ;; esac; }

### Emit helpers.

I=""
ind() { I=$(printf '\t%.0s' $(seq 1 "$1")); }
p() { echo "${I}$1"; }

# A GUI bool: does variable <1> equal <2>?
veq() { echo "EqualTo_CFixedPoint( GetPlayer.MakeScope.Var('$1').GetValue, '(CFixedPoint)$2' )"; }
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

# Kind 0 means "fall through to the next priority" - but on the last priority
# there is no next one, and it means "leave this vassal without a directive".
# Same behaviour either way, so only the label changes.
kind0_key() { echo "SelectLocalization( $(vge leo_mvd_rule_count $(($1 + 1))), 'leo_mvd_ui_kind_0', 'leo_mvd_ui_kind_0_last' )"; }

### Dropdowns.
#
# These open in flow, pushing the rows below them down, rather than floating
# over them. That is forced, not preferred.
#
# Draw order is tree order and there is no z-index for a non-window widget, so a
# list living inside its row is painted over by every row after it. Floating
# would mean hoisting the open list into a later sibling, which needs either a
# datamodel to mirror for alignment (script variable lists hold scopes, so rule
# nodes cannot be items) or the button's screen position (no datafunction
# returns one). Vanilla hits the same wall: game_rules.gui is this same panel -
# a scrollbox of rows each needing a selector - and puts its dropdowns in the
# header outside the scrollbox, while the rows inside use an arrow cycler.
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
emit_dd_start() { local depth=$1 id=$2 label=$3 tt=${4:-}
	ind "$depth"
	p "vbox = {"
	ind $((depth+1))
	p "layoutpolicy_horizontal = expanding"
	p "spacing = 0"
	p ""
	p "leo_mvd_button_drop = {"
	ind $((depth+2))
	p "layoutpolicy_horizontal = expanding"
	p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', Select_CString( GetVariableSystem.HasValue( 'leo_mvd_dd', '$id' ), 'none', '$id' ) )]\""
	p "text = \"[$label]\""
	[ -n "$tt" ] && p "tooltip = \"$tt\""
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

	# Where the caller's rows go. Returned this way so that changing the shape
	# above does not mean re-counting indents at every call site.
	DD_ROW_DEPTH=$((depth+4))
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
	p "onclick = \"$(sgui "leo_mvd_focus_${node}")\""
	p "onclick = \"$(sgui "$setter")\""
	p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', 'none' )]\""
	p "text = \"$label\""
	ind "$depth"; p "}"
}

# Whether condition <1> should be offered on a node whose parent condition lives
# in variable <2>.
#
# Re-asking a yes/no question its parent already settled can only ever give the
# same answer, so those are hidden. The measured conditions are left alone: a
# branch of "Military Strength is at Least 1000" asking "is it at least 500?"
# is how you carve out a middle band, and is worth keeping.
cond_row_visible() { local c=$1 parent_var=$2
	[ -z "$parent_var" ] && return
	[ "$c" -ge 9 ] && return
	echo "Not( $(veq "$parent_var" "$c") )"
}

emit_dd_close() { ind "$1"; p "}"; }

### One node's editor.

# <1> depth <2> priority <3> node number <4> level <5> parent's cond var, if any
emit_node() { local depth=$1 prio=$2 n=$3 level=$4 parent_cond=${5:-}
	local node="r${prio}_n${n}"
	local kinds="1 2 0"; [ "$level" -ge 2 ] && kinds="1 0"

	# What this node does. Kind 0's label depends on whether a next priority
	# exists, so the button has to ask before falling back to the generic key.
	local kind_label="SelectLocalization( $(veq "leo_mvd_${node}_kind" 0), $(kind0_key "$prio"), $(vkey 'leo_mvd_ui_kind_' "leo_mvd_${node}_kind") )"
	emit_dd_start "$depth" "${node}_kind" "$kind_label"
	for k in $kinds; do
		local kl="leo_mvd_ui_kind_$k"
		[ "$k" = 0 ] && kl="[$(kind0_key "$prio")]"
		emit_dd_row "$DD_ROW_DEPTH" "$node" "${node}_kind" "leo_mvd_set_kind_$k" "$kl" "" "leo_mvd_ui_kind_${k}_tt"
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
	emit_dd_start $((depth+1)) "${node}_dir" "$(vkey 'leo_mvd_ui_dir_' "leo_mvd_${node}_dir")"
	for d in $DIRS; do
		emit_dd_row "$DD_ROW_DEPTH" "$node" "${node}_dir" "leo_mvd_set_dir_$d" "leo_mvd_ui_dir_$d"
	done
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
	emit_dd_start $((depth+1)) "${node}_cond" "$(vkey 'leo_mvd_ui_cond_' "leo_mvd_${node}_cond")"
	for c in $CONDS; do
		emit_dd_row "$DD_ROW_DEPTH" "$node" "${node}_cond" "leo_mvd_set_cond_$c" "leo_mvd_ui_cond_$c" "$(cond_row_visible "$c" "$parent_cond")"
	done
	emit_dd_end $((depth+1)) "${node}_cond"

	# Its threshold, if it takes one. Only the chosen condition's list exists on
	# screen, so the label prefix can be that condition's, spelled out.
	for c in $NUMERIC_CONDS; do
		ind $((depth+1)); p ""
		p "vbox = {"
		ind $((depth+2))
		p "visible = \"[$(veq "leo_mvd_${node}_cond" "$c")]\""
		p "layoutpolicy_horizontal = expanding"
		p "spacing = 2"
		emit_dd_start $((depth+2)) "${node}_t${c}" "$(vkey "leo_mvd_ui_thresh_c${c}_" "leo_mvd_${node}_thresh")"
		for t in $(cond_thresh "$c"); do
			emit_dd_row "$DD_ROW_DEPTH" "$node" "${node}_t${c}" "leo_mvd_set_thresh_$t" "leo_mvd_ui_thresh_c${c}_${t}"
		done
		emit_dd_end $((depth+2)) "${node}_t${c}"
		ind $((depth+1)); p "}"
	done
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
	for b in "true:$kt" "false:$kf"; do
		local which=${b%%:*} kid=${b##*:}
		ind $((depth+1)); p ""
		p "text_label_left = {"
		ind $((depth+2)); p "layoutpolicy_horizontal = expanding"
		p "text = \"leo_mvd_ui_branch_$which\""
		ind $((depth+1)); p "}"
		emit_node $((depth+1)) "$prio" "$kid" $((level+1)) "leo_mvd_${node}_cond"
	done
	ind "$depth"; p "}"
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
	size = { 500 700 }

	parentanchor = top|right
	position = { -645 70 }

	using = Window_Background_Subwindow
	layer = top
	movable = yes

	visible = "[GetVariableSystem.Exists('mass_directives_window')]"

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
	for n in 0 1 2 3 4 5; do
		ind "$DD_ROW_DEPTH"
		p "leo_mvd_button_dropdown = {"
		ind $((DD_ROW_DEPTH+1))
		p "layoutpolicy_horizontal = expanding"
		p "size = { -1 30 }"
		p "onclick = \"$(sgui "leo_mvd_preset_${n}")\""
		p "onclick = \"[GetVariableSystem.Set( 'leo_mvd_dd', 'none' )]\""
		p "tooltip = \"leo_mvd_ui_preset_${n}_tt\""
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
	# tooltip. Reads the same key the dropdown's own tooltip does, so the two can
	# never disagree. Hidden for Custom, where the rules are spelled out below
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
	p "text = \"[Localize(Concatenate(Concatenate('leo_mvd_ui_preset_', $(vint leo_mvd_preset)), '_tt'))]\""
	ind 7; p "}"
	ind 6; p "}"
	ind 5; p "}"

	# The rule editor: one collapsible section per priority in use.
	for prio in $(seq 1 "$PRIORITIES"); do
		ind 5; p ""
		p "### Priority $prio (collapsible). Shown only while the player's own"
		p "### rules are selected and this priority is in use."
		p "vbox = {"
		ind 6
		p "visible = \"[And( $(veq leo_mvd_preset 5), $(vge leo_mvd_rule_count "$prio") )]\""
		p "layoutpolicy_horizontal = expanding"
		p "oncreate = \"[BindFoldOutContext]\""
		p "oncreate = \"[PdxGuiFoldOut.Unfold]\""
		p ""
		p "button_expandable_toggle_field = {"
		ind 7; p "blockoverride \"text\" {"
		ind 8; p "text = \"leo_mvd_ui_priority_$prio\""
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
		ind 6; p "}"
		ind 5; p "}"
	done

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
	for d in $DIRS; do
		echo "leo_mvd_set_dir_${d} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = { leo_mvd_edit_effect = { FIELD = 4 VALUE = $d } }"
		echo "}"
	done
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
	for prio in $(seq 1 6); do
		echo " leo_mvd_ui_priority_${prio}: \"Priority ${prio}\""
	done
	echo
	echo " leo_mvd_ui_kind_0: \"Continue to Next Priority\""
	echo " leo_mvd_ui_kind_0_last: \"Leave Without a Directive\""
	echo " leo_mvd_ui_kind_0_tt: \"Do nothing here, and let the next priority decide instead.\\n\\n#weak On the last priority there is no next one, so the [vassal|E] is simply left without a [directive|E].#!\""
	echo " leo_mvd_ui_kind_1: \"Assign a Directive\""
	echo " leo_mvd_ui_kind_1_tt: \"Give the [vassal|E] a [directive|E].\\n\\n#weak Vassals who cannot be given it - the game's own rules still apply - fall through to the next priority instead.#!\""
	echo " leo_mvd_ui_kind_2: \"Check a Condition\""
	echo " leo_mvd_ui_kind_2_tt: \"Ask something about the [vassal|E], and send each answer its own way.\""
	echo
	echo " leo_mvd_ui_branch_true: \"If True\""
	echo " leo_mvd_ui_branch_false: \"If False\""
	echo
	echo " leo_mvd_ui_dir_0: \"#weak Choose a Directive#!\""
	for d in $DIRS; do
		echo " leo_mvd_ui_dir_${d}: \"@leo_mvd_dir_icon_$(dir_icon "$d")! $(dir_name "$d")\""
	done
	echo
	echo " leo_mvd_ui_cond_0: \"#weak Choose a Condition#!\""
	for c in $CONDS; do
		echo " leo_mvd_ui_cond_${c}: \"$(cond_name "$c")\""
	done
	echo
	for c in $NUMERIC_CONDS; do
		for t in $(cond_thresh "$c"); do
			echo " leo_mvd_ui_thresh_c${c}_${t}: \"$(thresh_label "$c" "$t")\""
		done
	done
}

### Write them out, each with the UTF-8 BOM the game requires.

write_bom() { printf '\xEF\xBB\xBF' > "$1"; }

write_bom gui/leo_mvd_panel.gui
emit_panel >> gui/leo_mvd_panel.gui

write_bom common/scripted_guis/leo_mvd_edit.txt
emit_sguis >> common/scripted_guis/leo_mvd_edit.txt

write_bom localization/english/leo_mvd_ui_l_english.yml
emit_loc >> localization/english/leo_mvd_ui_l_english.yml

echo "Generated $PRIORITIES priority editor(s):"
wc -l gui/leo_mvd_panel.gui common/scripted_guis/leo_mvd_edit.txt localization/english/leo_mvd_ui_l_english.yml
