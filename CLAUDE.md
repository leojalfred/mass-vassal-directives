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

That includes layout tweaks — margins and the window skeleton live in the generator too. It builds to a temp dir, brace-checks, and only then moves files into place, so a failed run leaves the real ones alone. The generator is target-aware (`TARGET=vanilla|agot`, `OUTDIR=<dir>`); run bare like this it writes the vanilla files at the repo root, and `tools/build.sh` invokes it once per target (see below). After a generator change, run it bare to keep the committed repo-root files current, then run `build.sh` to produce and check both mods.

Why generated: the editor is the same widgets repeated per node, differing only in the variable they bind to, and `blockoverride` cannot parameterize a variable name inside a binding.

**That rationale is only half true, and the half that is false matters.** `blockoverride` cannot do it, but a `datamodel` can: a GUI binding may build a variable name at runtime, so one `item` template can serve every node and every option (see "The limits that explain the design"). What genuinely cannot be factored out is the *script* side — `leo_mvd_write_field_effect`'s 63-way dispatch — because a script variable name really is parse-time. So the generator's remaining job is smaller than it looks, and repetition in the `.gui` is a cost, not a necessity: the panel is created at startup and its first-open hitch scales with widget count.

## Two mods from one source

The repo builds **two shippable mods** from shared source: `dist/vanilla/` (the base mod) and `dist/agot/` (the same, adapted for the A Game of Thrones total conversion). `dist/` is gitignored and holds **game files only** — no tools, docs, or dev files — so each subfolder is ready to point the launcher at and upload to the Workshop. **Load and test from `dist/vanilla` and `dist/agot`, never the repo root.** The root's committed generated files (panel, editor sgui, English UI loc) are the version-controlled copy of the *vanilla* output: `dist/` is gitignored, so keeping the root current (via `gen_panel.sh` run bare) is what makes generator changes show up as reviewable git diffs. The root is not a mod you load — its descriptor's `thumbnail.png` only exists once the build copies it into each dist.

```
bash tools/build.sh            # builds both mods in parallel; -v narrates
```

There is **no runtime AGOT detection**. Everything that differs is applied at build time:

- **The panel** is regenerated in AGOT mode — the generator adds the `settle_wilderness` directive and the five Westeros conditions, drops the nomad section, and doubles the Military Strength ladder (all keyed on `TARGET=agot`).
- **Small fragments** are injected at `# @AGOT:...@` markers in three base files (`leo_mvd_rules.txt`, `leo_mvd_triggers.txt`, `zz_leo_mvd_vassal_directive_loc.txt`): the directive's dispatch, its ownership match, the five condition branches, and two cust-loc entries. The vanilla build simply strips the markers.
- **AGOT-only files** under `agot/files/` are copied in verbatim (its gate trigger, wilderness texticons, extra presets/sguis, the `leo_mvd_mil_baseline` override, and the translated overlay loc). `agot/descriptor.mod` replaces the base one.

So AGOT changes live in exactly three places: the generator's `TARGET=agot` branches, `agot/fragments/*.txt` (injected), and `agot/files/**` (copied). Base files carry only the inert markers. **Adding AGOT content means editing one of those three, never adding a runtime `if AGOT` to a base file.** Eligibility stays exactly vanilla in both builds; the AGOT deltas only surface content AGOT itself allows (e.g. `settle_wilderness`, a feudal-safe directive).

## Localization

The mod ships every language CK3 officially supports (english, french, german, spanish, russian, korean, simp_chinese, japanese, polish). English is the source of truth: `localization/english/leo_mvd_l_english.yml` is hand-written, `leo_mvd_ui_l_english.yml` is generated. The others live in `localization/<lang>/leo_mvd_l_<lang>.yml` and `leo_mvd_ui_l_<lang>.yml` and are **machine-generated, then hand-maintained** — the generator only ever writes the English UI file, so translations are never regenerated for you.

