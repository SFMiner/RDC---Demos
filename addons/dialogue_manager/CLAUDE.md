# CLAUDE.md — dialogue_manager addon

This is a third-party addon. **Do not edit files inside `addons/dialogue_manager/` directly.**
The project's custom balloon lives at `res://addons/dialogue_balloon.gd` (one level up,
outside this directory) and is the correct place for all game-specific dialogue changes.

## Project customisations made to the balloon (`addons/dialogue_balloon.gd`)

### Character font styling (bold/italic BBCode support)
When a dialogue line is displayed, the balloon applies the speaking character's font,
size, and colour to the `RichTextLabel` (`dialogue_label`). The overrides set are:

| Override key          | Purpose                          |
|-----------------------|----------------------------------|
| `normal_font`         | Base character font              |
| `bold_font`           | Font used for `[b]...[/b]` spans |
| `italics_font`        | Font used for `[i]...[/i]` spans |
| `bold_italics_font`   | Font used for `[b][i]...[/i][/b]` spans |
| `normal_font_size`    | Base size                        |
| `bold_font_size`      | Size for bold spans              |
| `italics_font_size`   | Size for italic spans            |
| `bold_italics_font_size` | Size for bold+italic spans    |
| `default_color`       | Character text colour            |

Variant font slots fall back to the normal font if no path is provided, so
specifying only `font_path` is sufficient for characters that have no
bold/italic variants. Provide the extra paths only when a separately-authored
font file (e.g. produced with FontForge) is available.

### Character data source
Font paths, size, and colour are read from `data/characters/<id>.json`:
```json
{
  "font_path":             "res://assets/fonts/MyFont-Regular.ttf",
  "font_bold_path":        "res://assets/fonts/MyFont-Bold.ttf",
  "font_italic_path":      "res://assets/fonts/MyFont-Italic.ttf",
  "font_bold_italic_path": "res://assets/fonts/MyFont-BoldItalic.ttf",
  "font_color": "#FF8800",
  "font_size": 2
}
```
`font_bold_path`, `font_italic_path`, and `font_bold_italic_path` are all
optional — omit any that don't exist and the normal font will be used instead.
`font_size` is an offset added to a base size of 25 (so `2` → 27px).
