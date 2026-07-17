# Leo VI's Mass Vassal Directives

A quality-of-life mod for **Crusader Kings III (1.19.x)** that hands out vassal directives for you, by rules you write, so you never have to click through every vassal one by one again.

Nothing about directive _eligibility_ changes: the mod calls the game's own eligibility triggers and mirrors the vanilla interaction's conditions exactly. It only automates what you could already do by hand.

It requires **no DLC, and supports them all**. The administrative directives come from _Roads to Power_ and nomad vassals from _Khans of the Steppe_; when you own a DLC the mod folds its content in, and when you do not, the panel hides what that DLC would add and the presets adjust their plans, so you only ever see options your game can actually use.

## How it works

You give the mod a **running order**: a list of priorities, worked through from the top. Each vassal gets the first directive in it that suits them. A vassal no priority claims is simply left alone.

A priority is one of three things:

- **Assign a Directive**: give it to every vassal who reaches this far.
- **Check a Condition**: ask something about the vassal, and send each answer its own way. Either branch can be another condition, so a priority can weigh up to two questions.
- **Continue to Next Priority**: do nothing here and let the next one decide.

The key to reading a rule set: **a vassal who cannot be given a directive falls through to the next priority.** That is the game's own doing (vanilla hides a directive it will not allow), and it is what lets a rule say "develop the land" without worrying about the vassals who cannot.

Nomads keep a **running order of their own**, below the main one. They have four directives no one else can be given and can be given none of the other nine, so they cannot share a list with the rest.

### Presets

Pick one and its plan appears in the panel, so you can read what it actually does rather than take the name on trust:

| Preset                  | What it does                                                                                        |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| **None**                | Nothing is assigned, and the automation gives up whatever it handed out. The default.               |
| **Convert and Develop** | Faith, then culture, then growth: the strong develop their land, the weak build up their military.  |
| **Unify the Realm**     | Converts harder, at the cost of growth. Cultural acceptance grinds down what conversion cannot.     |
| **Prepare for War**     | Arms the realm, each vassal to their strength. Ignores faith and culture.                           |
| **Grow the Economy**    | Wealth first: the undeveloped develop, the established build. Ignores faith and culture.            |
| **Custom**              | Your own rules, up to six priorities plus three for nomads.                                         |

**A preset is a starting point, not a take-it-or-leave-it.** Change any of its rules and the whole thing becomes yours, exactly as it was, plus your change. Suiting one to your realm costs a click rather than a rebuild. Picking Custom outright starts you from nothing instead. Your own rules are kept aside while a preset is loaded, so trying one never costs you your waterfall.

### Conditions

Faith is Yours · Culture is Yours · Holds Counties of Another Faith · Holds Counties of Another Culture · Same Dynasty as You · Administrative Government · Is a Powerful Vassal · Is on Your Council · Military Strength · Title Tier · Capital Development · Opinion of You · Counties Held · Cultural Acceptance with You

Every measured condition reads the same way (**"is at least"**), so the true branch is always the high side. Military Strength is the exception worth knowing: the number you pick is the **duchy baseline**, and it scales by title tier so it stays meaningful at every realm size (counts ×0.4, dukes ×1, kings ×3, emperors ×8; tunable in `common/script_values/leo_mvd_values.txt`). Administrative Government appears only with _Roads to Power_.

## Using the mod

All configuration lives in a panel docked to the **Realm → Subjects** tab.

1. **Open it**: in the Realm window's Subjects tab, click the directives button in the header (next to _Toggle Compact List_). The panel appears alongside; drag it wherever you like.
2. **Choose a preset.** Nothing is assigned until you do.
3. **Tick Automatically Reassign Vassal Directives** to run the rules every month and again whenever you change anything. **Apply Now** runs them once, on demand.
4. **Exempt individuals**: right-click a vassal's portrait → Vassal section → **"Exempt from Directive Automation"**. Exempt vassals show their directive icon **dimmed gray** everywhere in the UI and are skipped entirely; manage them by hand with the vanilla _Give Vassal Directive_ interaction. Undo with **"Include in Directive Automation"**.
5. **Escape hatch**: **Remove All** clears every directive the mod assigned, removes all exemptions, and turns automation off.

Settings are stored per playthrough and carry over to your heir on succession.

⚠️ The rules **overwrite manual directive assignments on non-exempt vassals** on their next run. Exemption is how you protect a manual choice. Directives you assigned by hand are otherwise never touched. The mod only ever clears a directive it still recognizes as its own.

## Compatibility

- **DLC**: none required, all supported. _Roads to Power_ adds the administrative directives (Improve Development, Train Commanders, Build Men-at-Arms) and the Administrative Government condition; _Khans of the Steppe_ adds nomad vassals and their four directives. Without a given DLC the panel hides what it would enable and the built-in presets adapt their plans, so nothing ever points at an option your game cannot use.
- **Achievements**: not affected. Since CK3 1.9, mods do not disable achievements.
- **Existing saves**: safe to add mid-run (automation bootstraps within a game-year, or immediately from the panel) and safe to remove (mod-assigned directives are ordinary vanilla directives; leftover mod variables are inert).
- **Multiplayer**: settings and automation are per-player; every button routes through a synchronized scripted GUI.
- **Other mods**: the only vanilla file override is `common/customizable_localization/00_vassal_custom_loc.txt` (adds the grayed exemption marker). Any mod overriding the same file will conflict on that cosmetic feature only. The panel is added as a standalone widget and overrides no vanilla GUI file.
- **Herders**: vanilla gives herders no directives at all, so neither does the mod.

## Updating after game patches

A few files mirror or copy vanilla content and should be re-diffed against the game files after each CK3 patch (each is commented with what to compare):

