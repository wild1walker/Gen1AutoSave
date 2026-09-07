# Changelog

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
