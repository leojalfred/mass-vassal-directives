#!/bin/bash
#
# Generates the repetitive parts of the configuration panel.
#
# The rule editor is the same handful of widgets repeated for every node of
# every priority, differing only in the variable name they bind to. There is no
# way to factor that out in GUI - blockoverride cannot parameterise the variable
# name inside a binding - so a priority's editor is ~200 near-identical widgets
# and six of them would be some 12000 lines. Generating it keeps the repetition
# consistent and makes changing the pattern a one-line edit here.
#
# Emits three files, from one description of the rules, so that the panel, the
# scripted GUIs it calls, and the localization it names cannot drift apart:
#
#   gui/leo_mvd_panel.gui                     the panel
#   common/scripted_guis/leo_mvd_edit.txt     focus/set scripted GUIs
#   localization/english/leo_mvd_ui_l_english.yml   editor labels
#
# Hand edits to those three files will be overwritten. Tune the layout here
# instead - the skeleton and the margins live in emit_panel below.
#
# Usage: bash tools/gen_panel.sh        (from the mod root)

set -euo pipefail
cd "$(dirname "$0")/.."

### How much to generate.
PRIORITIES=1          # main rule priorities to emit (max 6; see leo_mvd_rules.txt)

### The rules, described once.

# Directive codes -> vanilla loc key. The vanilla keys already embed the icon.
DIRS="1 2 3 4 5 6 7 8 9"
dir_loc() { case $1 in
	1) echo convert_faith ;;               2) echo convert_culture ;;
	3) echo improve_development ;;         4) echo train_commanders ;;
	5) echo build_maa ;;                   6) echo improve_cultural_acceptance ;;
	7) echo building_focus_fortification ;; 8) echo building_focus_military ;;
	9) echo building_focus_economy ;;
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

# Thresholds, per numeric condition. Tokens, because a name cannot hold a minus.
NUMERIC_CONDS="9 10 11 12 13 14"
cond_thresh() { case $1 in
	9)  echo "500 1000 2000 5000" ;;
	10) echo "2 3 4 5" ;;
	11) echo "10 20 40 60 80" ;;
	12) echo "n50 0 25 50 75" ;;
	13) echo "1 2 3 5 10" ;;
	14) echo "10 25 50 75 90" ;;
esac; }

# Token -> the number it means.
tok_value() { case $1 in n*) echo "-${1#n}" ;; *) echo "$1" ;; esac; }

# Token -> its label, which depends on the condition asking.
thresh_label() { local c=$1 t=$2
	case $c in
	10) case $t in 2) echo "County" ;; 3) echo "Duchy" ;; 4) echo "Kingdom" ;; 5) echo "Empire" ;; esac ;;
	14) echo "$t%" ;;
	12) tok_value "$t" ;;
	13) case $t in 1) echo "1 County" ;; *) echo "$t Counties" ;; esac ;;
	*)  echo "$t" ;;
	esac
}

# Every distinct threshold token, across all conditions.
all_thresh_tokens() { for c in $NUMERIC_CONDS; do cond_thresh "$c"; done | tr ' ' '\n' | sort -u; }

# A priority's node tree: n1 root, n2/n3 its branches, n4..n7 the grandchildren.
# n4..n7 are leaves - no condition - which is the depth cap standing in for the
# recursion the script language does not allow.
node_children() { case $1 in 1) echo "2 3" ;; 2) echo "4 5" ;; 3) echo "6 7" ;; esac; }

### Emit helpers.

I=""                       # current indent
ind() { I=$(printf '\t%.0s' $(seq 1 "$1")); }
p() { echo "${I}$1"; }

# A GUI bool: does variable <1> equal <2>?
veq() { echo "EqualTo_CFixedPoint( GetPlayer.MakeScope.Var('$1').GetValue, '(CFixedPoint)$2' )"; }
# Run scripted GUI <1> with the player as root.
sgui() { echo "[GetScriptedGui('$1').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"; }

