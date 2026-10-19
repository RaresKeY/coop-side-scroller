# Co-op Side Scroller specs

Standalone Godot prototype with one CraftPix character, a simple square-tile floor, static Web export and independent-process co-op testing.

| Spec | Sources | Read when |
| --- | --- | --- |
| [Prototype](prototype.md) | `src/main.gd`, `project.godot`, `main.tscn` | Changing gameplay, menus, animation or transport |
| [Network lab](network-lab.md) | `play-labs.sh`, `labs/`, `src/lab_keys.gd`, `tests/lab.sh` | Changing interactive tests, keyboard routing, latency/debug or process ownership |
| [Assets and hosting](assets-hosting.md) | `tools/`, `assets/craftpix-manifest.json`, `export_presets.cfg`, `.gitignore` | Importing art or building/publishing |
| [Verification](verification.md) | `tests/`, Web export and browser/manual checks | Assessing what is actually proven |

Provider alternatives are in `design/network-options.md`; deferred work is in `BACKLOG.md`.
