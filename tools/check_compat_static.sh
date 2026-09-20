#!/usr/bin/env bash
# Static compatibility check.
#
# Every vanilla (and A Game of Thrones) name this mod leans on, asserted against
# the installed game files. Run it after a CK3 or AGOT patch: if Paradox renamed
# or removed something the mod mirrors, a line here turns FAIL and points at what
# broke, instead of finding out from a player.
#
#   bash tools/check_compat_static.sh
#   GAME_DIR=/path/to/game AGOT_DIR=/path/to/agot bash tools/check_compat_static.sh
#
# Two kinds of check. A "def" is strong: a specific definition must exist in a
# specific corner of the game files, and a miss is a FAIL. A "use" is a proxy for
# an engine built-in that has no definition file (a trigger like
# max_military_strength, a datafunction like GetScriptedGui): the best a file
# scan can do is confirm vanilla still references it, so a miss is a WARN worth a
# look, not a certain break.
#
# This checks names, not behavior. A name that still exists but changed meaning
# (a directive's eligibility, a rebalanced value, a reworked HUD that hides the
# panel) passes here and is caught only by the real-mod smoke test in CLAUDE.md's
# "Verifying" section. Run both after a patch.
#
# Exit status is non-zero if any def FAILs. WARNs do not fail the run.
set -uo pipefail

GAME="${GAME_DIR:-C:/Games/Steam/steamapps/common/Crusader Kings III/game}"
AGOT="${AGOT_DIR:-C:/Games/Steam/steamapps/workshop/content/1158310/2962333032}"
TFE="${TFE_DIR:-C:/Games/Steam/steamapps/workshop/content/1158310/2243307127}"

P=0; F=0; W=0
FAILS=""

_g() { grep -rqsE -- "$2" "$1" 2>/dev/null; }          # <path> <regex>

def()  { # <label> <subdir under GAME> <regex>   strong, FAIL on miss
	if _g "$GAME/$2" "$3"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  FAIL  %s\n' "$1"; F=$((F+1)); FAILS="$FAILS\n  - $1"; fi
}
adef() { # <label> <subdir under AGOT> <regex>   strong (AGOT), FAIL on miss
	if _g "$AGOT/$2" "$3"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  FAIL  %s\n' "$1"; F=$((F+1)); FAILS="$FAILS\n  - $1"; fi
}
tdef() { # <label> <subdir under TFE> <regex>   strong (TFE), FAIL on miss
	if _g "$TFE/$2" "$3"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  FAIL  %s\n' "$1"; F=$((F+1)); FAILS="$FAILS\n  - $1"; fi
}
# A file TFE must NOT override, because the opener borrows what vanilla keeps
# there: button_give_directive from shared/buttons_icons.gui, and the
# mass_directives keybind from shortcuts.shortcuts.
tabsent() { # <label> <path under TFE>
	if [ -e "$TFE/$2" ]; then printf '  warn  %s (TFE now ships this file - re-check the opener against it)\n' "$1"; W=$((W+1))
	else printf '  ok    %s\n' "$1"; P=$((P+1)); fi
}
use()  { # <label> <regex>                        proxy, WARN on miss
	if _g "$GAME/common" "$2" || _g "$GAME/events" "$2"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  warn  %s (vanilla no longer references it - verify by hand)\n' "$1"; W=$((W+1)); fi
}
guse() { # <label> <regex>                        proxy against GUI, WARN on miss
	if _g "$GAME/gui" "$2"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  warn  %s (vanilla GUI no longer uses it - verify by hand)\n' "$1"; W=$((W+1)); fi
}
# A "name = {" block definition (a scripted trigger/effect, on_action, custom-loc
# function, pillar). The (^|[^a-z_]) prefix tolerates a leading BOM when the
# definition is line 1 of its file, and stops a longer identifier ending in the
# same name from matching; "= [{]" pins it to the definition, not a comment.
defd()  { # <label> <subdir under GAME> <name>   strong, FAIL on miss
	if _g "$GAME/$2" "(^|[^a-z_])$3 = [{]"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  FAIL  %s\n' "$1"; F=$((F+1)); FAILS="$FAILS\n  - $1"; fi
}
adefd() { # <label> <subdir under AGOT> <name>   strong (AGOT), FAIL on miss
	if _g "$AGOT/$2" "(^|[^a-z_])$3 = [{]"; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  FAIL  %s\n' "$1"; F=$((F+1)); FAILS="$FAILS\n  - $1"; fi
}
# A file that must exist (a texture the mod's texticons pull from vanilla).
deff()  { # <label> <path under GAME>            strong, FAIL on miss
	if [ -f "$GAME/$2" ]; then printf '  ok    %s\n' "$1"; P=$((P+1))
	else printf '  FAIL  %s\n' "$1"; F=$((F+1)); FAILS="$FAILS\n  - $1"; fi
}

