<p align="center">
  <a href="https://wild1walker.github.io/Gen1Wild/"><img src="docs/banner.png" alt="Gen1Wild" width="400"></a>
</p>

<h1 align="center">Gen1AutoSave</h1>

<p align="center">
  <a href="https://wild1walker.github.io/Gen1Wild/"><img src="docs/lineup.png" alt="Check out my other mods!" width="880"></a>
</p>

<p align="center">
  <b>Manual saving, made optional</b><br>
  An autosave mod for <a href="https://github.com/bryanthaboi/gen1recomp">gen1recomp</a>
  that is deliberately careful around the built-in save sync.
</p>

<p align="center">
  <img src="docs/pokeball-frames.png" alt="the save indicator, frame by frame: a Poke Ball wobbling, and a cross blinking" width="820"><br>
  <i>The save indicator, frame by frame, in the screen's top right corner
  instead of a text box across the playfield: a Poke Ball that wobbles when a
  save lands, and a cross that blinks when one is held.<br>
  Drawn from main.lua by <code>tools/logo/frames.py</code>.</i>
</p>

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
| `SAVE ON LOADS` | on | Save in a moment you could not move in: a door, a battle, a menu. |
| `QUIET SYNC` | on | Keep a sync cycle out of the frames you are walking through. |
| `INDICATOR` | POKE BALL | `OFF`, `POKE BALL`, `SAVED TEXT`, or `TEXT BOX`. |
| `SAVE BACKUPS` | off | Keep rollback copies. Adds `BACKUPS` to the START menu. Roughly triples what a save costs — see below. |
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
write, with a five second upload debounce, so this mod never calls sync
directly. The work is in *not* writing at the wrong moments.

- **Nothing happened, nothing written.** Playtime always advances, so comparing
  save bytes would call every idle minute a change. Instead the engine's own
  events (`world.stepped`, `flag.changed`, `battle.*`, `pokemon.*`, …) mark the
  save dirty, and a clean save is skipped. Leaving the game sitting on a route
  never bumps the save revision or wakes an upload.
- **Never writes mid-sync.** A transfer in flight, or an unresolved conflict
  waiting on you *about this save*, both hold the file still; the save is
  retried once sync settles. Adding a third revision to a disagreement you have
  not answered yet is how a cross-device conflict gets worse — but the engine's
  `phase` is one word for every save it can see, and a conflict about an old
  playthrough on another device is not this file's business, so the hold is
  matched against `protectedKey` rather than taken at the phase's word.
- **One floor between writes.** 20 seconds between any two, whatever asked
  for them, so a row of door transitions cannot hammer the file. There used to
  be a second and longer floor between two *event* saves, from when the timer
  did the steady work and events only had to catch what it missed. Now that
  the events are the mechanism, that minute meant walking through a row of
  rooms and saving at none of them — which reads exactly like map entry not
  being a save trigger at all.
- **Nothing is written inside the quit itself**, either way out of it. A write
  there can only make a revision nothing survives to finish sending: the
  server applies the PUT, the reply dies with the process, and the device
  keeps the old revision — one half of a conflict, with the write supplying
  the other. So the quit save happens in the `QUIT` confirm instead, while
  there is still a game running to carry the upload through — and that quit
  waits for the upload rather than racing it. The five second upload debounce
  is pulled forward while you wait, since it is there to coalesce a burst of
  writes and no burst is coming; a save that cannot be sent inside fifteen
  seconds stops holding the quit, because `QUIT` goes to the title rather than
  out of the process and an upload still running finishes there. All the quit
  hook does now is disarm an upload that was scheduled but not started, so the
  exit cannot cut one open; the next launch uploads it as an ordinary change.
- **One upload woken per five minutes, not one per save.** Planning a sync runs
  on the main thread, and it reads and *decodes* every save slot of every game
  version before any of it reaches a worker — through the restricted-grammar
  reader, which is a character-at-a-time parser written in Lua on purpose, so a
  tampered save fails to parse instead of executing. A quarter-megabyte slot
  costs tens of milliseconds, per slot on disk, across six versions, and a
  phone is worse. Waking that on every autosave — as often as every 20 seconds,
  with `AFTER EVENTS` on — was the loudest thing this mod did to a linked
  device. So an autosave wakes an upload at most every five minutes. Writes in
  between still land on disk; the engine's own five minute sweep carries them
  up, because planning compares each slot's `savedAt` against the revision it
  last saw and uploads anything that moved. Picking `QUIT` is exempt: there is
  no sweep coming for a game that is about to stop running, so that upload has
  to go now or never.

## The frame after a save

### What a save actually costs

Measured on a 45 MB heap under LuaJIT, with a 182 KB save file:

