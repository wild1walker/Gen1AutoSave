# Gen1AutoSave

An autosave mod for gen1recomp that makes manual saving optional, and that is
deliberately careful around the built-in save sync.

## What it does

- **The timer counts play time, not idle time.** A long gym battle advances it,
  so `5 MIN` means five minutes of playing rather than five minutes of standing
  on a route. The write itself still waits for a settled overworld.
- **Saves after things happen** — battles, catches, evolutions, hatches, trades,
  blackouts, entering a new map.
- **Saves when you pick QUIT**, before the confirm box — the last moment the
  game is still running, so the upload it starts gets to finish. The engine's
  own quit writes nothing at all: by then a write can only make a revision
  that never finishes sending, which is half of a "played at the same time"
  conflict.
- **A Poke Ball that wobbles** in the top right corner of the game picture
  when a save lands, in place of a text box across the screen — the picture's
  corner, so it rides the letterboxed image rather than the window, at a
  faithful aspect ratio on a phone as much as on a widescreen desktop.
  Switchable to a small `SAVED` panel, the classic text box, or off.
- **Optional rollback backups** of recent autosaves, reachable from the START
  menu.

Manual saving is untouched: it writes and syncs exactly as it does without this
mod. The only thing that happens here is the timer resetting, so an autosave
does not land on top of a save you just made yourself.

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `AUTO SAVE` | on | Master switch. |
| `INTERVAL` | 5 MIN | Play time between saves. `OFF` leaves only the event and quit saves. |
| `AFTER EVENTS` | on | Save after battles, catches, new areas and so on. |
| `ON QUIT` | on | Save when you pick QUIT, before leaving. |
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