[ -d "$GAME" ] || { echo "game not found at: $GAME" >&2; echo "set GAME_DIR to your install." >&2; exit 2; }
echo "game: $GAME"

echo
echo "== Vanilla: directives the mod assigns and clears =="
# The 13 vanilla directive flags. Set by give_vassal_directive_interaction, so if
# a directive were removed its flag would stop appearing in that folder.
for d in convert_faith convert_culture improve_development train_commanders \
         build_maa improve_cultural_acceptance building_focus_fortification \
         building_focus_military building_focus_economy manage_fertility \
         explore_cultures raid_innovation_intent raid_herd_intent; do
	# The setter, not the bare name: a comment mentioning a removed directive
	# must not keep this green.
	def "directive flag: vassal_directive_$d" common/character_interactions "add_character_flag = vassal_directive_$d"
done
def "interaction: give_vassal_directive_interaction" common/character_interactions "give_vassal_directive_interaction = [{]"
defd "clear effect: remove_vassal_directives" common/scripted_effects remove_vassal_directives

echo
echo "== Vanilla: scripted triggers the mod calls =="
for t in vassal_is_valid_and_follows_directive_trigger \
         vassal_follows_directive_trigger vassal_follows_directive_valid_trigger \
         is_physically_able is_governor; do
	defd "scripted trigger: $t" common/scripted_triggers "$t"
done

echo
echo "== Vanilla: administration types (Administration Type condition) =="
# Every administrative government sets one of these on a governor's contract.
# The condition matches by name across all of them, so a rename in any one set
# silently drops that government's governors out of the rules that ask for it.
for th in balanced civilian military frontier imperial naval; do
	def "contract theme flag: admin_theme_$th" common/subject_contracts "flag = admin_theme_$th"
done
for pt in standard industrial metropolitan military protectorate; do
	def "contract flag: celestial_province_$pt" common/subject_contracts "flag = celestial_province_$pt"
done
for pt in standard industrial military; do
	def "contract flag: meritocratic_province_$pt" common/subject_contracts "flag = meritocratic_province_$pt"
done
# Ritsuryo's industrial type carries a flag named for trade, which is why the
# panel offers it under one name and matches it under another.
for pt in standard trade military; do
	def "contract flag: japan_administrative_province_$pt" common/subject_contracts "flag = japan_administrative_province_$pt"
done

echo
echo "== Vanilla: the governments each administration-type set belongs to =="
# leo_mvd_admin_family_*_trigger names these outright. A government renamed here
# means its player is offered no types at all, and the preset silently vanishes.
for g in administrative_government celestial_government meritocratic_government \
         steppe_admin_government japan_administrative_government; do
	# Unanchored on the left: a government defined on a file's first line is
	# preceded by the UTF-8 BOM, which an anchored match would not see past.
	def "government: $g" common/governments "(^|[^a-z_])$g = [{]"
done

echo
echo "== Vanilla: government features the mod branches on =="
# .txt only: _governments.info carries a doc comment "( administrative = yes )"
# that would otherwise keep this green after the feature were removed.
if grep -rqsE --include=*.txt -- "administrative = yes" "$GAME/common/governments" 2>/dev/null; then
	printf '  ok    government feature: administrative\n'; P=$((P+1))
else printf '  FAIL  government feature: administrative\n'; F=$((F+1)); FAILS="$FAILS\n  - government feature: administrative"; fi
# These are listed one per line inside a government's flags block, so match the
# token alone on its line: a usage (government_has_flag = ...) or a doc comment
# has other text on the line and will not.
def "government flag: government_is_nomadic"  common/governments "^[[:space:]]*government_is_nomadic[[:space:]]*$"
def "government flag: government_is_herder"   common/governments "^[[:space:]]*government_is_herder[[:space:]]*$"