**Whenever you change an English localization value, update every translated file to match** — same keys in the same order, the changed value re-translated. This applies to the static file *and* the generated UI file (its translations are hand-maintained too). Keep the CK3 markup identical across languages: concept links `[x|E]`, `$refs$`, `@icon!` tokens, `[recipient.GetX]` calls, `#weak`/`#V` … `#!` codes, and `\n` are never translated — only the prose between them. In user-facing text the translations are described as **machine-generated**, never "AI" (see Hard rules).

AGOT-only loc lives in overlay files, `agot/files/localization/<lang>/leo_mvd_agot_l_<lang>.yml`, one per language, shipped only to `dist/agot`. English is split: the AGOT condition/directive/threshold labels come out of the generator (into the AGOT `leo_mvd_ui_l_english.yml`), while the exempt marker and the extra presets are hand-written in the English overlay. The **translated** overlays carry *both* sets — the generator only ever writes English, so every AGOT-specific key a non-English game needs must be hand-translated into its overlay (which is why the translated overlays hold more keys than the English one; repeating the generator's English keys there would just duplicate them). The build adds the BOM to every overlay loc file for you.

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
- **The panel is created at game start, not on first open.** `gui/scripted_widgets/` means "create this widget on startup" (`_scripted_widgets.info`). So the first-open hitch is the first *layout and text-shaping* pass over the whole tree, which is why widget **count** is the thing that matters.
- **All `.txt`/`.gui`/`.yml` need a UTF-8 BOM. `descriptor.mod` must NOT have one.**
- **Script variables and flags that only GUI ever reads trip the validator.** `-debug_mode` logs "set but is never used", because it scans script only and does not count GUI or localization. Keep `error.log` clean by referencing them from a scripted trigger that something actually calls.

## Adding things

- The vanilla is_shown mirror lives once, in `leo_mvd_directive_shown_trigger` - both the rules and the exempt interaction call it. Keep it that way.
- **A condition** — add to `leo_mvd_cond_holds_trigger` (the chain, keyed on `scope:leo_mvd_cond_id`), then `CONDS`/`cond_name` in the generator. If it takes a number, also `NUMERIC_CONDS`, `cond_thresh`, `cond_default_thresh`, `thresh_label`. Guard anything that changes scope with `exists`. Add it to `NOMAD_CONDS` unless a nomad could never answer yes. A condition whose meaning is not obvious from its label can carry an explanatory tooltip via `cond_tt`; leave it out and the generator writes a blank tooltip key, which renders nothing. Everything else follows: the option list, the redundancy code, the blank tooltip and the setter scripted GUI are all generated from `CONDS`.
- **`CONDS` is also the panel's display order**, and it is deliberately not in numeric order — codes are append-only because they live in saved player variables, so a new condition takes the next free code and is then placed in the list wherever it reads best.
- **A directive**: a gate trigger mirroring its vanilla `send_option`, a branch in `leo_mvd_try_assign_effect`, a case in `leo_mvd_managed_matches_trigger`, an inline icon in `gui/leo_mvd_texticons.gui`, and `dir_icon`/`dir_name`/`DIRS` in the generator. For the dimmed exempt marker, also add a twin to both functions in `common/customizable_localization/zz_leo_mvd_vassal_directive_loc.txt`, with its `leo_mvd_x_*` loc keys and gray texticon.
- **DLC-gated content** — if a condition or directive only exists with a DLC (administrative → `roads_to_power`, nomad → `khans_of_the_steppe`), add it to `cond_dlc_vis`/`dir_dlc_vis`, and branch any preset that uses it on `has_dlc_feature` so the preset loads an alternative (see `leo_mvd_preset_1/3/4_effect`). Those two functions no longer gate a widget: they decide what `leo_mvd_build_options_effect` puts in the option list, so an option the player cannot use is absent rather than hidden. A whole preset can be hidden the same way with `preset_dlc_vis`. Use `roads_to_power`, **not** `admin_gov` — the latter does not track DLC ownership. The nomad section is gated as a block in `emit_waterfall`, so nomad directives need no per-row entry. Nothing here changes eligibility: the gated content already evaluates false without its DLC, so this is only to keep the panel and presets tidy.
- **A preset** — a `leo_mvd_preset_N_effect` (rule data, not logic), an sgui, loc for its name and `_tt`, and the dropdown's range in `emit_panel`.
- **More priorities** — raise `PRIORITIES` in the generator *and* extend `leo_mvd_write_field_effect`, the clear/backup/copy effects, and `leo_mvd_evaluate_vassal_effect`.
- **AGOT-only content** (see "Two mods from one source") goes in exactly one of three places, never a runtime `if AGOT` in a base file: a `TARGET=agot` branch in the generator (something only the AGOT panel shows, e.g. a Westeros condition, `settle_wilderness`, the doubled Military Strength ladder), an injected `agot/fragments/*.txt` at a base file's `# @AGOT:...@` marker (script a base file needs a hook for, e.g. a directive's dispatch or a condition branch), or a self-contained `agot/files/**` file copied in (a gate trigger, texticon, preset, value override, or overlay loc). New markers must be added to `MARKER_FILES` in `build.sh`; new bracey or BOM-needing overlay files to `AGOT_CHECK`/`AGOT_BOMLESS`.