| | |
| --- | --- |
| `SaveSerializer.encode` (the engine's, unavoidable) | **9.6 ms** |
| the file writes (`.bak` read, then three writes of the blob) | under 1 ms on a desktop; a phone's flash is slower |
| `SAVE BACKUPS` on: two deep copies plus a second serialize | **+16 ms** |

So a plain autosave is about ten milliseconds of real work, and the mod's job is
to put it where nobody is looking — which is what the windows below are for.

### The collector, and a mistake this mod made for a long time

One encode allocates about **2.8 MB** of short-lived strings and tables. That is
a lot for one frame, and the temptation is to pay it off immediately.

This mod used to do that with 12 collector steps of 4096 KB each. Up to 48 MB of
allocation credit — which on any heap a Game Boy game has is not a nudge, it is
a **complete collection cycle, in one frame, after every single save**. Measured
over 30 save cycles with twenty seconds of ordinary frames between them, the
median frame a save landed in:

| | save frame |
| --- | --- |
| 12 × step 4096 — what this used to do | **53.0 ms** |
| no nudge at all | 14.3 ms |
| 2 × step 512 — what it does now | **10.5 ms** |

And it bought almost nothing. The worst frame in the twenty seconds *after* a
save is 4.1 ms with the old burst, 5.9 ms with the small nudge, 10.2 ms with no
nudge at all. The burst was spending forty milliseconds a save to move at most
six milliseconds off some later frame. On a phone every one of those numbers is
three to five times larger, and that was the stutter.

The reason a small nudge is enough is that **the engine is already doing this**.
`Game:update` ends on `collectgarbage("step", 1)` every rendered frame, and its
own comment says why: to spread collection out "so the default lazy schedule
never batches it into a visible pause". The collector was never falling behind.
What it needed was a little extra credit for the one frame that allocated far
more than a frame usually does — 2 × 512 KB, stopping early if the cycle
finishes — and nothing more.

A sync cycle leaves a bigger debt, since planning decodes every slot into a full
table again. It gets the same small nudge, on a frame the screen is not moving.

### Saving on a screen you cannot see

The write is not what you feel; where its frame lands is. On the route that
frame is a stutter in the middle of walking, which is the one place a dropped
frame shows.

The game already blacks the screen out twice for its own reasons — a warp fades
out, swaps the map and fades back, and a battle ends behind a hold and a fade.
Nobody can see a frame during either. So `SAVE ON LOADS` holds a due save until
one of those comes round and writes it there: the loading screen is a few frames
longer, and nothing else changes.

It writes on **`map.entered`**, not `map.exited`. Exited fires at the top of
`setMap`, before the new map is loaded, so a save written there records the map
you just left and the spot you left it from. Entered fires once the new map, your
cell and your facing are all in place, with the transition still up — coherent
state, screen still covered.

#### A route seam is not a door

Not every map change has a screen in front of it, and the engine says which is
which: `map.entered` carries a `via`, and only some of its words mean the screen
went black.

| `via` | |
| --- | --- |
| `warp` | a door, stairs, a cave mouth, a mod's own warp — **has a screen** |
| `fly` | FLY, which has an animation of its own — **has a screen** |
| `connection` | a route seam: seamless, no screen at all |
| `reload` | a mod rebuilding the map under your feet, in place |
| `boot` / `continue` | the game has just started; there is nothing new to write |

Walking from Route 1 into Viridian is a `connection`. The routes are stitched
together — the map simply scrolls on, and you are mid-stride the whole way
across. That matters twice over. It is the exact frame this mod exists to keep
a write out of, and **it is not a checkpoint either**: crossing from one route
to the next while running is not progress worth stopping for, it is running.

So a seam neither writes a save nor asks for one. A save that was already due
stays due and goes at the next real window. An engine too old to say anything
at all gets the old answer, so a build that predates `via` cannot silently stop
saving at doors.

Waiting is not on a clock. There used to be a 45-second cap here, on the
reasoning that a player who had not warped or fought in that long was standing
somewhere quiet and a save on the route beat no save. It did not check that they
had *stopped*, so what it actually did was give up and write into a stride —
the one frame this whole path exists to avoid, arriving reliably rather than by
accident.

#### The windows

A warp and the end of a battle are two of them, and they were the only two for
a while, which made a due save wait longer than it had to. The real rule is
wider: **any moment you could not move if you wanted to** is a moment worth
spending a frame in, and the game gives you a lot of them.

| Window | Why |
| --- | --- |
| A warp, or FLY | The screen is already black; `map.entered`, so the new map, cell and facing are all in place. A route seam is **not** one of these — see above |
| A battle starting | Behind its own intro, and the save is of the overworld you left |
| A battle ending | The return hold, before the fade back |
| A text box, while an NPC talks | You are being held still by the conversation |
| The START menu, the bag, the party, a PC, a mart, a Center's heal | Same — anything over the overworld |
| Standing still | A *real* stop, not a pause |

Nothing here is a list of named events. Something over the overworld is
something holding you still, so the stack answers all of the middle rows at
once — including the ones this table does not name.

Two of them are held back on purpose. **Inside** a battle nothing is written:
Gen 1 has no save there and neither has this, because the file would record the
overworld the fight started from while you are somewhere else entirely. And
**part-way through a script** nothing is written either — a script that has set
some of its flags and not the rest is not a state to write down, and a save
taken there can drop you back into a half-finished cutscene. The moment a
script *ends* is a window, and by then it is finished and you are standing
where it left you.

#### What counts as standing still

Not `moving == false`: that flag drops for the single frame between two
strides, so somebody walking a long route without stopping satisfies it several
times a second, and that gap is precisely where a dropped frame is seen — the
screen is scrolling on both sides of it.

Not one frame of not-walking either. Letting go of the pad to change direction,
lining up on a doorway, thinking for a second: all of those look identical to a
stop and none of them is one. A stop is **three unbroken seconds** of standing
there — or the moment a menu closed or a conversation ended and you have not
started moving again, which is a window of its own for a second and a half.

Every other rule still applies on a loading screen: the floor between writes, a
live sync transfer, an unresolved conflict and a player still mid-step all
refuse it exactly as they would anywhere else.

### And where the last of it lands

Pacing chose how *often* a cycle runs. It could not choose *when* the expensive
part of one happens, and that is the half you actually feel. The plan is built
against the server's **reply**, not against the request: the engine polls the
handle each frame, and the frame the answer arrives on is the frame that
decodes every slot. So the stall lands on network time — a moment set by
latency and the server, with no relation to anything you did. That is exactly
why it reads as the game hiccupping rather than as the game syncing: nothing on
screen caused it, and nothing on screen explains it. The engine's own five
minute sweep lands the same way, and the pacing above never touched that one.

That work cannot be made cheap from here. It can be made to land where it does
not show. A frame dropped while you are standing still, in a menu, reading a
box or in a battle is a frame nobody sees; the same frame dropped mid-step is a
visible stutter, because the walk cycle and the camera are both part-way
between tiles and both jump when one frame is worth two.

So `QUIET SYNC` holds a cycle that has a reply in hand out of the frames you are
walking through, and runs it in the next window — the same windows above, plus
the two the write is barred from. A battle is a fine frame to spend and a
terrible one to save in; the sync takes it, the write does not.

**The write is not waiting for the sync, and the sync is not waiting for the
write.** Those are two errands and pairing them was costing both: the write is
cheap and wants the first window it can get, the cycle it wakes is expensive and
does not arrive for another few seconds. So the save goes down at the door you
walked through, and the cycle takes whatever comes next — the next door, the
next battle, the next conversation, or you stopping.

Only when a reply is actually in flight: the cheap tick that *starts* a cycle is
never held, since holding it would stop the engine's clock for no reason.

"Walking" is the same question the write asks, and it has to be asked the same
way. This used to read the player's `moving` flag alone, which drops for the
single frame between two strides — so someone walking a long route without
stopping offered the hold an opening several times a second, and the plan took
it, landing in the exact frame the hold exists to protect. A held direction
counts as walking now, and so does a one-frame pause in the middle of one.

There is no cap on the hold either. There was one — three seconds, so that
holding a direction across Route 21 could not starve sync — and it did not check
that you had stopped: it counted to three and ran the plan wherever it landed.
Between the two, the stall a moment after every save was not an edge case, it
was the ordinary path. Holding costs nothing but time: the reply is already in
hand, the engine's own clock stops with the hold so nothing fires early to make
the time back, and letting go of the pad releases it on the next frame.

The debt a finished cycle leaves behind waits for the same kind of frame. The
plan is kept out of a walk, but the transfer that follows it completes on
network time and answers to nothing, and a burst of collector steps landing in
the middle of a stride is the same stutter by another route. So it is
remembered and paid on the first frame that is not a moving screen.

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

By **Wild**. Written for this mod rather than derived from anyone else's — it
is built on the save, battle and map-transition hooks of
[Pokemon Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), which is what
it listens to and all it takes from anywhere.

**Pokemon** Red, Blue and Yellow are Nintendo / Creatures / GAME FREAK. This is
an unofficial fan mod, distributed free, with no affiliation with or
endorsement by any of them.

## Licence

MIT — see [LICENSE](LICENSE).