echo
echo "== Vanilla: the exempt-dimming override targets (must exist to override) =="
# The mod redefines these two by name so an exempt vassal's icon dims. If vanilla
# stops defining them, the override has nothing to win against and the game's own
# display assumptions may have changed.
defd "custom loc: vassal_directive_icon" common/customizable_localization vassal_directive_icon
defd "custom loc: vassal_directive_text" common/customizable_localization vassal_directive_text

echo
echo "== Vanilla: the hooks the mod attaches to =="
defd "on_action: on_game_start_after_lobby" common/on_action on_game_start_after_lobby
defd "on_action: on_death"                  common/on_action on_death
defd "on_action: yearly_playable_pulse"     common/on_action yearly_playable_pulse
def "panel toggle variable: mass_directives_window" gui "Toggle\( *'mass_directives_window' *\)"
def "gui datafunction: GetPlayer.IsValid"          gui "GetPlayer\.IsValid"

echo
echo "== Vanilla: DLC feature names (no definition file; matched against use) =="
def "dlc feature: roads_to_power"      common/scripted_triggers "has_dlc_feature = roads_to_power"
def "dlc feature: all_under_heaven"    common/scripted_triggers "has_dlc_feature = all_under_heaven"
def "dlc feature: khans_of_the_steppe" common/scripted_triggers "has_dlc_feature = khans_of_the_steppe"

echo
echo "== Vanilla: engine built-in triggers (proxy: still used by vanilla) =="
for t in is_powerful_vassal_of is_councillor_of max_military_strength \
         vassal_contract_has_flag highest_held_title_tier development_level \
         cultural_acceptance has_dynasty government_allows government_has_flag \
         any_sub_realm_county any_held_county any_held_title every_held_title \
         capital_county opinion save_temporary_scope_value_as; do
	use "trigger: $t" "\b$t\b"
done
for c in tier_county tier_duchy tier_kingdom tier_empire; do
	use "tier constant: $c" "\b$c\b"
done

echo
echo "== Vanilla: GUI datafunctions the panel relies on (proxy: still used in vanilla GUI) =="
# The load-bearing, less-common ones. The everyday ones (And/Or/Not, GetPlayer)
# are not worth listing - if those vanished the whole game UI would be down.
for fn in GetScriptedGui GetVariableSystem 'MakeScope' 'GetList' 'GetFlagName' \
          Concatenate Localize IntToString FixedPointToInt \
          EqualTo_CFixedPoint NotEqualTo_CFixedPoint GreaterThanOrEqualTo_CFixedPoint \
          Select_CString Select_float SelectLocalization HasDlcFeature \
          BindFoldOutContext; do
	guse "datafunction: $fn" "$fn"
done

echo
echo "== Vanilla: display bits (cosmetic; a miss degrades looks, not function) =="
# Game concepts the panel links with [x|E]. Matched as a concept key or as an
# alias member, so common words in prose do not give a false pass.
for c in faith culture cultures dynasty house administrative government \
         governor baron \
         powerful_vassal council title development opinion county counties \
         cultural_acceptance men_at_arms fortification_buildings \
         military_buildings economic_buildings vassal vassals directive \
         directives nomad duchy kingdom empire raid_intent innovations herd \
         county_fertility; do
	# "$c = {" (a concept key) or membership in an "alias = { ... }". The key form
	# is left-bounded by (^|[^a-z_]) so development is not falsely satisfied by
	# county_development = {, while still tolerating a leading BOM on line 1.
	if _g "$GAME/common/game_concepts" "(^|[^a-z_])$c = [{]|alias = [{][^}]*\b$c\b"; then
		printf '  ok    game concept: %s\n' "$c"; P=$((P+1))
	else
		printf '  warn  game concept: %s (not found as key/alias - verify)\n' "$c"; W=$((W+1))
	fi
done
for th in balanced civilian military frontier imperial naval; do
	def "theme loc key: admin_theme_$th" localization/english "^ *admin_theme_$th:"
done
# The other sets' names, which the option labels reach through
# leo_mvd_admin_type_loc.txt. A missing key shows as a raw key in the picker.
for k in celestial_province_standard celestial_province_industrial \
         celestial_province_metropolitan celestial_province_military \
         celestial_province_protectorate meritocratic_province_standard \
         meritocratic_province_industrial meritocratic_province_military \
         japan_administrative_province_standard japan_administrative_province_trade \
         japan_administrative_province_military; do
	def "administration type loc key: $k" localization/english "^ *$k:"
done
# The words for the mechanic itself, per government, as concept keys.
for k in theme_administration circuit_administration province_administration \
         theme circuit province; do
	def "concept loc key: game_concept_$k" localization/english "^ *game_concept_$k:"