- `common/scripted_triggers/leo_mvd_triggers.txt`: mirrors `give_vassal_directive_interaction`'s eligibility and its per-directive gates (`game/common/character_interactions/00_vassal_interactions.txt:3420+`). `leo_mvd_directive_shown_trigger` is the one copy of vanilla's is_shown, used by both the rules and the exempt interaction.
- `common/customizable_localization/00_vassal_custom_loc.txt`: full copy of the vanilla file with exemption-marker twin entries.
- `gui/leo_mvd_panel.gui`: latches onto the vanilla Subjects-tab directives button and its `mass_directives_window` GUI variable (`game/gui/window_my_realm.gui`); confirm that button and variable still exist. Also carries copies of vanilla's `button_drop` and `button_dropdown` (`game/gui/shared/buttons.gui`).
- `gui/leo_mvd_texticons.gui`: gray and inline-sized twins of the vanilla directive texticons (`game/gui/texticons.gui`); confirm the source textures still exist.

## File layout

```
common/character_interactions/leo_mvd_interactions.txt   exempt / include toggle interactions
common/customizable_localization/00_vassal_custom_loc.txt  VANILLA OVERRIDE: grayed exemption marker
common/on_action/leo_mvd_on_actions.txt                  game-start bootstrap, succession carry-over, yearly watchdog
common/script_values/leo_mvd_values.txt                  tier-scaled military threshold (tunable multipliers)
common/scripted_effects/leo_mvd_effects.txt              assignment, cleanup, the run across all vassals
common/scripted_effects/leo_mvd_rules.txt                the rule engine, the presets, the editor's writes
common/scripted_guis/leo_mvd_sguis.txt                   panel buttons (synchronized)
common/scripted_guis/leo_mvd_edit.txt                    GENERATED: the editor's scripted GUIs
common/scripted_triggers/leo_mvd_triggers.txt            eligibility, per-directive gates, the conditions
events/leo_mvd_events.txt                                monthly self-rescheduling pulse
gui/leo_mvd_panel.gui                                    GENERATED: the configuration panel
gui/leo_mvd_texticons.gui                                gray and inline directive icons
gui/scripted_widgets/leo_mvd_widgets.txt                 registers the panel as a standalone widget
localization/english/leo_mvd_l_english.yml               static panel text
localization/english/leo_mvd_ui_l_english.yml            GENERATED: the editor's labels
tools/gen_panel.sh                                       generates the three files above
```

### Implementation notes

Most of the interesting decisions here were forced by what CK3's script and GUI can and cannot do. The short version:

- **The rule tree is capped at two levels of conditions because scripted effects cannot recurse.** The walk is unrolled by hand, one effect per level (`leo_mvd_eval_root_effect` → `_mid_` → `_leaf_`).
- **A variable name cannot be built at runtime**, so rules live in fixed node slots reached by macro expansion, and **a condition cannot be chosen at runtime**, so the condition and directive chains are written once and driven by a value staged into a temporary scope rather than duplicated per node.
- **The panel is generated** (`tools/gen_panel.sh`). The editor is the same widgets repeated per node, differing only in the variable they bind to, and GUI has no way to factor that out. `blockoverride` cannot parameterize a variable name inside a binding. Six priorities plus the nomads' three come to ~25,000 lines. **Edit the generator, not the files it writes.**
- **Controls read their state straight from the variable they represent**: `EqualTo_CFixedPoint` against `Var(...).GetValue` for a bool, or pasting the value onto a loc key prefix for a dropdown's label. Only clicking one runs script, so the panel costs no per-frame script evaluation.
- **GUI cannot hand script a number.** So choosing an option runs two scripted GUIs in order: one points a cursor at the node, the next writes to whatever the cursor points at. That is what keeps the editor at ~110 scripted GUIs rather than one per node-and-option pair.
- **Dropdown lists push the rows below them down rather than floating over them.** Draw order is tree order and there is no z-index for a non-window widget, so a list inside its row is painted over by every row after it. Floating would need either a datamodel to mirror for alignment (script lists hold scopes, so rule nodes cannot be items) or the button's screen position (no datafunction returns one). Vanilla hits the same wall: `game_rules.gui` is this same panel and puts its dropdowns outside the scrollbox, using an arrow cycler for the rows inside.
- Vanilla directives are character flags (`vassal_directive_*`); assignment matches the vanilla interaction exactly (`remove_vassal_directives` + `add_character_flag`).
- The mod tracks what it assigned via a `leo_mvd_managed` variable on each vassal, so it can clean up after itself without ever clearing a player's manual assignment.
- There is no monthly on_action in vanilla, so a self-rescheduling hidden event (`leo_mvd.1`) drives the auto-run, with a heartbeat flag and a yearly watchdog to restart it after loading pre-mod saves or switching characters.
- Vanilla on_actions are extended via their additive `on_actions` list (never by redefining `effect`, which would replace vanilla's logic).

## Roadmap / ideas

- Exemption inheritance when a vassal dies.
- Optional auto-exempt when a directive is assigned manually (requires overriding the vanilla interaction file, so deferred).
- More conditions: the set is a closed list in script (`leo_mvd_cond_holds_trigger`), since a condition cannot be chosen at runtime, but adding to it is mechanical.

## Maintenance & contributions

I'm just one guy with a real job and a real life. This mod is a hobby project, so please be patient if patches break something and it takes me a while to get to it. Bug reports are welcome (an `error.log` excerpt and a description of what you expected goes a long way), and contributions are actively encouraged: if you want to fix a compatibility issue, tackle something from the roadmap, or add a localization, open a pull request. The implementation notes above and the comments in the script files should give you everything you need to find your way around. Start with `common/scripted_effects/leo_mvd_rules.txt`, which explains the shape of the whole thing.