# A radio that writes <field> = <value> to <node>, and lights up when it holds.
# The two onclick lines are the whole trick: GUI cannot hand script a number, so
# the first points the cursor at the node and the second writes the value.
# Vanilla stacks onclick this way (tournament_widget_types.gui:281-283); it runs
# them in order. Bracket chaining "[A][B]" is not a thing - do not try it.
emit_radio() { local depth=$1 node=$2 code=$3 field=$4 value=$5 loc=$6 tt=${7:-}
	ind "$depth"
	p "button_radio_label = {"
	ind $((depth+1))
	p "layoutpolicy_horizontal = expanding"
	p "onclick = \"$(sgui "leo_mvd_focus_${node}")\""
	p "onclick = \"$(sgui "leo_mvd_set_${field}_${value}")\""
	[ -n "$tt" ] && p "tooltip = \"$tt\""
	p "blockoverride \"radio\" {"
	ind $((depth+2)); p "frame = \"[BoolTo1And2( $(veq "leo_mvd_${node}_${field}" "$(tok_value "$value")") )]\""
	ind $((depth+1)); p "}"
	p "blockoverride \"text\" {"
	ind $((depth+2)); p "text = \"$loc\""
	ind $((depth+1)); p "}"
	ind "$depth"; p "}"
}

# One node's editor. leaf nodes cannot branch, so they get no condition option.
emit_node() { local depth=$1 prio=$2 n=$3 level=$4
	local node="r${prio}_n${n}" code=$((prio*10+n))
	local kinds="0 1 2"; [ "$level" -ge 2 ] && kinds="0 1"

	for k in $kinds; do
		emit_radio "$depth" "$node" "$code" kind "$k" "leo_mvd_ui_kind_$k" "leo_mvd_ui_kind_${k}_tt"
	done

	# Assign a Directive
	ind "$depth"; p ""
	p "vbox = {"
	ind $((depth+1))
	p "visible = \"[$(veq "leo_mvd_${node}_kind" 1)]\""
	p "layoutpolicy_horizontal = expanding"
	p "margin_left = 16"
	p "spacing = 2"
	for d in $DIRS; do
		emit_radio $((depth+1)) "$node" "$code" dir "$d" "leo_mvd_ui_dir_$d"
	done
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
	for c in $CONDS; do
		emit_radio $((depth+1)) "$node" "$code" cond "$c" "leo_mvd_ui_cond_$c"
	done

	# Its threshold, if it takes one. Only the chosen condition's list shows.
	for c in $NUMERIC_CONDS; do
		ind $((depth+1)); p ""
		p "vbox = {"
		ind $((depth+2))
		p "visible = \"[$(veq "leo_mvd_${node}_cond" "$c")]\""
		p "layoutpolicy_horizontal = expanding"
		p "margin_left = 16"
		p "spacing = 2"
		for t in $(cond_thresh "$c"); do
			emit_radio $((depth+2)) "$node" "$code" thresh "$t" "leo_mvd_ui_thresh_c${c}_${t}"
		done
		ind $((depth+1)); p "}"
	done
	ind "$depth"; p "}"

	# Its branches. Only rendered once this node is actually a condition, so an
	# unused level costs the player nothing to look at.
	local kids; kids=$(node_children "$n")
	local kt kf; kt=$(echo "$kids" | cut -d' ' -f1); kf=$(echo "$kids" | cut -d' ' -f2)
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
		emit_node $((depth+1)) "$prio" "$kid" $((level+1))
	done
	ind "$depth"; p "}"
}

### The panel.

# A GUI bool: is variable <1> at least <2>?
vge() { echo "GreaterThanOrEqualTo_CFixedPoint( GetPlayer.MakeScope.Var('$1').GetValue, '(CFixedPoint)$2' )"; }