done
def "text color: color_gray" gui "name = color_gray"

echo
echo "== Vanilla: loc keys the exempt-dimming override reuses =="
# zz_leo_mvd_vassal_directive_loc.txt overrides vassal_directive_icon/text
# wholesale and its non-exempt path points at these vanilla keys. Because the
# override loads last and wins, a rename of any of them breaks the directive
# icon or text for EVERY vassal, not just exempt ones.
for k in no_directive_icon directive_refusal_icon no_directive_text \
         refusing_directive_text blank_line county_fertility_text culture_text \
         herd_text convert_faith_icon convert_faith_text convert_culture_icon \
         convert_culture_text improve_development_icon improve_development_text \
         train_commanders_icon train_commanders_text build_maa_icon build_maa_text \
         improve_cultural_acceptance_icon improve_cultural_acceptance_text \
         building_focus_fortification_icon building_focus_fortification_text \
         building_focus_military_icon building_focus_military_text \
         building_focus_economy_icon building_focus_economy_text \
         manage_fertility_icon explore_cultures_icon explore_cultures_text \
         raid_innovation_intent_icon raid_herd_intent_icon; do
	def "loc key: $k" localization/english "^ *$k:"
done

echo
echo "== Vanilla: textures the mod's directive texticons pull from =="
for tex in vassal_directives/no_directive vassal_directives/refusal \
           vassal_directives/convert_faith vassal_directives/promote_culture \
           vassal_directives/improve_development \
           vassal_directives/improve_cultural_acceptance \
           vassal_directives/boost_men_at_arms vassal_directives/recruit_men_at_arms \
           vassal_directives/construct_fortification_buildings \
           vassal_directives/construct_military_buildings \
           vassal_directives/construct_economic_buildings \
           icon_county_fertility icon_herd \
           council_task_types/task_kurultai_culture message_feed/culture; do
	deff "texture: $tex.dds" "gfx/interface/icons/$tex.dds"
done

echo
echo "== Vanilla: GUI templates the panel builds on =="
for tpl in Window_Background_Subwindow Background_DropDown Animation_FadeIn_Quick \
           Animation_FadeOut_Quick; do
	def "template: $tpl" gui "\b$tpl\b"
done
for ty in button_normal button_standard text_single text_label_left \
          header_pattern scrollbox; do
	def "widget type: $ty" gui "type $ty ="
done

# ---- AGOT ----
if [ -d "$AGOT" ]; then
	echo
	echo "agot: $AGOT"
	echo "== AGOT: Westeros conditions =="
	# No ^ anchor on the religions: each is defined on line 1 of its file, right
	# after the UTF-8 BOM, which a ^ would sit in front of. "= {" pins it to the
	# definition rather than a religion_tag = ... usage elsewhere.
	adefd "cultural pillar: heritage_ironman" common/culture/pillars heritage_ironman
	adef "religion: the_seven_religion"      common/religion "the_seven_religion = [{]"
	adef "religion: the_pact_religion"       common/religion "the_pact_religion = [{]"
	adef "religion: the_rhllor_religion"     common/religion "the_rhllor_religion = [{]"

	echo
	echo "== AGOT: Settle the Wilderness directive =="
	adef "directive flag: vassal_directive_settle_wilderness" common/character_interactions "vassal_directive_settle_wilderness"
	adef "colonization on_action reads the flag" common/on_action "vassal_directive_settle_wilderness"
	adef "loc: settlement_focus_text"  localization "settlement_focus_text:"
	adef "loc: settle_wilderness_icon" localization "settle_wilderness_icon:"
	adef "texticon: directive_wilderness" gui "directive_wilderness"
	adef "game concept: wilderness" common/game_concepts "^[[:space:]]*wilderness ="

	echo
	echo "== AGOT: the override the mod must load after =="
	adefd "AGOT custom loc: vassal_directive_icon" common/customizable_localization vassal_directive_icon
	adefd "AGOT custom loc: vassal_directive_text" common/customizable_localization vassal_directive_text
else
	echo
	echo "agot: not found at $AGOT - skipping AGOT checks (set AGOT_DIR to include them)"
fi

