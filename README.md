# Leo VI's Mass Vassal Directives

A quality-of-life mod for **Crusader Kings III (1.19.x)** that automates vassal directives with a prioritized waterfall, so you never have to click through every vassal one by one again.

Nothing about directive _eligibility_ changes: the mod calls the game's own eligibility triggers and mirrors the vanilla interaction's conditions exactly. It only automates what you could already do by hand.

## How it works

Every eligible vassal is assigned the **highest priority that applies to them**:

| Priority | Directive             | Applies when                                                             |
| -------- | --------------------- | ------------------------------------------------------------------------ |
| 1        | Convert Faith         | The vassal shares **your faith** and holds counties of another faith     |
| 2        | Promote Culture       | The vassal shares **your culture** and holds counties of another culture |
| 3        | Configurable fallback | Neither of the above applies (see below)                                 |

If no priority applies, the vassal is left without a directive — and any directive **the mod previously assigned** is cleared. Directives you assigned manually are never touched by the cleanup.

Eligibility is pure vanilla: the vassal must be a landed, AI-controlled ruler of county tier or higher who actually _follows_ directives (50+ opinion, admin government, strong hook, Absolute crown authority, the relevant perks, etc. — exactly the vanilla rules). Vassals currently refusing directives are skipped entirely.

### The fallback (priority 3)

Three modes, configured in-game:

- **None** — vassals not covered by priorities 1–2 get no directive.
- **Blanket** — one directive of your choice (any of the 7 non-conversion directives) applied to all remaining vassals. Vanilla per-directive requirements still apply (e.g. Improve Development needs an administrative duchy+ vassal).
- **Military/economy branch** — remaining vassals below a military-strength threshold are told to construct military buildings; those above it construct economic buildings. The threshold you pick is the **duchy baseline** and scales by title tier so it stays meaningful at every realm size: counts ×0.5, dukes ×1, kings ×3, emperors ×6. (Multipliers are tunable in `common/script_values/leo_mvd_values.txt`.)

## Using the mod

1. **Configure**: open the decision **"Vassal Directive Automation"** (Decisions tab). The menu shows current settings and lets you enable automation, toggle the monthly auto-run, and pick the fallback mode.
2. **Apply**: either turn on the **monthly auto-run** (the waterfall re-evaluates all vassals every 30 in-game days — vassals whose counties finish converting automatically move on to the next priority), or use **"Apply Directive Priorities"** / the menu's _Apply directives now_ whenever you like.
3. **Exempt individuals**: right-click a vassal's portrait → Vassal section → **"Exempt from Directive Automation"**. Exempt vassals show a ❌ marker on their directive icon everywhere in the UI and are skipped by the waterfall; manage them manually with the vanilla _Give Vassal Directive_ interaction. Undo via **"Include in Directive Automation"** on the same menu.
4. **Escape hatch**: the config menu's _Remove all automated directives and disable_ clears every directive the mod assigned, removes all exemptions, and turns automation off. Manually assigned directives are kept.

Settings are stored per playthrough and carry over to your heir on succession.

⚠️ Note: the waterfall **overwrites manual directive assignments on non-exempt vassals** on its next run. Exemption is how you protect a manual choice.

## Compatibility

- **Achievements**: not affected — since CK3 1.9, mods do not disable achievements.
- **Existing saves**: safe to add mid-run (automation bootstraps within a game-year, or immediately via the config decision) and safe to remove (mod-assigned directives are ordinary vanilla directives; leftover mod variables are inert).
- **Multiplayer**: settings and automation are per-player.
- **Other mods**: the only vanilla file override is `common/customizable_localization/00_vassal_custom_loc.txt` (adds the ❌ exemption marker). Any mod overriding the same file will conflict on that cosmetic feature only.
- **Nomad/herder governments**: their special directives are not automated in v1; such vassals are simply left alone.

## Updating after game patches

Two files mirror or copy vanilla content and should be re-diffed against the game files after each CK3 patch (both are commented with what to compare):

- `common/scripted_triggers/leo_mvd_triggers.txt` — mirrors the inline gates of `give_vassal_directive_interaction` (`game/common/character_interactions/00_vassal_interactions.txt`).
- `common/customizable_localization/00_vassal_custom_loc.txt` — full copy of the vanilla file with exemption-marker twin entries.

## File layout

```
common/character_interactions/leo_mvd_interactions.txt   exempt / include toggle interactions
common/customizable_localization/00_vassal_custom_loc.txt  VANILLA OVERRIDE: ❌ exemption marker
common/customizable_localization/leo_mvd_custom_loc.txt  settings summary for the config menu
common/decisions/leo_mvd_decisions.txt                   config + apply-now decisions
common/on_action/leo_mvd_on_actions.txt                  game-start bootstrap, succession carry-over, yearly watchdog
common/script_values/leo_mvd_values.txt                  tier-scaled threshold (tunable multipliers)
common/scripted_effects/leo_mvd_effects.txt              the waterfall core
common/scripted_triggers/leo_mvd_triggers.txt            eligibility (vanilla triggers + mirrored gates)
events/leo_mvd_events.txt                                monthly pulse + config menu events
localization/english/leo_mvd_l_english.yml               all mod text
```

### Implementation notes

- Vanilla directives are character flags (`vassal_directive_*`); assignment matches the vanilla interaction exactly (`remove_vassal_directives` + `add_character_flag`).
- The mod tracks what it assigned via a `leo_mvd_managed` variable on each vassal, so it can clean up after itself without ever clearing a player's manual assignment.
- There is no monthly on_action in vanilla, so a self-rescheduling hidden event (`leo_mvd.1`) drives the auto-run, with a heartbeat flag and a yearly watchdog to restart it after loading pre-mod saves or switching characters.
- Vanilla on_actions are extended via their additive `on_actions` list (never by redefining `effect`, which would replace vanilla's logic).

## Roadmap / ideas

- General rule builder: arbitrary condition → directive chains (tier, terrain, development, contract theme, ...).
- Nomad/herder directive support.
- Exemption inheritance when a vassal dies.
- Optional auto-exempt when a directive is assigned manually (requires overriding the vanilla interaction file, so deferred).

## Maintenance & contributions

I'm just one guy with a real job and a real life — this mod is a hobby project, so please be patient if patches break something and it takes me a while to get to it. Bug reports are welcome (an `error.log` excerpt and a description of what you expected goes a long way), and contributions are actively encouraged: if you want to fix a compatibility issue, tackle something from the roadmap, or add a localization, open a pull request. The implementation notes above and the comments in the script files should give you everything you need to find your way around.
