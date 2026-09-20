# Working on this mod

A CK3 **1.19.x** mod that assigns vassal directives from a rule set the player writes. Read `README.md` first for what it does; this file is how to change it without breaking it.

## Hard rules

- **Never touch anything outside this directory.** The game folder (`C:\Games\Steam\steamapps\common\Crusader Kings III`) and the A Game of Thrones mod (`C:\Games\Steam\steamapps\workshop\content\1158310\2962333032`) are read-only reference. Never modify either.
- **Directive eligibility must stay exactly vanilla.** The mod automates what a player could already do by hand — never more. If a change would let a rule reach a state vanilla forbids, it's wrong. There is exactly one deliberate deviation, documented at `leo_mvd_gate_raid_innovation_intent_trigger`.
- **`README.md` must never mention AI or Claude.** Neither must anything else user-facing.
- **Never reference implementation phases, sessions, or process in comments.** Comments are for someone who has only ever seen the code.
- **Research the [wiki](https://ck3.paradoxwikis.com/Modding) first**, then the wider web, then the game files. The wiki usually answers faster than reverse-engineering `game/gui/*.gui`. Don't guess — this codebase is full of things that look impossible and aren't, and vice versa.

## The panel is generated

Five files are **output** — never edit them, edit `tools/gen_panel.sh` and re-run it:

- `gui/leo_mvd_panel.gui` (~9.6k lines)
- `common/scripted_guis/leo_mvd_edit.txt`
- `localization/english/leo_mvd_ui_l_english.yml`
- `common/scripted_effects/leo_mvd_options.txt` — the option lists the dropdowns iterate
- `common/scripted_triggers/leo_mvd_options_ack.txt` — names those lists in script so the validator does not call them unused

```
bash tools/gen_panel.sh        # ~20s, refreshes the repo-root (vanilla) files
```

That includes layout tweaks — margins and the window skeleton live in the generator too. It builds to a temp dir, brace-checks, and only then moves files into place, so a failed run leaves the real ones alone. The generator is target-aware (`TARGET=vanilla|agot|tfe`, `OUTDIR=<dir>`); run bare like this it writes the vanilla files at the repo root, and `tools/build.sh` invokes it once per target (see below). After a generator change, run it bare to keep the committed repo-root files current, then run `build.sh` to produce and check all three mods.

Why generated: the editor is the same widgets repeated per node, differing only in the variable they bind to, and `blockoverride` cannot parameterize a variable name inside a binding.

**That rationale is only half true, and the half that is false matters.** `blockoverride` cannot do it, but a `datamodel` can: a GUI binding may build a variable name at runtime, so one `item` template can serve every node and every option (see "The limits that explain the design"). What genuinely cannot be factored out is the *script* side — `leo_mvd_write_field_effect`'s 63-way dispatch — because a script variable name really is parse-time. So the generator's remaining job is smaller than it looks, and repetition in the `.gui` is a cost, not a necessity: the panel is created at startup and its first-open hitch scales with widget count.

## Three mods from one source

The repo builds **three shippable mods** from shared source: `dist/vanilla/` (the base mod), `dist/agot/` (adapted for the A Game of Thrones total conversion) and `dist/tfe/` (adapted for The Fallen Eagle). `dist/` is gitignored and holds **game files only** — no tools, docs, or dev files — so each subfolder is ready to point the launcher at and upload to the Workshop. **Load and test from `dist/vanilla`, `dist/agot` and `dist/tfe`, never the repo root.** The root's committed generated files (panel, editor sgui, English UI loc) are the version-controlled copy of the *vanilla* output: `dist/` is gitignored, so keeping the root current (via `gen_panel.sh` run bare) is what makes generator changes show up as reviewable git diffs. The root is not a mod you load — its descriptor's `thumbnail.png` only exists once the build copies it into each dist.

```
bash tools/build.sh            # builds all three mods in parallel; -v narrates
```

There is **no runtime detection of either total conversion**. Everything that differs is applied at build time, the same three ways for both:

- **The panel** is regenerated in that mode. AGOT adds the `settle_wilderness` directive and the five Westeros conditions, drops the nomad section, and doubles the Military Strength ladder; TFE adds the Exarchate administration type and the Roman Imperial row (all keyed on `TARGET=agot` / `TARGET=tfe`).
- **Small fragments** are injected at `# @AGOT:...@` / `# @TFE:...@` markers in the base files listed in `MARKER_FILES`. AGOT's are the directive's dispatch, its ownership match, the five condition branches and two cust-loc entries; TFE's are its government family, two administration-type branches, its preset and its wording. **Every build strips the markers that are not its own**, so nothing target-specific can leak.
- **Target-only files** under `agot/files/` and `tfe/files/` are copied in verbatim, and that target's `descriptor.mod` replaces the base one. AGOT: its gate trigger, wilderness texticons, extra presets/sguis, the `leo_mvd_mil_baseline` override and the translated overlay loc. TFE: its opener widget, its family trigger and its overlay loc.

So a target's changes live in exactly three places: the generator's `TARGET=` branches, `<target>/fragments/*.txt` (injected), and `<target>/files/**` (copied). Base files carry only the inert markers. **Adding total-conversion content means editing one of those three, never adding a runtime `if AGOT` to a base file.** Eligibility stays exactly vanilla in all three builds; the deltas only surface content that conversion itself allows (AGOT's `settle_wilderness`, a feudal-safe directive; TFE's own locked administration types).

**TFE needs an opener, and that is the only reason the build exists.** TFE ships its own `window_my_realm.gui` whose Subjects tab has no mass directives button, and nothing in TFE sets the `mass_directives_window` variable the panel shows itself on. `tfe/files/gui/leo_mvd_tfe_opener.gui` is a standalone scripted widget that toggles that same variable, shown while `IsGameViewOpen('my_realm')` and TFE's own `bookmark_subjects` are both true, and clearing it on hide because TFE's window does not. It overrides no TFE file on purpose: a widget cannot be injected into another mod's file, and re-shipping TFE's 4600-line window would go stale and fight every other TFE submod.

## Localization

The mod ships every language CK3 officially supports (english, french, german, spanish, russian, korean, simp_chinese, japanese, polish). English is the source of truth: `localization/english/leo_mvd_l_english.yml` is hand-written, `leo_mvd_ui_l_english.yml` is generated. The others live in `localization/<lang>/leo_mvd_l_<lang>.yml` and `leo_mvd_ui_l_<lang>.yml` and are **machine-generated, then hand-maintained** — the generator only ever writes the English UI file, so translations are never regenerated for you.

**Whenever you change an English localization value, update every translated file to match** — same keys in the same order, the changed value re-translated. This applies to the static file *and* the generated UI file (its translations are hand-maintained too). Keep the CK3 markup identical across languages: concept links `[x|E]`, `$refs$`, `@icon!` tokens, `[recipient.GetX]` calls, `#weak`/`#V` … `#!` codes, and `\n` are never translated — only the prose between them. In user-facing text the translations are described as **machine-generated**, never "AI" (see Hard rules).

Total-conversion loc lives in overlay files, `agot/files/localization/<lang>/leo_mvd_agot_l_<lang>.yml` and `tfe/files/localization/<lang>/leo_mvd_tfe_l_<lang>.yml`, one per language, shipped only to that dist. **TFE ships English only**, so its overlay never points at a TFE key: a key borrowed from TFE would render raw in every other language, which is why the Exarchate's name and TFE's word for the mechanic are written out and translated here. English is split: the AGOT condition/directive/threshold labels come out of the generator (into the AGOT `leo_mvd_ui_l_english.yml`), while the exempt marker and the extra presets are hand-written in the English overlay. The **translated** overlays carry *both* sets — the generator only ever writes English, so every AGOT-specific key a non-English game needs must be hand-translated into its overlay (which is why the translated overlays hold more keys than the English one; repeating the generator's English keys there would just duplicate them). The build adds the BOM to every overlay loc file for you.

## The limits that explain the design

Every odd-looking decision here follows from one of these.

### Real, and they are script-side

1. **Scripted effects cannot recurse.** So the rule tree is capped at two levels of conditions and the walk is unrolled by hand, one effect per level (`leo_mvd_eval_root_effect` → `_mid_` → `_leaf_`).
2. **A *script* variable name cannot be built at runtime.** `$X$` is a parse-time text macro. So rules live in fixed node slots reached by macro expansion with literal names — hence the hand-written 63-way dispatch in `leo_mvd_write_field_effect`. This one is genuinely immovable, and it is why that dispatch has to exist at all. It is also the only reason left that anything is generated.
3. **A condition cannot be chosen at runtime.** So the condition and directive chains are written **once** and driven by a value staged into a temporary scope (`scope:leo_mvd_cond_id`, `scope:leo_mvd_thresh`, `scope:leo_mvd_dir_id`), rather than duplicated into all 63 nodes.
4. **GUI has no string comparison.** Only `Select_CString` (a selector) exists — there is no `IsEqual_CString` or equivalent anywhere in vanilla. So a datamodel item's identity, which is a string, can never be compared against a number held in a variable. Work around it by having script pre-build one list per case and letting GUI pick the list by name, rather than filtering rows in the GUI.

### Two former "limits" that are false, and were load-bearing for the generator

Both were verified wrong in game, with working probes. They are recorded here because the whole panel is generated on the strength of them, and anyone reading the old note would rebuild the same thing.

- **A variable name in a *GUI binding* CAN be built at runtime.** `Var()` and `GetList()` both accept a computed `CString`, not just a literal. Vanilla does it: `Story.MakeScope.Var( StoryCycleVariableVisualization.GetVariableName )` (`window_situation_list.gui:741`) and `GetList( ... GetVariableName )` (`:1071`). Combined with `Concatenate`, one widget can bind a different variable per datamodel item. The old note said `blockoverride` cannot parameterize a variable name inside a binding — that is true of `blockoverride` and irrelevant, because the answer is a datamodel, not `blockoverride`.
- **GUI CAN pass a number to script.** `MakeScopeValue`, `MakeScopeFlag` and `MakeScopeBool` exist alongside `AddScope`, and arrive script-side as `scope:name`. Verified working, despite having zero vanilla call sites. `GetScriptedGui()` also accepts a **computed** name, so an option row can dispatch to `leo_mvd_set_cond_5` without that string appearing anywhere in the file.

### What follows from that

A dropdown's options do not need to be literal widgets. Script keeps a `variable_list` of flags named after the loc-key suffix they carry, GUI iterates it with a `datamodel`, and one `item` template serves every option: the label is `Localize(Concatenate('leo_mvd_ui_', Scope.GetFlagName))` and the click is `GetScriptedGui(Concatenate('leo_mvd_set_', Scope.GetFlagName))`. Point the `datamodel` at a list name that was never created and the rows do not just hide, they **cease to exist** — which is how an unopened dropdown can cost nothing. DLC gating moves out of per-row `HasDlcFeature` bindings and into which entries script puts in the list.

## GUI facts worth not rediscovering

- **Reading script state needs no scripted GUI.** `.Var('x').GetValue` is a **CFixedPoint**: `EqualTo_CFixedPoint( GetPlayer.MakeScope.Var('x').GetValue, '(CFixedPoint)5' )`. Literals must be cast-and-quoted. Drives `visible`, and `frame` via `BoolTo1And2`.
- **A label can be built from a value**: `Localize(Concatenate('prefix_', IntToString(FixedPointToInt(Var('x').GetValue))))`. This is what makes the dropdowns affordable. **Every value a variable can hold needs a key** — including `0`, which is what an unset node reads.
- **Multiple `onclick` lines work and run in order.** `"[A][B]"` chaining does not exist.
- **No floating popups.** Draw order is tree order, there's no z-index for non-window widgets, and no datafunction returns a widget's position. Dropdowns open in flow. Don't retry this; see the generator's comment. (Vanilla's native `dropDown` widget, `gui/shared/lists.gui:755`, does position its own list — but its items come from a `datamodel`, so it only helps where the options are data.)
- **`margin` is padding inside a widget**, and an expanding widget is still stretched to its parent's width — to make a box narrower, put the inset on a parent. A hidden widget takes no space.
- **A widget that overflows its window still draws, but stops being clickable.** The window's input area ends at its own edge, so an over-long list looks fine and silently does nothing. Inside the panel the scrollbox clips instead, which is why this only bites on new windows.
- **An empty loc value renders no tooltip at all**, not an empty box. So a runtime-built tooltip key can exist for every option and simply be blank where there is nothing worth saying.
- **`visible = no` does not prevent instantiation, only rendering and layout.** The engine property `visible_at_creation` exists precisely because widgets are created while hidden. Hiding a subtree therefore saves nothing at load; only deleting it does.
- **The panel is created at game start, not on first open.** `gui/scripted_widgets/` means "create this widget on startup" (`_scripted_widgets.info`). So the first-open hitch is the first *layout and text-shaping* pass over the whole tree, which is why widget **count** is the thing that matters. The panel warms this off during the loading screen: it shows itself for a moment at creation (`alpha = 0` so it is unseen, `oncreate` sets a `leo_mvd_prewarm` variable), which pays the layout pass before the player is looking. Text shaping may be draw-gated, so the warm is only partial - it is cheap insurance on top of the widget reduction, not the fix.
- **The engine wipes GUI variables at the load-to-session transition.** This is what ends the pre-warm: `leo_mvd_prewarm` is set at widget creation and simply ceases to exist when the session begins, which is also before the player has mouse control. Handy (the pre-warm self-terminates and re-runs every session for free), but it means a GUI variable set at startup cannot be relied on to survive into play, and a `state` `delay` meant to outlast the transition will not - the wipe fires first.
- **`alwaystransparent` is a per-widget pass-through, not a subtree input blocker.** Vanilla only ever puts it on a leaf inside a button, so the *button* gets the click. On a container it does nothing useful: the children still take input. There is no property that makes a whole subtree ignore the mouse. To hide a window from input, move it off-screen or do not make it `visible`.
- **All `.txt`/`.gui`/`.yml` need a UTF-8 BOM. `descriptor.mod` must NOT have one.**
- **Script variables and flags that only GUI ever reads trip the validator.** `-debug_mode` logs "set but is never used", because it scans script only and does not count GUI or localization. Keep `error.log` clean by referencing them from a scripted trigger that something actually calls.

## Adding things

- The vanilla is_shown mirror lives once, in `leo_mvd_directive_shown_trigger` - both the rules and the exempt interaction call it. Keep it that way.
- **A condition** — add to `leo_mvd_cond_holds_trigger` (the chain, keyed on `scope:leo_mvd_cond_id`), then `CONDS`/`cond_name` in the generator. If it takes a number, also `NUMERIC_CONDS`, `cond_thresh`, `cond_default_thresh`, `thresh_label`. Guard anything that changes scope with `exists`. Add it to `NOMAD_CONDS` unless a nomad could never answer yes. A condition whose meaning is not obvious from its label can carry an explanatory tooltip via `cond_tt`; leave it out and the generator writes a blank tooltip key, which renders nothing. Everything else follows: the option list, the redundancy code, the blank tooltip and the setter scripted GUI are all generated from `CONDS`.
- **`CONDS` is also the panel's display order**, and it is deliberately not in numeric order — codes are append-only because they live in saved player variables, so a new condition takes the next free code and is then placed in the list wherever it reads best.
- **A directive**: a gate trigger mirroring its vanilla `send_option`, a branch in `leo_mvd_try_assign_effect`, a case in `leo_mvd_managed_matches_trigger`, an inline icon in `gui/leo_mvd_texticons.gui`, and `dir_icon`/`dir_name`/`DIRS` in the generator. For the dimmed exempt marker, also add a twin to both functions in `common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt`, with its `leo_mvd_x_*` loc keys and gray texticon.
- **DLC-gated content** — if a condition or directive only exists with a DLC (administrative → `$ADMIN_DLC`, nomad → `khans_of_the_steppe`), add it to `cond_dlc_feature`/`dir_dlc_feature`, and branch any preset that uses it on `has_dlc_feature` so the preset loads an alternative (see `leo_mvd_preset_1/3/4_effect`). Those helpers decide what `leo_mvd_build_options_effect` puts in the option list: a gated option is wrapped in its own `has_dlc_feature` check at its place in the list, so it is absent without the DLC rather than hidden, and still sits in panel order when present. Both helpers take one or more feature names; `sdlc`/`vdlc` turn several into an `OR`. A whole preset can be hidden the same way with `preset_dlc_vis`. The nomad section is gated as a block in `emit_waterfall`, so nomad directives need no per-row entry. Nothing here changes eligibility: the gated content already evaluates false without its DLC, so this is only to keep the panel and presets tidy — but a gate that is *stricter* than vanilla takes away content the player could use, so derive it from what vanilla actually tests. **Administrative is two expansions, not one.** Vanilla gates the administrative directives on `government_allows = administrative` alone, and five governments answer yes: Byzantium's from Roads to Power, plus celestial, meritocratic, steppe administrative and Ritsuryo from All Under Heaven. Hence `ADMIN_DLC="roads_to_power all_under_heaven"`. Do not use `admin_gov`.
- **Administration types are five sets, not one.** Every administrative government puts a type on its governors' contracts, but each has its own with its own flags: Roads to Power's six `admin_theme_*` themes, celestial's five `celestial_province_*`, meritocratic and steppe administrative's three `meritocratic_province_*`, Ritsuryo's three `japan_administrative_province_*` (whose industrial type carries a flag named for *trade*). They overlap by **name**, not by flag, so condition 20's values are names: each matches every flag of that name, and the panel offers a player only their own government's row. Which row that is comes from the `leo_mvd_admin_family_*_trigger` triggers, once: `admin_type_row` in the generator builds the picker from them, `leo_mvd_set_admin_family_effect` writes `leo_mvd_admin_family` for the one thing GUI has to read for itself (hiding the preset), and `leo_mvd_admin_type_loc.txt` picks the government's own names, icons and wording for the labels. Add a government to a family trigger and everything else follows. The threshold codes are append-only for the same reason the condition codes are.
- **A preset** — a `leo_mvd_preset_N_effect` (rule data, not logic), an sgui, loc for its name and `_tt`, and the dropdown's range in `emit_panel`.
- **More priorities** — raise `PRIORITIES` in the generator *and* extend `leo_mvd_write_field_effect`, the clear/backup/copy effects, and `leo_mvd_evaluate_vassal_effect`.
- **Total-conversion content** (see "Three mods from one source") goes in exactly one of three places, never a runtime `if AGOT` in a base file: a `TARGET=agot`/`TARGET=tfe` branch in the generator (something only that panel shows, e.g. a Westeros condition, `settle_wilderness`, the doubled Military Strength ladder, the Exarchate type), an injected `<target>/fragments/*.txt` at a base file's `# @AGOT:...@`/`# @TFE:...@` marker (script a base file needs a hook for, e.g. a directive's dispatch, a condition branch, a preset variant), or a self-contained `<target>/files/**` file copied in (a gate trigger, texticon, preset, value override, widget, or overlay loc). A marker in a file not yet listed in `MARKER_FILES` in `build.sh` will **ship as a stray comment and its fragment will never be injected**, so add the file there; new bracey or BOM-needing overlay files go in `AGOT_CHECK`/`AGOT_BOMLESS` or `TFE_CHECK`/`TFE_BOMLESS`. A marker meant to add a branch to an `if`/`else_if` chain goes *before* the final `else`, where an injected `else_if` is valid and an empty line is harmless.

## Verifying

There are no automated tests; the game is the test. Before handing back:

```
bash tools/gen_panel.sh        # refresh the repo-root (vanilla) files
bash tools/build.sh            # build + BOM- and brace-check all three mods
# Then, in the relevant dist(s), check that every scripted GUI, loc key,
# effect and trigger the panel names actually exists - including the keys
# built at runtime by Concatenate and the ones a customizable localization
# reaches, which nothing else will catch. A target's content only exists in
# its own dist, so check dist/agot and dist/tfe for theirs.
```

Have the user test **every build a change can reach**: `dist/vanilla` on plain CK3, `dist/agot` on a playset with A Game of Thrones, and `dist/tfe` on one with The Fallen Eagle. **Load after the conversion in both cases** (the mod overrides no AGOT or TFE *file*, but its by-name `vassal_directive_icon`/`vassal_directive_text` override for the exempt dimming has to win over AGOT's own definitions of those two, so it must load last; loaded before AGOT everything works except the dimming. TFE defines neither today, so order matters less there, but keep it last for the same reason.) Each with `-debug_mode`, watching `logs/error.log` for `leo_mvd`. A clean vanilla `error.log` is a hard gate: nothing target-only may leak into `dist/vanilla`. `reload gui` refreshes the panel live; structural changes may need a restart.

**Things static checks cannot catch, so ask for them to be tested:** anything reached only by a macro-built name; a loc key built at runtime; whether a directive thrashes month to month (assign, advance, confirm it stays).

### After a CK3, AGOT or TFE patch

Two steps, in order. The first is names, the second is everything names cannot tell you.

**1. `bash tools/check_compat_static.sh`.** Asserts every vanilla, AGOT and TFE name the mod leans on against the installed files (override `GAME_DIR`/`AGOT_DIR`/`TFE_DIR` if an install moved). It also block-diffs TFE's copy of `give_vassal_directive_interaction` against vanilla's, since TFE overrides that file and the mod's gates mirror it line for line. A FAIL means a patch renamed or removed something the mod mirrors; fix it before shipping. When a change adds a new vanilla dependency (a trigger, a flag, a concept, an overridden function), add a line for it here so the next patch is checked, not remembered. This checks names only: a name that still exists but changed *meaning* passes here.

**2. The real-mod smoke test.** The most limited set of steps that catches everything the static check cannot. Load `dist/vanilla` with `-debug_mode`, ideally an administrative realm with Roads to Power so the gated content is exercised, and in one session:

- Open **Realm → Subjects → the directives button.** The panel appears and is fully on-screen. (Catches a HUD/realm-window rework hiding or occluding it, as happened under AGOT.)
- Open a **condition dropdown.** Real condition names fill it; pick one and it applies. (This one action exercises the whole GUI mechanism: the datamodel over a script list, the runtime-built labels, the computed-name dispatch.)
- Pick a **preset**, then **Apply Now.** Directives assign to eligible vassals. Advance about three months: the assignments **stay** and none thrash. (A directive that assigns then vanishes next tick is the signature of the per-directive gates in `leo_mvd_triggers.txt` no longer matching vanilla's `send_option`s. If that happens, re-diff the `leo_mvd_gate_*` triggers against `give_vassal_directive_interaction`, whose lines they cite.)
- **Exempt** a vassal (right-click portrait). Its directive icon dims. (The by-name `vassal_directive_icon`/`vassal_directive_text` override still works.)
- `logs/error.log` has no `leo_mvd` lines.

Without Roads to Power or All Under Heaven, confirm instead that the gated conditions and directives are absent. With All Under Heaven but not Roads to Power, confirm the administrative directives, the Administrative Government condition and Administration Type are all present, the last offering that government's own types under its own names. For AGOT, load `dist/agot` after AGOT and repeat: the Westeros conditions appear, Settle the Wilderness assigns, and the exempt dimming works (it depends on load order). For TFE, load `dist/tfe` after TFE and repeat, starting with the opener: the button appears in the Subjects tab only, opens and closes the panel, answers the `mass_directives` keybind, and closing the realm window closes the panel with it. A Roman Imperial realm reads "Imperial Administration Type is" and offers Civilian, Military and Exarchate.

There is no committed in-game check tool: opening the real dropdown above tests the same GUI mechanism a synthetic one would, on the real panel rather than a proxy. If a mechanism ever does break and needs isolating to debug, a throwaway probe like the one in this repo's history can be rebuilt for the occasion.

## Conventions

- Prefix everything `leo_mvd_`.
- Directive codes 1-9 settled, 10-13 nomad, 14 AGOT `settle_wilderness`, 0 = none. They appear in `leo_mvd_managed`, node `dir` variables, and loc key suffixes. Keep them aligned. Condition codes 1-14 are the base set, 15-18 the AGOT Westeros conditions (added only in the `TARGET=agot` generator branch), 19-21 base conditions added later.
- Administration-type codes (condition 20's threshold values) are 1-6 the Roads to Power themes, 7-10 the All Under Heaven types that are not one of those names (standard, industrial, metropolitan, protectorate), 11 TFE's Exarchate (added only in the `TARGET=tfe` branch). A code is a *name*, so one code matches every government's type called that.
- **Condition, directive and administration-type codes are append-only.** They are stored in player variables that persist in saves, so renumbering silently rewrites the rule sets of everyone already playing. A new condition takes the next free code no matter where it belongs in the list; `CONDS` is what orders the panel, and it is deliberately not in numeric order.
- Scripted GUIs: `is_shown` = checked/selected state, `is_valid` = enabled, `effect` = onclick. Controls that read their own state from a variable need no entry at all.
- Comments say **why**, not what. The what is readable; the why is usually "the script language wouldn't let me do the obvious thing".
- **Text style.** Anything user-facing (game loc, `README.md`, the Workshop description) uses American spelling (recognize, gray, behavior, color, not recognise/grey/behaviour/colour) and no em-dash or spaced-hyphen separators between clauses. End the sentence and start a new one, or use a colon, parentheses, or a comma where that reads better. Genuine compound hyphens stay (quality-of-life, off-faith, duchy-tier). Hold comments and identifiers to the same spelling so the codebase stays consistent (`leo_mvd_gray_*`, not `grey`).
