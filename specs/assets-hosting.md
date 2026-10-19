# Assets and hosting

The local CraftPix library owns immutable vendor source. `tools/import_craftpix.py` copies seven saber-fighter animation sheets and three RPG Game UI button states plus the character notice, into ignored `assets/private/`. The tracked manifest binds source and destination paths, PNG hashes and original archive hashes. Runtime slices regions without changing originals. The importer records adoption in the private library under its mutation lock. Local subscription evidence remains in the library; none is copied here.

CraftPix raw art and PSDs must never enter public source. Code can run with the original fallback sprite. Exported playable game resources may contain licensed art according to game-use terms; there is no asset-download or artwork-export feature. Root notices identify the rights holder. No project license has been assigned.

`tools/build_web.sh` explicitly imports and exports using the managed Godot 4.7 Podman runtime. `play.sh` uses hardware GPU access and host networking for local co-op. The Web preset uses Compatibility, no threads or GDExtension, producing static files in ignored `build/web/`. GitHub Pages needs only these files at site root with `.nojekyll`. Web exports contain the runtime's generated JavaScript; project tooling needs no Node packages.

Source publication must exclude `.godot/`, private assets, candidate builds and capture files. Keep one current candidate; delete it after successful remote verification. Local preview image is disposable. Deployed assets belong in a separate Pages branch, never the source branch. No automatic deployment workflow or credentials have been installed.
