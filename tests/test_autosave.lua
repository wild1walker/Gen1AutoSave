-- Minimal harness: fake mod host + fake game, drives core.update.
local writes = 0
local vetoed = false

-- SAVE ON LOADS off: this suite drives the ROUTE path, where a due save is
-- written on the map once the overworld settles.  With the row on, a due save
-- waits up to LOAD_WAIT for a warp or a battle to take it on a black screen
-- instead, which is a different contract and has a suite of its own
-- (test_on_load.lua).
local opts = { enabled = true, interval = 300, events = true, onquit = true,
               notify = "icon", heal = true, on_load = false }

local handlers, chains = {}, {}
local schema, boxes = nil, {}
local mod = {
  options = {
    define = function(_, s) schema = s return s end,
    get = function(_, k) return opts[k] end,
  },
  events = { on = function(_, name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
  end },
  hooks = { wrap = function(_, name, fn) chains[name] = fn end },
  log = { info = function() end, warn = function(_, f, e) print("WARN", f, e or "") end },
  ui = {
    TextBox = { new = function(_, text, _, o)
      local box = { text = text, opts = o }
      boxes[#boxes + 1] = box
      return box
    end },
  },
}

local player = { moving = false }
-- Deliberately no `dirHeld` here: this overworld is the shape an engine older
-- than OverworldState:dirHeld has, so the mod has to fall back to asking the
-- raw input whether a direction is down.  test_on_load.lua covers the other
-- half, where the overworld answers for itself.
local ow = { player = player, scriptMoves = {}, runner = nil }
local downButtons = {}
local syncState = { busy = false, phase = "idle", uploadAt = nil,
                    protectedKey = nil, conflicts = nil }
local screens, returned = {}, 0
local game = {
  overworld = ow,
  input = { isDown = function(_, button) return downButtons[button] == true end },
  stack = {
    top = function() return screens[#screens] or ow end,
    push = function(_, s) screens[#screens + 1] = s end,
    pop = function() return table.remove(screens) end,
  },
  -- QUIT goes back to the title in-process, so this is where a quit lands
  returnToTitle = function()
    returned = returned + 1
    screens = {}
  end,
  writeSave = function()
    if vetoed then return false end
    writes = writes + 1
    -- Game:writeSave notifies sync, which arms its upload debounce
    syncState.uploadAt = 5
    return true
  end,
  -- reads come from syncState, writes go back to it, so the mod disarming
  -- engine.uploadAt is visible to the test rather than lost on a temporary
  syncEngine = function()
    return setmetatable({}, {
      __index = function(_, k)
        if k == "busy" then return function() return syncState.busy end end
        return syncState[k]
      end,
      __newindex = function(_, k, v) syncState[k] = v end,
    })
  end,
}

loadfile("../main.lua")()(mod)

local function emit(name, ev) for _, fn in ipairs(handlers[name] or {}) do fn(ev) end end
local function run(seconds, dt)
  dt = dt or 1 / 60
  local t = 0
  while t < seconds do chains["core.update"](function() end, game, dt) t = t + dt end
end

local function check(label, cond)
  print((cond and "PASS  " or "FAIL  ") .. label)
end

-- 0. what the mod ships with.  The timer is OFF: the events below cover
-- ordinary play, and the QUIT confirm covers the way out.
local defaults = {}
for _, opt in ipairs(schema or {}) do defaults[opt.key] = opt.default end
check("AUTO SAVE ships on", defaults.enabled == true)
check("INTERVAL ships OFF", defaults.interval == 0)
check("AFTER EVENTS ships on", defaults.events == true)
check("ON QUIT ships on", defaults.onquit == true)
check("HEAL CONFLICTS ships on", defaults.heal == true)

-- 1. idle with nothing happening never writes
run(400)
check("idle 400s with no events -> no write", writes == 0)

-- 2. once something happened, the timer fires
emit("save.writing")          -- baseline: pretend the player just saved
emit("world.stepped")
run(299)
check("timer has not fired early", writes == 0)
run(3)
check("timer fires after the interval", writes == 1)

-- 3. after that write, an untouched save is skipped again
run(400)
check("no second write without new activity", writes == 1)

-- 4. an event right after a write still respects the file's own floor, but a
-- manual save is not an event save and no longer holds one off for a minute
emit("save.writing")
emit("world.stepped")
emit("pokemon.caught")
run(15)
check("event save waits out MIN_GAP", writes == 1)
run(10)
check("event save lands once MIN_GAP has passed", writes == 2)

-- 5. no write while the overworld is busy
emit("world.stepped")
player.moving = true
run(400)
check("never writes while the player is moving", writes == 2)
player.moving = false
run(2)
check("writes once the overworld settles", writes == 3)

-- 6. no write while sync is transferring or in conflict
emit("world.stepped")
syncState.phase = "conflict"
run(400)
check("holds off during a sync conflict", writes == 3)
syncState.phase = "idle"
run(5)
check("resumes after the conflict clears", writes == 4)

-- 6b. a conflict is a standing hold with no timeout, so it gets said out loud
-- once -- silence here is indistinguishable from the mod having died, which
-- is what "it stopped saving after battles" actually is.
local warns, lastWarn = 0, nil
mod.log.warn = function(_, fmt, ...)
  warns = warns + 1
  lastWarn = select("#", ...) > 0 and string.format(fmt, ...) or fmt
end
emit("world.stepped")
syncState.phase = "conflict"
run(400)
check("still no write while the conflict stands", writes == 4)
check("the hold is reported once", warns == 1)
run(400)
check("and not once per frame after that", warns == 1)
syncState.phase = "idle"
run(30)
check("writes again once the conflict clears", writes == 5)

-- a transfer is seconds, not indefinite: it stays quiet
emit("world.stepped")
syncState.busy = true
run(400)
check("a transfer in flight is not announced", warns == 1)
syncState.busy = false
run(30)
check("and the write lands when it finishes", writes == 6)

-- 6b-2. WHOSE conflict is it?  engine.phase is one word for the whole engine,
-- but the planner raises a row per key over every local save it can see, so an
-- old playthrough in dispute on another device turned the phase to "conflict"
-- and stopped THIS game saving -- about a prompt with nothing to do with it.
-- protectedKey is the save being played; the rows say which are in dispute.
syncState.protectedKey = "red/now-playing"
syncState.conflicts = { { key = "red/some-other-run" } }
syncState.phase = "conflict"
run(30)                       -- clear MIN_GAP after the last write
local before = writes
emit("battle.ended")
run(30)
check("a conflict over another save does not hold this one", writes == before + 1)
check("and is not announced", warns == 1)

-- our own key in that same list is still a hold, and still gets said
syncState.conflicts = { { key = "red/some-other-run" }, { key = "red/now-playing" } }
run(30)
before = writes
emit("battle.ended")
run(60)                       -- past HOLD_GRACE
check("a conflict over this save does hold it", writes == before)
check("and that one is announced", warns == 2)
syncState.phase = "idle"
syncState.conflicts = nil
run(30)
check("and the write lands once it clears", writes == before + 1)

-- 6b-3. A conflict that does not stand is not worth telling anyone about.
-- SyncEngine:syncNow() empties its conflict list and re-plans, and the upload
-- debounce path in SyncEngine:update() reaches it with no phase guard at all,
-- so a conflict can come and go with nobody answering anything.  Said on the
-- first frame, that blip is a badge about a launcher prompt that is already
-- gone by the time the player goes to look for it.
local HOLD_GRACE = 15         -- mirrors main.lua
run(30)                       -- clear MIN_GAP
before = writes
syncState.phase = "conflict"
emit("battle.ended")
run(HOLD_GRACE - 5)
check("a conflict shorter than the grace says nothing", warns == 2)
check("though it still holds the write while it lasts", writes == before)
syncState.phase = "idle"
run(30)
check("and the held write lands as soon as it clears", writes == before + 1)

-- and the next blip starts its own grace rather than inheriting that one's
run(30)
before = writes
syncState.phase = "conflict"
emit("battle.ended")
run(HOLD_GRACE - 5)
check("the next short hold starts its grace over", warns == 2)
syncState.phase = "idle"
run(30)
check("and it lands too", writes == before + 1)

-- a conflict that really does stand still gets said, on the far side of both
run(30)
before = writes
syncState.phase = "conflict"
emit("battle.ended")
run(400)
check("a standing conflict is still announced", warns == 3)
check("and still holds the file", writes == before)
syncState.phase = "idle"
run(30)
check("and still resumes when it clears", writes == before + 1)

-- 6b-4. And it says WHICH conflict.  "A conflict is standing" is not something
-- a player can go and check -- least of all while the launcher's SAVE SYNC
-- screen is still empty, which it is from every launch until the first sweep
-- runs (SyncEngine builds eng.conflicts empty on load and never restores
-- state.pendingConflicts into it).  The two savedAt stamps are the same line
-- that screen shows once it catches up.
local function at(hour, min)
  return os.time({ year = 2026, month = 8, day = 25, hour = hour, min = min,
                   sec = 0 })
end
run(30)
before = writes
syncState.conflicts = {
  { key = "red/some-other-run", localMeta = { savedAt = at(9, 0) } },
  { key = "red/now-playing",
    localMeta = { savedAt = at(21, 42) },
    remoteMeta = { savedAt = at(21, 37) } },
}
syncState.phase = "conflict"
emit("battle.ended")
run(400)
check("the held line names the key in dispute",
  (lastWarn or ""):find("red/now%-playing") ~= nil)
check("and this device's stamp", (lastWarn or ""):find("21:42") ~= nil)
check("and the other device's", (lastWarn or ""):find("21:37") ~= nil)
check("and not the row that is none of our business",
  (lastWarn or ""):find("some%-other%-run") == nil)
check("and it is still holding the file", writes == before)
syncState.phase = "idle"
syncState.conflicts = nil
syncState.protectedKey = nil
run(30)
check("and still resumes after that one clears", writes == before + 1)

-- 6b-5. The conflict that is not one.  SyncEngine.overlaps compares
-- [sessionStart, savedAt] on the two sides, and ONE sessionStart covers a whole
-- play session -- so this device's own lost upload always reads as "played at
-- the same time".  Both sides carrying the SAME sessionStart is the tell: a
-- second device calls os.time() for its own, on its own load.
local resolved = {}
local function selfRow(mine, theirs, session)
  return { { key = "red/now-playing",
             localMeta = { sessionStart = session, savedAt = mine },
             remoteMeta = { sessionStart = session, savedAt = theirs } } }
end
local session = at(21, 10)
syncState.resolveConflict = function(_, key, choice)
  resolved[#resolved + 1] = { key = key, choice = choice }
  syncState.phase = "idle"          -- what the launcher's button gets to
  syncState.conflicts = nil
  return true
end

run(30)
local w0 = warns
before = writes
syncState.protectedKey = "red/now-playing"
syncState.conflicts = selfRow(at(21, 42), at(21, 37), session)
syncState.phase = "conflict"
emit("battle.ended")
run(60)
check("a self-conflict is answered, not held", #resolved == 1)
check("with keep-this-device", resolved[1].choice == "local")
check("on the key we are playing", resolved[1].key == "red/now-playing")
check("nothing was said about it", warns == w0)
check("and the write it was holding lands", writes == before + 1)

-- two real sessions is a real disagreement: left alone, badge and all
run(30)
resolved, w0, before = {}, warns, writes
syncState.conflicts = { { key = "red/now-playing",
  localMeta = { sessionStart = at(21, 10), savedAt = at(21, 42) },
  remoteMeta = { sessionStart = at(9, 0), savedAt = at(21, 37) } } }
syncState.phase = "conflict"
emit("battle.ended")
run(400)
check("two sessions is not ours to answer", #resolved == 0)
check("so it is still held", writes == before)
check("and still said", warns == w0 + 1)
syncState.phase = "idle"
syncState.conflicts = nil
run(30)

-- one session, but the far side is AHEAD of us: not a superseded upload, so
-- not something keep-this-device is obviously right about
resolved, w0, before = {}, warns, writes
syncState.conflicts = selfRow(at(21, 37), at(21, 42), session)
syncState.phase = "conflict"
emit("battle.ended")
run(400)
check("a far side ahead of ours is not answered either", #resolved == 0)
check("and is held", writes == before)
syncState.phase = "idle"
syncState.conflicts = nil
run(30)

-- HEAL CONFLICTS off puts every one of them back in front of the player
resolved, w0, before = {}, warns, writes
opts.heal = false
syncState.conflicts = selfRow(at(21, 42), at(21, 37), session)
syncState.phase = "conflict"
emit("battle.ended")
run(400)
check("HEAL CONFLICTS off answers nothing", #resolved == 0)
check("and holds as it used to", writes == before)
opts.heal = true
syncState.phase = "idle"
syncState.conflicts = nil
run(30)

-- a heal that will not stick is capped, and then it is a hold like any other
resolved, w0, before = {}, warns, writes
syncState.resolveConflict = function(_, key, choice)
  resolved[#resolved + 1] = { key = key, choice = choice }
  return true                       -- says yes, changes nothing: back it comes
end
syncState.conflicts = selfRow(at(21, 42), at(21, 37), session)
syncState.phase = "conflict"
emit("battle.ended")
run(400)
check("a heal that does not take is capped at three", #resolved == 3)
check("and then it is a hold like any other", writes == before)
check("which does get said", warns == w0 + 1)
syncState.phase = "idle"
syncState.conflicts = nil
syncState.protectedKey = nil
syncState.resolveConflict = nil
run(30)
check("and clears when the conflict does", writes == before + 1)

-- 6c. Events are floored by MIN_GAP and nothing else.  There was a second and
-- longer floor between two EVENT saves, which held a row of doors to one save
-- a minute -- and with the timer off by default, that reads as map entry not
-- being a save trigger at all.
run(30)                       -- clear MIN_GAP after the last write
emit("world.stepped")
run(400)                      -- a timer save lands
local afterTimer = writes
emit("battle.ended")          -- a wild battle ends right on its heels
run(25)                       -- past MIN_GAP
check("a battle just after a timer save still saves", writes == afterTimer + 1)

emit("map.entered")           -- and a door straight after the battle
run(3)
check("a door right after a battle save saves too", writes == afterTimer + 2)

emit("map.entered")           -- but two inside the floor are still one write
run(5)
check("a second door inside MIN_GAP is held", writes == afterTimer + 2)
run(20)
check("and lands once MIN_GAP has passed", writes == afterTimer + 3)

-- 6d. the reported symptom, end to end: with the timer off, walking a row of
-- rooms saved at almost none of them.  Every door past the floor saves now.
opts.interval = 0
emit("save.loaded")           -- a fresh session, as after CONTINUE
local doors = writes
for _ = 1, 4 do
  emit("map.entered")
  run(21)
end
check("with the timer off, four doors are four saves", writes == doors + 4)
opts.interval = 300

-- 7. a manual save resets the clock
local beforeManual = writes
emit("world.stepped")
run(100)
emit("save.writing")
run(250)
local base = writes
check("manual save restarts the interval", base == beforeManual)

-- 8. the save moved off the quit hook and into the QUIT confirm, which is the
-- last moment the game is still running: a write inside the quit itself can
-- only make a revision nothing finishes sending, which is half a conflict.
-- The box says it is going to save, YES saves, and the quit then waits for
-- the write and for the upload it starts.
local function startMenu()
  local items = { { label = "QUIT", onSelect = function() return "quit" end } }
  return chains["ui.start_menu.items"](function(_, i) return i end, game, items)
end
local function quitRow()
  for _, item in ipairs(startMenu()) do
    if item.label == "QUIT" then return item end
  end
end
local function lastBox() return boxes[#boxes] end

emit("world.stepped")
check("the QUIT row is still there", quitRow() ~= nil)
quitRow().onSelect()
check("picking QUIT writes nothing on its own", writes == base)
check("it asks first, and says what YES will do",
  lastBox() ~= nil and lastBox().text:find("SAVE") ~= nil)
check("the confirm still defaults to NO", lastBox().opts.defaultNo == true)

-- NO is the vanilla answer to a vanilla question: nothing saved, nothing quit
lastBox().opts.choice(false)
run(1)
check("answering NO writes nothing", writes == base)
check("answering NO does not quit", returned == 0)

-- YES: the box goes up, the save lands behind it, and the quit holds for the
-- upload the write just armed
quitRow().onSelect()
lastBox().opts.choice(true)
run(0.2)
check("YES puts a saving box up", lastBox().text == "Now saving...")
check("nothing is written until it has typed out", writes == base)
lastBox().opts.stay.onShown()
run(0.1)
check("the save lands behind the box", writes == base + 1)
check("and the quit waits on the upload", returned == 0)
syncState.uploadAt = nil      -- the upload goes
run(0.1)
check("the quit follows it once sync is done", returned == 1)
check("and the box went with the stack", #screens == 0)

-- nothing changed since, so there is nothing to offer: the engine's own
-- prompt goes up untouched and the row does exactly what it always did
local boxesSoFar = #boxes
check("a clean save falls through to the vanilla QUIT",
  quitRow().onSelect() == "quit")
check("with no box of ours in front of it", #boxes == boxesSoFar)

-- an upload that never lands must not strand the player in front of the box
emit("world.stepped")
quitRow().onSelect()
lastBox().opts.choice(true)
run(0.2)
lastBox().opts.stay.onShown()
run(1)
check("the save still lands", writes == base + 2)
run(20)                       -- uploadAt is never cleared this time
check("a stuck upload times the quit out instead of trapping it", returned == 2)

-- the engine's own quit hook no longer writes at all, either way out
local quits = writes
emit("world.stepped")
local okQ = chains["core.quit_to_launcher"](function() return false end)
check("closing the game writes nothing now", writes == quits)
check("the quit verdict is passed through", okQ == false)
local okL = chains["core.quit_to_launcher"](function() return true end)
check("stepping back to the launcher writes nothing either", writes == quits)
check("the launcher verdict is passed through", okL == true)

-- but it does disarm an upload the exit would otherwise cut open
syncState.uploadAt = 12.5
chains["core.quit_to_launcher"](function() return false end)
check("a scheduled upload is disarmed on the way out", syncState.uploadAt == nil)

-- 9. sync still shapes the offer.  A conflict is the one thing this mod never
-- writes under, so it promises nothing and hands QUIT back to the engine; a
-- transfer in flight is only a reason to wait, so the save is still offered.
syncState.uploadAt = nil
emit("world.stepped")
syncState.phase = "conflict"
local boxCount = #boxes
check("a conflict falls through to the vanilla QUIT",
  quitRow().onSelect() == "quit")
check("and puts no box of ours up", #boxes == boxCount)
check("and writes nothing", writes == quits)
syncState.phase = "idle"

syncState.busy = true
quitRow().onSelect()
lastBox().opts.choice(true)
run(0.2)
lastBox().opts.stay.onShown()
run(1)
check("no quit save while a transfer is in flight", writes == quits)
syncState.busy = false
run(0.1)
check("the write lands once the transfer finishes", writes == quits + 1)
syncState.uploadAt = nil
run(0.1)
check("and the quit follows it", returned == 3)

-- 10. a vetoed write does not spin
local settled = writes
vetoed = true
emit("world.stepped")
run(400)
check("vetoed write is not retried in a loop", writes == settled)
vetoed = false

-- 11. disabled does nothing
opts.enabled = false
emit("world.stepped")
run(400)
check("disabled writes nothing", writes == settled)
opts.enabled = true

-- 5b. and not into the gap between two strides
--
-- `moving` drops for one frame between strides, so a player who never stops
-- walking passes the check above several times a second -- which is exactly
-- where a dropped frame is seen.  A held direction says the next stride starts
-- on the next frame.  Read off the raw input here, since this overworld has no
-- dirHeld to ask.
emit("world.stepped")
run(25)
local beforeStride = writes
emit("pokemon.caught")
downButtons.left = true
player.moving = false
run(400)
check("never writes between two strides of a walk", writes == beforeStride)
downButtons.left = false
run(2)
check("and writes the moment the pad is let go", writes == beforeStride + 1)

