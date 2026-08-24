# Gen1AutoSave

An autosave mod for gen1recomp that makes manual saving optional, and that is
deliberately careful around the built-in save sync.

## What it does

- **Saves after things happen** — battles, catches, evolutions, hatches, trades,
  blackouts, entering a new map. Between them they cover ordinary play, which
  is why the clock below ships `OFF`. Each one saves as soon as the overworld
  settles, floored at one write every 20 seconds.
- **QUIT asks, then waits.** Picking `QUIT` puts up `SAVE AND RETURN TO MAIN
  MENU?` in place of the engine's own confirm. `YES` saves behind a
  `Now saving...` box and holds the quit until the write *and* the upload it
  starts are done, so the save reaches the server while there is still a game
  running to send it. `NO` cancels, exactly as before. Nothing is promised
  when nothing would be written — with a clean save, or a sync conflict
  standing, you get the vanilla prompt and the vanilla quit.
- **An optional play-time timer**, off by default. Turned on, a long gym battle
  advances it, so `5 MIN` means five minutes of playing rather than five
  minutes of standing on a route. The write itself still waits for a settled
  overworld.
- **A Poke Ball that wobbles** in the top right corner when a save lands, in
  place of a text box across the screen. One tile in from the corner of the
  game itself, which is the window's corner when the map fills it and the
  picture's corner under FAITHFUL RATIO, where the bars around the picture are
  dead display. Switchable to a small `SAVED` panel, the classic text box, or
  off.
- **Optional rollback backups** of recent autosaves, reachable from the START
  menu.

Manual saving is untouched: it writes and syncs exactly as it does without this
mod. The only thing that happens here is the clock resetting, so an autosave
does not land on top of a save you just made yourself.

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `AUTO SAVE` | on | Master switch. |
| `INTERVAL` | OFF | An extra save every so much play time, on top of the events. |
| `AFTER EVENTS` | on | Save after battles, catches, new areas and so on. |
| `ON QUIT` | on | Offer the save in the QUIT confirm, and wait for it. |
| `INDICATOR` | POKE BALL | `OFF`, `POKE BALL`, `SAVED TEXT`, or `TEXT BOX`. |
| `SAVE BACKUPS` | off | Keep rollback copies. Adds `BACKUPS` to the START menu. |
| `BACKUPS KEPT` | 5 | Ring size: 3, 5, 10 or 20. |

If autosaving goes quiet, look for `PAUSED` rather than the usual save
indicator: an unresolved save sync conflict holds every write until you answer
the launcher's prompt, and this mod says so once rather than leaving you to
guess. **MODS > SAVE SYNC**, pick a side, and saving resumes.

## Working with save sync

`Game:writeSave()` already notifies the sync engine after every successful
write, so this mod never calls sync directly. The work is in *not* writing at
the wrong moments: nothing happened means nothing written, a transfer in flight
or an unresolved conflict holds the file still until sync settles, and a floor
between writes keeps a burst of door transitions from hammering the file.

## Backups

A backup is an engine checkpoint — the data-only progress snapshot plus your
map, tile, facing and the RNG state — stored in mod storage, which is scoped
per game version *and* per playthrough. It never touches `save.lua`, so keeping
history beside the save costs no revisions and no uploads.

To roll back: **START > BACKUPS**, pick a time, confirm.

## Compatibility

- Mod API 2, `content` profile: link play is unaffected.
- Conflicts with `recomp-autosave` — run one autosave mod, not two.

## Credits

Inspired by [Czajo/gen1recomp-autosave](https://github.com/Czajo/gen1recomp-autosave).
MIT licensed.
