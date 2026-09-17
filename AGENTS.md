# Project conventions

- Be brief.
- Use only English language.
- Typed GDScript only. No untyped `var`.
- Use only 4.7.2 Godot version.
- 2D scenes in `scenes/2d/`, 3D in `scenes/3d/`.
- Tests live in `tests/` and run with GUT.
 
## Anti-patterns
 
- No `get_node()` in `_process` — cache references in `_ready`.
- No global singletons except `Globals.gd`. Use signal buses instead.
