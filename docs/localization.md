# Localization

Slavian ships in English and Serbian (Latin). English is the source text:
every string the player sees is written in English in the code and looked
up in `client/i18n/<language>.po` (gettext) at run time.

- **In GDScript** mark strings with `tr("…")` in nodes, `UI.t("…")` in static
  helpers, and `tr_n("one", "many", n)` / `UI.tn(…)` for counts (Serbian has
  three plural forms). Format after translating: `tr("Round %d of %d") % [a, b]`.
  Constants translated where they are used get a `# tr` comment at the end of
  their line so the extractor finds them.
- **Game data** (`data/*.json`): names, titles, descriptions and other texts are
  collected automatically; translate them at use with `UI.t(def.name)`.
- **Never translated:** names players chose (villages, worlds, accounts), hero
  and enemy leader names. Godot's automatic translation of control text is off.
- `python3 tools/i18n/extract.py` updates `client/i18n/messages.pot` and the
  `.po` files (new strings come in empty); `--check` fails when they're stale or
  a string is untranslated. Translate with any .po editor (Poedit) or by hand.
- The player picks the language on the start screen; the first run follows the
  device (Serbian, Bosnian, Croatian or Montenegrin devices start in Serbian).
