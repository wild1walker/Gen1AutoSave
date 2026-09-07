# Changelog

## 1.20.1

- **Picking QUIT no longer crashes when there is nothing to save.** Load a
  save, open START and choose QUIT before anything has happened, and the mod
  raised `attempt to call field 'unpack' (a nil value)` instead of showing the
  prompt. Nothing had changed yet, so there was no save worth offering -- and
  the fallback that hands the row back to the game untouched was the broken
  part:

  ```lua
  original(unpack and unpack(args) or table.unpack(args))
  ```

  Two faults in one line. `a and b or c` truncates `b` to a single value, so
  only the first argument was ever forwarded; and the Gen 1 start menu calls a
  row with *no* arguments at all, which made that single value `nil`, fell
  through to the `or`, and reached for a `table.unpack` that does not exist on
  the Lua the game runs. LOVE is LuaJIT -- the global `unpack` is the one that
  exists there. `tests/` runs Lua 5.4, where it is the other way round, which
  is why the suite covering exactly this path stayed green.

  The name is resolved once now, at load, and arguments are forwarded with
  their arity via `select("#", ...)` so a `nil` in the list no longer ends it.
  `tests/quit_fallback_test.lua` drives the row under both arrangements of the
  two names, and fails under the LuaJIT one against the old line.

- **Every harness runs in CI.** The workflow named six suites by hand and the
  directory held nine, so three had never run once. Both file-naming
  conventions are globbed now, and a failing suite is caught by its exit
  status, its `FAIL` lines and its summary count rather than by one of the
  three.

## 1.20.0

- **Runs on Gold, Silver and Crystal.** Everything the mod promises is the
  same there; what changes is how it answers *is it safe to write right now?*,
  because the two games say "busy" in completely different ways.

  On Red a fade is `transitioning` or `teleportOut`. Gold has neither — a warp,
  a door, a teleport, the ride back out of a battle and a scripted fade to
  white are all `mapSetup` or `fade`. Scripts, engagement and emotes differ the
  same way.

  So the three guards — a fade running, something else holding the controls,
  the player mid-engagement — are each defined once with a branch per cart,
  instead of the Red checks being repeated inline the way they grew. **Nothing
  about when it saves changed on Red:** the same conditions are asked in the
  same places, from one definition rather than six.
