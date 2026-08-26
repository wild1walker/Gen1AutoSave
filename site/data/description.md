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
- **Answers the conflict that is not one.** A save sync conflict whose two
  sides come from the same play session is this device's own lost upload rather
  than a second player, and the mod answers those itself — keep this device —
  so they never reach you. Real disagreements still do.
- **An optional play-time timer**, off by default. Turned on, a long gym battle
  advances it, so `5 MIN` means five minutes of playing rather than five
  minutes of standing on a route. The write itself still waits for a settled
  overworld.
- **A Poke Ball that wobbles** in the top right corner when a save lands, in
  place of a text box across the screen. One tile in from the corner of the
  game itself, which is the window's corner when the map fills it and the
  picture's corner under FAITHFUL RATIO, where the bars around the picture are
  dead display. On the rare save that gets held, the same slot blinks a red
  cross instead. Switchable to a small `SAVED` panel, the classic text box, or
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
| `HEAL CONFLICTS` | on | Answer a "conflict" that is really your own lost upload. |
| `INDICATOR` | POKE BALL | `OFF`, `POKE BALL`, `SAVED TEXT`, or `TEXT BOX`. |
| `SAVE BACKUPS` | off | Keep rollback copies. Adds `BACKUPS` to the START menu. |
| `BACKUPS KEPT` | 5 | Ring size: 3, 5, 10 or 20. |

If autosaving goes quiet, look for the held badge in place of the usual save
indicator — a **flashing red cross** where the Poke Ball would be, or the word
`PAUSED` in the text modes. It means an unresolved save sync conflict **over
the save you are playing** is holding every write. **MODS > SAVE SYNC**, pick a
side, and saving resumes.

Most of the time you will not see it, because most of them are not conflicts.
See [When a conflict is not one](#when-a-conflict-is-not-one) below.

**If that screen looks empty, the conflict has not gone away.** The launcher
draws it from rows the engine holds in memory, and those do not survive a
restart: `SyncEngine` persists `state.pendingConflicts` but builds `conflicts`
empty on load, and empties it again at the start of every sync. So there is a
window after each launch — up to five minutes, until the first sweep runs — and
a shorter one around every sync, where the badge is right and the screen has
nothing on it yet. Give it a moment and look again. The mod's log line names
the conflict it is holding for, with both savedAt stamps, so you can tell which
of the two it means before the screen catches up.

The badge is slow on purpose, and quiet about things that are not yours. It
waits until the conflict has stood for fifteen seconds, and it ignores
conflicts about any *other* playthrough. The engine reports one `phase` for
every save it can see and re-plans from scratch on every sync, so neither
"there is a conflict" nor "there is one this instant" means this file is the
one in dispute.

### When a conflict is not one

**These saves were played at the same time** does not mean two people. It is
`SyncEngine.overlaps`, which asks whether `[sessionStart, savedAt]` on the two
sides overlap — and one `sessionStart` covers a whole play session, because
`Game.sessionStartedAt` is stamped once at load and copied into every save meta
written until you close the game. Two revisions of the same session therefore
overlap by definition, and get described as simultaneous play.

Which is exactly what your own device produces when an upload is committed by
the server but its reply never arrives — a dropped connection, a phone putting
the app to sleep mid-request. `state.revs` stays behind the rev the server now
has, and the next plan sees the save changed on *both* ends: locally because
you kept playing, remotely because that upload did land after all. Nothing on
this side can prevent it; by the time anything could look, the reply is gone.

So the mod recognises it instead. When both sides of a conflict carry the
**same `sessionStart`** and the far side is the **older** of the two, it is one
device's file twice — a second device would have called `os.time()` for its own
session, on its own load — and there is only one honest answer to it. The mod
gives that answer itself, `resolveConflict(key, "local")`, which is precisely
the launcher's `Keep this device` button: point `state.revs` at the rev we
never heard about, force-upload the file you are actually playing, carry on.
Nothing is discarded, because the far copy is the one yours came after.

Anything that fails either half of that test is a real disagreement and is left
alone for you to answer. So is a heal that does not stick: after three goes on
one save the mod stops and puts the badge up. `HEAL CONFLICTS` turns the whole
thing off if you would rather see every one of them.

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