if [ -d "$TFE" ]; then
	echo
	echo "tfe: $TFE"

	echo
	echo "== TFE: what the opener is attached to =="
	# TFE ships its own window_my_realm.gui with no mass directives button, which
	# is why dist/tfe adds one. The button shows itself on these two facts: the
	# realm window is open, and its Subjects tab is the active one. TFE sets a
	# variable per tab; if it went back to vanilla's single 'bookmark' variable,
	# or renamed the window, the opener would never appear.
	tdef "TFE realm window: my_realm_window"      gui "widgetid = \"my_realm_window\""
	tdef "TFE realm window: bookmark_subjects"    gui "bookmark_subjects"
	# The button borrows two vanilla widget types and vanilla's own shortcut. TFE
	# does not override the files holding them today; if it starts to, the opener
	# has to be re-checked against TFE's versions.
	tabsent "TFE leaves shared/buttons_icons.gui alone (button_give_directive)" gui/shared/buttons_icons.gui
	tabsent "TFE leaves shortcuts.shortcuts alone (mass_directives keybind)"    gui/shortcuts.shortcuts

	echo
	echo "== TFE: the directives themselves are still vanilla's =="
	# TFE overrides 00_vassal_interactions.txt but has so far kept the directive
	# interaction byte-identical. The mod's per-directive gates mirror vanilla's
	# send_options, so a TFE edit here would silently desync dist/tfe: directives
	# would be assigned and then dropped next tick.
	if [ -f "$TFE/common/character_interactions/00_vassal_interactions.txt" ]; then
		_blk() { awk '/^give_vassal_directive_interaction = \{/{on=1} on{print} on&&/^\}/{exit}' "$1"; }
		if diff -q <(_blk "$GAME/common/character_interactions/00_vassal_interactions.txt") \
		           <(_blk "$TFE/common/character_interactions/00_vassal_interactions.txt") >/dev/null 2>&1; then
			printf '  ok    TFE give_vassal_directive_interaction matches vanilla\n'; P=$((P+1))
		else
			printf '  FAIL  TFE give_vassal_directive_interaction differs from vanilla\n'
			F=$((F+1)); FAILS="$FAILS\n  - TFE give_vassal_directive_interaction differs from vanilla (re-diff the leo_mvd_gate_* triggers)"
		fi
	else
		printf '  ok    TFE does not override the directive interaction\n'; P=$((P+1))
	fi

	echo
	echo "== TFE: Roman administration types =="
	# roman_government uses Roads to Power's contract group, so its governors carry
	# the six themes; roman_imperial_government has three assignments of its own.
	tdef "TFE government: roman_government"          common/governments "(^|[^a-z_])roman_government = [{]"
	tdef "TFE government: roman_imperial_government" common/governments "(^|[^a-z_])roman_imperial_government = [{]"
	tdef "TFE contract flag: roman_imperial_civilian_assignment"  common/subject_contracts "flag = roman_imperial_civilian_assignment"
	tdef "TFE contract flag: roman_imperial_exarchate_assignment" common/subject_contracts "flag = roman_imperial_exarchate_assignment"
	# The Military assignment needs no value of its own because TFE sets vanilla's
	# theme flag on it, which value 3 already matches. If that stopped being true,
	# Roman military governors would silently stop matching Military.
	tdef "TFE military assignment still sets admin_theme_military" common/subject_contracts "flag = admin_theme_military"

	echo
	echo "== TFE: the exempt-dimming override has no rival =="
	# TFE does not define these, so the mod's by-name override wins wherever it
	# loads. If TFE starts defining them, dist/tfe must load after TFE.
	if _g "$TFE/common/customizable_localization" "(^|[^a-z_])vassal_directive_(icon|text) = [{]"; then
		printf '  warn  TFE now defines vassal_directive_icon/text - dist/tfe must load after TFE\n'; W=$((W+1))
	else
		printf '  ok    TFE defines neither vassal_directive_icon nor vassal_directive_text\n'; P=$((P+1))
	fi
else
	echo
	echo "tfe: not found at $TFE - skipping TFE checks (set TFE_DIR to include them)"
fi

echo
echo "----------------------------------------"
printf 'passed %s   failed %s   warnings %s\n' "$P" "$F" "$W"
if [ "$F" -gt 0 ]; then
	printf 'FAILED:%b\n' "$FAILS"
	echo "something the mod depends on is missing or renamed. investigate before shipping."
	exit 1
fi
[ "$W" -gt 0 ] && echo "warnings are engine built-ins vanilla no longer references; usually fine, worth a glance."
echo "all hard dependencies present."