emit_preset_radio() { local n=$1
	ind 7
	p "button_radio_label = {"
	ind 8
	p "layoutpolicy_horizontal = expanding"
	p "onclick = \"$(sgui "leo_mvd_preset_${n}")\""
	p "tooltip = \"leo_mvd_ui_preset_${n}_tt\""
	p "blockoverride \"radio\" {"
	ind 9; p "frame = \"[BoolTo1And2( $(veq leo_mvd_preset "$n") )]\""
	ind 8; p "}"
	p "blockoverride \"text\" {"
	ind 9; p "text = \"leo_mvd_ui_preset_${n}\""
	ind 8; p "}"
	ind 7; p "}"
}

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
### scrolls instead of overflowing), and a fixed action-button footer. Each
### settings group is a collapsible fold-out section (BindFoldOutContext +
### button_expandable_toggle_field + visible = PdxGuiFoldOut.IsUnfolded),
### matching the vanilla Subjects tab's collapsible vassal categories.
###
### A radio's selected state is read straight out of the script variable it
### represents - EqualTo_CFixedPoint against Var(...).GetValue - rather than
### through a scripted GUI's is_shown. Only clicking one runs script, so the
### panel costs no per-frame script evaluation however many radios it grows.
### Note that .GetValue yields a CFixedPoint, so literals must be written in
### the cast-and-quoted form '(CFixedPoint)1'.

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

	state = {
		name = _hide
		using = Animation_FadeOut_Quick
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

					### Automation section (collapsible).
					vbox = {
						layoutpolicy_horizontal = expanding
						oncreate = "[BindFoldOutContext]"
						oncreate = "[PdxGuiFoldOut.Unfold]"

						button_expandable_toggle_field = {
							blockoverride "text" {
								text = "leo_mvd_ui_heading_automation"
							}
						}

						### The checkbox reflects a scripted GUI's is_shown as its
						### checked state and runs its effect on click. It is
						### expanding so its content left-aligns.
						vbox = {
							visible = "[PdxGuiFoldOut.IsUnfolded]"
							layoutpolicy_horizontal = expanding
							margin = { 12 4 }
							spacing = 4

							button_checkbox_label = {
								layoutpolicy_horizontal = expanding
								onclick = "[GetScriptedGui('leo_mvd_toggle_auto').Execute( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
								enabled = "[GetScriptedGui('leo_mvd_toggle_auto').IsValid( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
								tooltip = "leo_mvd_ui_auto_tt"
								blockoverride "checkbox" {
									checked = "[GetScriptedGui('leo_mvd_toggle_auto').IsShown( GuiScope.SetRoot( GetPlayer.MakeScope ).End )]"
								}
								blockoverride "text" {
									text = "leo_mvd_ui_auto"
								}
							}
						}
					}

					### Preset section (collapsible). One radio per built-in rule
					### set; clicking one loads it, replacing the rules in place.
					### None is selected by default - the mod assigns nothing
					### until a rule set is chosen. Custom keeps whatever rules
					### are loaded and opens them for editing below.
					vbox = {
						layoutpolicy_horizontal = expanding
						oncreate = "[BindFoldOutContext]"
						oncreate = "[PdxGuiFoldOut.Unfold]"

						button_expandable_toggle_field = {
							blockoverride "text" {
								text = "leo_mvd_ui_heading_preset"
							}
						}

						vbox = {
							visible = "[PdxGuiFoldOut.IsUnfolded]"
							layoutpolicy_horizontal = expanding
							margin = { 12 4 }
							spacing = 2

HEAD

	for n in 0 1 2 3 4 5; do emit_preset_radio "$n"; echo; done

cat << 'MID'
						}
					}
MID

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
		p "margin = { 12 4 }"
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

### The scripted GUIs the panel's radios call.

emit_sguis() {
cat << 'HEAD'
# Leo VI's Mass Vassal Directives - rule editor scripted GUIs
#
# GENERATED by tools/gen_panel.sh - edits here will be overwritten.
#
# A radio click runs two of these in order: a focus, which points the cursor at
# the node being edited, then a set, which writes one field to it. That split is
# what keeps this file to one entry per node plus one per option, instead of one
# per node-and-option pair - GUI cannot hand script a number, so the node cannot
# simply be an argument.
#
# None of these need is_shown: a radio reads its selected state straight from
# the variable it represents.
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
	echo "### Conditions."
	for c in $CONDS; do
		echo "leo_mvd_set_cond_${c} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = { leo_mvd_edit_effect = { FIELD = 2 VALUE = $c } }"
		echo "}"
	done

	echo
	echo "### Thresholds. Shared by value across conditions; only the labels differ."
	for t in $(all_thresh_tokens); do
		echo "leo_mvd_set_thresh_${t} = {"
		echo -e "\tscope = character"
		echo -e "\teffect = { leo_mvd_edit_effect = { FIELD = 3 VALUE = $(tok_value "$t") } }"
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
	echo " leo_mvd_ui_kind_0_tt: \"Do nothing here. The [vassal|E] falls through to the next priority.\\n\\n#weak On the last priority this leaves them without a [directive|E].#!\""
	echo " leo_mvd_ui_kind_1: \"Assign a Directive\""
	echo " leo_mvd_ui_kind_1_tt: \"Give the [vassal|E] a [directive|E].\\n\\n#weak Vassals who cannot be given it - the game's own rules still apply - fall through to the next priority instead.#!\""
	echo " leo_mvd_ui_kind_2: \"Check a Condition\""
	echo " leo_mvd_ui_kind_2_tt: \"Test something about the [vassal|E] and act on the answer.\""
	echo
	echo " leo_mvd_ui_branch_true: \"If True\""
	echo " leo_mvd_ui_branch_false: \"If False\""
	echo
	for d in $DIRS; do
		echo " leo_mvd_ui_dir_${d}: \"\$$(dir_loc "$d")\$\""
	done
	echo
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