## Verifying

There are no automated tests; the game is the test. Before handing back:

```
bash tools/gen_panel.sh        # refresh the repo-root (vanilla) files
bash tools/build.sh            # build + BOM- and brace-check both mods
# Then, in the relevant dist(s), check that every scripted GUI, loc key,
# effect and trigger the panel names actually exists - including the keys
# built at runtime by Concatenate, which nothing else will catch. AGOT-only
# content only exists in dist/agot, so check there for it.
```

Have the user test **both** where a change can affect both: load `dist/vanilla` on plain CK3 and `dist/agot` on a playset with A Game of Thrones, **loaded after AGOT** (the mod overrides no AGOT *file*, but its by-name `vassal_directive_icon`/`vassal_directive_text` override for the exempt dimming has to win over AGOT's own definitions of those two, so it must load last; loaded before AGOT everything works except the dimming), each with `-debug_mode`, and watch `logs/error.log` for `leo_mvd`. A clean vanilla `error.log` is a hard gate: nothing AGOT-only may leak into `dist/vanilla`. `reload gui` refreshes the panel live; structural changes may need a restart.

**Things static checks cannot catch, so ask for them to be tested:** anything reached only by a macro-built name; a loc key built at runtime; whether a directive thrashes month to month (assign, advance, confirm it stays).

## Conventions

- Prefix everything `leo_mvd_`.
- Directive codes 1-9 settled, 10-13 nomad, 14 AGOT `settle_wilderness`, 0 = none. They appear in `leo_mvd_managed`, node `dir` variables, and loc key suffixes. Keep them aligned. Condition codes 1-14 are the base set, 15-18 the AGOT Westeros conditions (added only in the `TARGET=agot` generator branch), 19-20 base conditions added later.
- **Condition and directive codes are append-only.** They are stored in player variables that persist in saves, so renumbering silently rewrites the rule sets of everyone already playing. A new condition takes the next free code no matter where it belongs in the list; `CONDS` is what orders the panel, and it is deliberately not in numeric order.
- Scripted GUIs: `is_shown` = checked/selected state, `is_valid` = enabled, `effect` = onclick. Controls that read their own state from a variable need no entry at all.
- Comments say **why**, not what. The what is readable; the why is usually "the script language wouldn't let me do the obvious thing".
- **Text style.** Anything user-facing (game loc, `README.md`, the Workshop description) uses American spelling (recognize, gray, behavior, color, not recognise/grey/behaviour/colour) and no em-dash or spaced-hyphen separators between clauses. End the sentence and start a new one, or use a colon, parentheses, or a comma where that reads better. Genuine compound hyphens stay (quality-of-life, off-faith, duchy-tier). Hold comments and identifiers to the same spelling so the codebase stays consistent (`leo_mvd_gray_*`, not `grey`).
