# Gen1AutoSave

An autosave mod for [gen1recomp](https://github.com/bryanthaboi/gen1recomp) that
makes manual saving optional, and that is deliberately careful around the
built-in save sync.

## Installing

**From the launcher, by index.** In **MODS > FIND MODS**, add the index

```
wild1walker/Gen1AutoSave
```

and the mod shows up as a card you can install and update in place. The repo
page URL, the Pages root and the feed URL itself all resolve to the same
source, so any of them works in that box.

**By hand.** **MODS > Import mod .zip**, using the archive from the
[latest release](../../releases/latest).

Adding an index is a deliberate act of trusting whoever publishes it, and this
one publishes exactly one mod: this one. A listing buys nothing extra either
way — installing from a card runs the same import a .zip does, and the
installer still refuses an archive whose manifest id is not `gen1autosave`.

## What it does

- **The timer counts play time, not idle time.** A long gym battle advances it,
  so `5 MIN` means five minutes of playing rather than five minutes of standing
  on a route. The write itself still waits for a settled overworld.
- **Saves after things happen** — battles, catches, evolutions, hatches, trades,
  blackouts, entering a new map.
- **Saves when you close the game**, unless you are mid-battle, mid-script, or
  save sync still has something in flight. Stepping back to the launcher does
  not save: that path restarts the process, and a write there arms an upload
  the restart then kills half-sent, which is what a "played at the same time"
  conflict is made of.
- **A Poke Ball that wobbles** in the top right corner when a save lands, in
  place of a text box across the screen. Switchable to a small `SAVED` panel,
  the classic text box, or off.
- **Optional rollback backups** of recent autosaves, reachable from the START
  menu.

Manual saving is untouched: it writes and syncs exactly as it does without this
mod. The only thing that happens here is the timer resetting, so an autosave
does not land on top of a save you just made yourself.

![the ball indicator, frame by frame](docs/pokeball-frames.png)

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `AUTO SAVE` | on | Master switch. |
| `INTERVAL` | 5 MIN | Play time between saves. `OFF` leaves only the event and quit saves. |
| `AFTER EVENTS` | on | Save after battles, catches, new areas and so on. |
| `ON QUIT` | on | Save when closing the game. Not when stepping back to the launcher. |
| `INDICATOR` | POKE BALL | `OFF`, `POKE BALL`, `SAVED TEXT`, or `TEXT BOX`. |
| `SAVE BACKUPS` | off | Keep rollback copies. Adds `BACKUPS` to the START menu. |
| `BACKUPS KEPT` | 5 | Ring size: 3, 5, 10 or 20. |

If autosaving goes quiet, look for `PAUSED` rather than the usual save
indicator: an unresolved save sync conflict holds every write until you answer
the launcher's prompt, and this mod says so once rather than leaving you to
guess. **MODS > SAVE SYNC**, pick a side, and saving resumes.

## Working with save sync

`Game:writeSave()` already notifies the sync engine after every successful
write, with a five second upload debounce, so this mod never calls sync
directly. The work is in *not* writing at the wrong moments.

- **Nothing happened, nothing written.** Playtime always advances, so comparing
  save bytes would call every idle minute a change. Instead the engine's own
  events (`world.stepped`, `flag.changed`, `battle.*`, `pokemon.*`, …) mark the
  save dirty, and a clean save is skipped. Leaving the game sitting on a route
  never bumps the save revision or wakes an upload.
- **Never writes mid-sync.** A transfer in flight, or an unresolved conflict
  waiting on you, both hold the file still; the save is retried once sync
  settles. Adding a third revision to a disagreement you have not answered yet
  is how a cross-device conflict gets worse.
- **Floors between writes.** 20 seconds between any two writes, and 60 between
  two *event* saves, so a row of door transitions cannot hammer the file. The
  event floor counts from the last event save rather than from the last save
  of any kind — measured the other way, a battle that ended just after a timer
  save produced nothing for a minute, which reads as never saving after
  battles at all.
- **Nothing is written on the way back to the launcher.** That path is a
  process restart, and the old process lives just long enough after a write
  for the five second upload debounce to start a PUT and then die mid-request.
  The server applies it, the reply dies with the process, and the device keeps
  the old revision — one half of a conflict, with the write itself supplying
  the other. Closing the game has no such window: LÖVE tears the network down
  and nothing is left in flight, so that is where the quit save happens, and
  the upload waits for the next launch.

## Backups

A backup is an engine checkpoint — the data-only progress snapshot plus your
map, tile, facing and the RNG state — stored in `mod.storage`, which is scoped
per game version *and* per playthrough and written atomically. It never touches
`save.lua`, so keeping history beside the save costs no revisions and no
uploads. Old snapshots are deleted as the ring fills.

To roll back: **START > BACKUPS**, pick a time, confirm. The menus unwind before
the rollback applies, because checkpoints need a settled overworld. Once it
lands the mod writes the save immediately, so the file — and the next sync
upload — carries the rolled-back state rather than the newer one it replaced.

Only autosaves become backups. `Checkpoint.inspect` refuses to capture while a
screen is on top, and manual saving happens from inside the START menu.

## Development

Requires `lua5.4`.

```sh
lua5.4 -e "assert(loadfile('main.lua'))"   # syntax
cd tests && lua5.4 test_autosave.lua       # timing, sync gating, quit save
cd tests && lua5.4 test_backups.lua        # ring rotation, menu, rollback
cd tests && lua5.4 test_indicator.lua      # HUD geometry across DPI scales
```

The harnesses stand in fake `game`, `mod.storage`, `mod.checkpoints` and screen
stack objects, so they run without the engine. CI runs all three on every push.

### The mod index feed

`site/data/index.json` is the feed **FIND MODS** reads, generated from
`manifest.json`:

```sh
python3 tools/build_index.py           # rewrite it after a version bump
python3 tools/build_index.py --check   # what CI runs
```

The launcher resolves `owner/repo` to
`https://wild1walker.github.io/Gen1AutoSave/data/index.json` and falls back to
the raw file on `main` when that fails, so the feed works with GitHub Pages
switched off. Turning Pages on for `/site` on `main` just makes the first URL
the one that answers.

Every release publishes the archive twice, versioned and under the fixed name
`gen1autosave.zip`, because the feed's `downloadURL` points at
`/releases/latest/download/gen1autosave.zip`. That is what keeps a static feed
pointing at the newest release; `--check` fails if the workflow stops
publishing it.

To list the mod in the community index at
[bryanthaboi/gen1recomp-mod-index](https://github.com/bryanthaboi/gen1recomp-mod-index)
instead — the one most players already have — use its
[submission helper](https://bryanthaboi.github.io/gen1recomp-mod-index/). The
fields it asks for are the ones already in `manifest.json` and in the feed
entry here.

### Releasing

Push to `main` with the `version` in `manifest.json` bumped ahead of every
existing tag. The release workflow packs the mod, stamps that version into the
archived `manifest.json`, and publishes `gen1autosave-X.Y.Z.zip` as a GitHub
Release. `[release X.Y.Z]` in a commit message, or a manual run with an explicit
version, both override it.

`github` in `manifest.json` points at `wild1walker/Gen1AutoSave`, which is how
the launcher offers updates and other versions.

## Credits

Inspired by [Czajo/gen1recomp-autosave](https://github.com/Czajo/gen1recomp-autosave).

## Licence

MIT — see [LICENSE](LICENSE).
