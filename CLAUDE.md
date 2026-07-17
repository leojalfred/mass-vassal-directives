# Working on this mod

A CK3 **1.19.x** mod that assigns vassal directives from a rule set the player writes. Read `README.md` first for what it does; this file is how to change it without breaking it.

## Hard rules

- **Never touch anything outside this directory.** The game folder (`C:\Games\Steam\steamapps\common\Crusader Kings III`) is read-only reference. Never modify it.
- **Directive eligibility must stay exactly vanilla.** The mod automates what a player could already do by hand — never more. If a change would let a rule reach a state vanilla forbids, it's wrong. There is exactly one deliberate deviation, documented at `leo_mvd_gate_raid_innovation_intent_trigger`.
- **`README.md` must never mention AI or Claude.** Neither must anything else user-facing.
- **Never reference implementation phases, sessions, or process in comments.** Comments are for someone who has only ever seen the code.
- **Research the [wiki](https://ck3.paradoxwikis.com/Modding) first**, then the wider web, then the game files. The wiki usually answers faster than reverse-engineering `game/gui/*.gui`. Don't guess — this codebase is full of things that look impossible and aren't, and vice versa.

## The panel is generated

`gui/leo_mvd_panel.gui` (~25k lines), `common/scripted_guis/leo_mvd_edit.txt` and `localization/english/leo_mvd_ui_l_english.yml` are **output**. Edit `tools/gen_panel.sh` and re-run it:

```
bash tools/gen_panel.sh        # ~35s
```

That includes layout tweaks — margins and the window skeleton live in the generator too. It builds to a temp dir, brace-checks, and only then moves files into place, so a failed run leaves the real ones alone.

Why generated: the editor is the same widgets repeated per node, differing only in the variable they bind to, and GUI cannot factor that out — `blockoverride` cannot parameterize a variable name inside a binding.

## Localization

The mod ships every language CK3 officially supports (english, french, german, spanish, russian, korean, simp_chinese, japanese, polish). English is the source of truth: `localization/english/leo_mvd_l_english.yml` is hand-written, `leo_mvd_ui_l_english.yml` is generated. The others live in `localization/<lang>/leo_mvd_l_<lang>.yml` and `leo_mvd_ui_l_<lang>.yml` and are **machine-generated, then hand-maintained** — the generator only ever writes the English UI file, so translations are never regenerated for you.

**Whenever you change an English localization value, update every translated file to match** — same keys in the same order, the changed value re-translated. This applies to the static file *and* the generated UI file (its translations are hand-maintained too). Keep the CK3 markup identical across languages: concept links `[x|E]`, `$refs$`, `@icon!` tokens, `[recipient.GetX]` calls, `#weak`/`#V` … `#!` codes, and `\n` are never translated — only the prose between them. In user-facing text the translations are described as **machine-generated**, never "AI" (see Hard rules).

## Four limits that explain the whole design

Every odd-looking decision here follows from one of these. All confirmed, none guessable from the code:

1. **Scripted effects cannot recurse.** So the rule tree is capped at two levels of conditions and the walk is unrolled by hand, one effect per level (`leo_mvd_eval_root_effect` → `_mid_` → `_leaf_`).
2. **A variable name cannot be built at runtime.** `$X$` is a parse-time text macro. So rules live in fixed node slots reached by macro expansion with literal names — hence the hand-written 63-way dispatch in `leo_mvd_write_field_effect`.
3. **A condition cannot be chosen at runtime.** So the condition and directive chains are written **once** and driven by a value staged into a temporary scope (`scope:leo_mvd_cond_id`, `scope:leo_mvd_thresh`, `scope:leo_mvd_dir_id`), rather than duplicated into all 63 nodes.
4. **GUI cannot pass a number to script.** Only `GuiScope.SetRoot` and `AddScope` exist, both scope-only. So choosing an option runs **two scripted GUIs in order**: a focus that points `leo_mvd_edit_node` at the node, then a set that writes to whatever it points at.

## GUI facts worth not rediscovering

- **Reading script state needs no scripted GUI.** `.Var('x').GetValue` is a **CFixedPoint**: `EqualTo_CFixedPoint( GetPlayer.MakeScope.Var('x').GetValue, '(CFixedPoint)5' )`. Literals must be cast-and-quoted. Drives `visible`, and `frame` via `BoolTo1And2`.
- **A label can be built from a value**: `Localize(Concatenate('prefix_', IntToString(FixedPointToInt(Var('x').GetValue))))`. This is what makes the dropdowns affordable. **Every value a variable can hold needs a key** — including `0`, which is what an unset node reads.
- **Multiple `onclick` lines work and run in order.** `"[A][B]"` chaining does not exist.
- **No floating popups.** Draw order is tree order, there's no z-index for non-window widgets, and no datafunction returns a widget's position. Dropdowns open in flow. Don't retry this; see the generator's comment.
- **`margin` is padding inside a widget**, and an expanding widget is still stretched to its parent's width — to make a box narrower, put the inset on a parent. A hidden widget takes no space.
- **All `.txt`/`.gui`/`.yml` need a UTF-8 BOM. `descriptor.mod` must NOT have one.**

## Adding things

- The vanilla is_shown mirror lives once, in `leo_mvd_directive_shown_trigger` - both the rules and the exempt interaction call it. Keep it that way.
- **A condition** — add to `leo_mvd_cond_holds_trigger` (the chain, keyed on `scope:leo_mvd_cond_id`), then `CONDS`/`cond_name` in the generator. If it takes a number, also `NUMERIC_CONDS`, `cond_thresh`, `cond_default_thresh`, `thresh_label`. Guard anything that changes scope with `exists`. Add it to `NOMAD_CONDS` unless a nomad could never answer yes. A condition whose meaning is not obvious from its label can carry an explanatory tooltip via `cond_tt` (only Military Strength does, for its tier scaling).
- **A directive**: a gate trigger mirroring its vanilla `send_option`, a branch in `leo_mvd_try_assign_effect`, a case in `leo_mvd_managed_matches_trigger`, an inline icon in `gui/leo_mvd_texticons.gui`, and `dir_icon`/`dir_name`/`DIRS` in the generator. For the dimmed exempt marker, also add a twin to both functions in `common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt`, with its `leo_mvd_x_*` loc keys and gray texticon.
- **DLC-gated content** — if a condition or directive only exists with a DLC (administrative → `roads_to_power`, nomad → `khans_of_the_steppe`), add it to `cond_dlc_vis`/`dir_dlc_vis` so the panel hides it without that DLC, and branch any preset that uses it on `has_dlc_feature` so the preset loads an alternative (see `leo_mvd_preset_1/3/4_effect`). Use `roads_to_power`, **not** `admin_gov` — the latter does not track DLC ownership. The nomad section is gated as a block in `emit_waterfall`, so nomad directives need no per-row entry. Nothing here changes eligibility: the gated content already evaluates false without its DLC, so this is only to keep the panel and presets tidy.
- **A preset** — a `leo_mvd_preset_N_effect` (rule data, not logic), an sgui, loc for its name and `_tt`, and the dropdown's range in `emit_panel`.
- **More priorities** — raise `PRIORITIES` in the generator *and* extend `leo_mvd_write_field_effect`, the clear/backup/copy effects, and `leo_mvd_evaluate_vassal_effect`.

## Verifying

There are no automated tests; the game is the test. Before handing back:

```
bash tools/gen_panel.sh
# BOM + braces on every file; then check that every scripted GUI, loc key,
# effect and trigger the panel names actually exists - including the keys
# built at runtime by Concatenate, which nothing else will catch.
```

Then have the user run it with `-debug_mode` and watch `logs/error.log` for `leo_mvd`. `reload gui` refreshes the panel live; structural changes may need a restart.

**Things static checks cannot catch, so ask for them to be tested:** anything reached only by a macro-built name; a loc key built at runtime; whether a directive thrashes month to month (assign, advance, confirm it stays).

## Conventions

- Prefix everything `leo_mvd_`.
- Directive codes 1-9 settled, 10-13 nomad, 0 = none. They appear in `leo_mvd_managed`, node `dir` variables, and loc key suffixes. Keep them aligned.
- Scripted GUIs: `is_shown` = checked/selected state, `is_valid` = enabled, `effect` = onclick. Controls that read their own state from a variable need no entry at all.
- Comments say **why**, not what. The what is readable; the why is usually "the script language wouldn't let me do the obvious thing".
- **Text style.** Anything user-facing (game loc, `README.md`, the Workshop description) uses American spelling (recognize, gray, behavior, color, not recognise/grey/behaviour/colour) and no em-dash or spaced-hyphen separators between clauses. End the sentence and start a new one, or use a colon, parentheses, or a comma where that reads better. Genuine compound hyphens stay (quality-of-life, off-faith, duchy-tier). Hold comments and identifiers to the same spelling so the codebase stays consistent (`leo_mvd_gray_*`, not `grey`).
