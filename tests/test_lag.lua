-- What an autosave costs AFTER the write: the collector catching up on the
-- garbage the write made, and the sync upload it armed.  Both used to land a
-- second or two later, in a frame that is just ordinary walking.
--
-- Minimal harness: fake mod host + fake game, drives core.update.
local writes = 0
local emit                       -- forward: writeSave below emits through it

-- SAVE ON LOADS off: what a write costs AFTER it lands is the subject here,
-- and it costs the same whichever screen it landed on.  Driving the route path
-- keeps the save() helper below a plain "ask, then step to the frame it writes
-- on" rather than one that has to stage a warp first.
local opts = {
  enabled = true, interval = 0, events = true, onquit = true,
  notify = "icon", backups = false, on_load = false,
}

local handlers, chains = {}, {}
local boxes = {}
local mod = {
  options = {
    define = function(_, s) return s end,
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
-- A held direction, which is what the engine's OverworldState:dirHeld answers.
-- It matters here as much as it does to the write: `moving` is false for the
-- single frame between two strides, so a player who never stops walking offers
-- an opening several times a second, and that frame is the stutter.
local held = false
local ow = { player = player, scriptMoves = {}, runner = nil,
             dirHeld = function() return held end }
-- SyncEngine.UPLOAD_DEBOUNCE, mirrored: writeSave arms uploadAt this far out.
local SYNC_UPLOAD_DEBOUNCE = 5
local syncState = { busy = false, phase = "idle", uploadAt = nil, clock = 100 }
local screens, returned = {}, 0
local noEngine = false
local vetoed = false
local game = {
  overworld = ow,
  stack = {
    top = function() return screens[#screens] or ow end,
    push = function(_, s) screens[#screens + 1] = s end,
    pop = function() return table.remove(screens) end,
  },
  returnToTitle = function()
    returned = returned + 1
    screens = {}
  end,
  -- Faithful to Game:writeSave, and the fidelity that matters here is the
  -- ORDER: writeSave emits save.writing to mods first and only then tells the
  -- sync engine, which arms the five second upload debounce -- so the debounce
  -- is modelled off the engine's own clock here rather than as a bare number,
  -- because "the upload was pulled forward to now" is a claim about that
  -- arithmetic and a constant cannot express it.
  writeSave = function()
    emit("save.writing")
    -- a veto (another mod's save.write hook returning false) still cost the
    -- frame it took to get here
    if vetoed then return false end
    writes = writes + 1
    syncState.uploadAt = (syncState.clock or 0) + SYNC_UPLOAD_DEBOUNCE
    return true
  end,
  -- reads come from syncState, writes go back to it, so the mod disarming
  -- engine.uploadAt is visible to the test rather than lost on a temporary
  syncEngine = function()
    if noEngine then return nil end
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

function emit(name, ev) for _, fn in ipairs(handlers[name] or {}) do fn(ev) end end
local function run(seconds, dt)
  dt = dt or 1 / 60
  local t = 0
  while t < seconds do chains["core.update"](function() end, game, dt) t = t + dt end
end

local function check(label, cond)
  print((cond and "PASS  " or "FAIL  ") .. label)
end


-- The most allocation credit the nudge after a write may ask the collector
-- for, in KB, over all of its steps.
--
-- This is the assertion that matters, not the step count.  `collectgarbage
-- ("step", n)` asks the collector to work as if n KB had been allocated, so
-- steps x size is a budget -- and a budget the size of the heap is a COMPLETE
-- collection cycle, in one frame, after every single save.  This was 12 x
-- 4096, which is 48 MB of credit: a full cycle on any heap a Game Boy game
-- has, and measured at 53 ms in the frame the save landed in against 10 ms
-- for the nudge that replaced it.
--
-- One encode of a 182 KB save allocates about 2.8 MB, and the engine already
-- steps the collector on every rendered frame of its own accord
-- (Game:update, collectgarbage("step", 1)).  So the ceiling here is a nudge,
-- not a cycle.  If a future edit puts the burst back, this fails.
local GC_BUDGET_KB = 2048

-- The collector, watched.  The mod looks `collectgarbage` up as a global at
-- call time, so swapping it here is enough to see every step it asks for --
-- and how big each one was.
-- The engine's frame pacer, watched.  A hitch inside a logic step makes the
-- next dt huge, and FixedStep pays that back as a burst of steps before the
-- next draw -- which over a warp's fade is not a fade, it is a cut.  The mod
-- is supposed to arm the engine's own clamp after anything of its own that
-- costs a frame; this counts the calls.
local catchupDiscards = 0
package.loaded["src.core.FixedStep"] = {
  discardCatchup = function() catchupDiscards = catchupDiscards + 1 end,
}

local realGC = collectgarbage
local gcSteps, gcCredit, gcFinishAfter, gcBoom = 0, 0, 1, false
collectgarbage = function(what, arg)
  if what ~= "step" then return realGC(what, arg) end
  if gcBoom then error("collector said no") end
  gcSteps = gcSteps + 1
  gcCredit = gcCredit + (tonumber(arg) or 0)
  return gcFinishAfter ~= nil and gcSteps >= gcFinishAfter
end

-- Ask for a save and stop on the frame it lands: what happens in the seconds
-- AFTER a write is the whole subject here, so a run that overshoots would
-- test the wrong frames.  MIN_GAP is 20s, so this is never more than a few
-- hundred frames.
local function save()
  -- map.entered is both a "something changed" event and a checkpoint, so one
  -- emit both dirties the save and asks for a write
  emit("map.entered")
  local before, frames = writes, 0
  while writes == before and frames < 60 * 400 do
    chains["core.update"](function() end, game, 1 / 60)
    frames = frames + 1
  end
  return writes > before
end

-- ---------- 1. the collector is settled at the write

gcSteps = 0
check("an autosave lands", save())
check("and settles the collector while it does", gcSteps == 1)
check("stopping the moment a step finishes the cycle", gcSteps == 1)

-- nothing new happened, so nothing is written -- and nothing is collected
gcSteps = 0
run(400)
check("a skipped save writes nothing", gcSteps == 0)

-- a collector that never reports a finished cycle is still bounded, and
-- bounded SMALL: a large heap on a phone must not turn one hitch into a
-- freeze, and asking for a heap's worth of credit is exactly that
gcFinishAfter = nil
gcSteps, gcCredit = 0, 0
check("a second autosave lands", save())
check("the catch-up is bounded when no cycle finishes", gcSteps <= 4)
check("and asks for a nudge rather than a whole cycle",
      gcCredit > 0 and gcCredit <= GC_BUDGET_KB)

-- a step that raises must not cost the save or crash the frame
gcBoom = true
check("a collector that errors does not take the save with it", save())
gcBoom = false
gcFinishAfter = 1

-- ---------- 1b. the frame after the hitch
--
-- A save is a hitch inside one logic step, and the engine pays an oversized
-- dt back as several logic steps before the next draw.  Over a warp's black
-- screen that is the fade being skipped -- the player pops into the new map.
-- FixedStep:discardCatchup is the engine's own remedy (crossConnection calls
-- it after a map seam); warps do not, so a hitch under one has nothing arming
-- the clamp, and this mod's write was that hitch.

catchupDiscards = 0
check("a third autosave lands", save())
check("and absorbs the frame it cost, so the fade is not skipped",
      catchupDiscards >= 1)

-- a write that FAILS cost a frame too; the clamp is not conditional on the
-- save having worked
catchupDiscards = 0
vetoed = true
run(25)
emit("map.entered")
run(2)
vetoed = false
check("a vetoed write still absorbs its frame", catchupDiscards >= 1)

-- and a frame with no write in it arms nothing
catchupDiscards = 0
run(120)
check("an ordinary frame arms nothing", catchupDiscards == 0)

-- ---------- 2. every autosave hands its upload straight to sync
--
-- A save is not finished when it reaches the disk, it is finished when it
-- reaches the account.  This used to pace uploads -- one autosave-woken upload
-- every five minutes, every other write's debounce disarmed, the file left for
-- the engine's own sweep -- which meant the newest save could sit on one
-- device for minutes while a second device was still being handed the old one.
--
-- Now the upload goes with the save, every time, and it goes NOW: the five
-- second debounce is there to coalesce a burst, and MIN_GAP already puts
-- twenty seconds between any two writes, so waiting it out only moves the
-- request from the black screen the save landed on to the middle of whatever
-- came next.

emit("save.loaded")
check("an autosave leaves its upload armed", save() and syncState.uploadAt ~= nil)
check("and armed for now, not five seconds out",
      syncState.uploadAt == syncState.clock)

-- ...which is the whole point: the debounce would have put it here instead
check("the debounce it replaced would have been later",
      syncState.clock + SYNC_UPLOAD_DEBOUNCE > syncState.clock)

-- the very next autosave does the same.  Under the old pacing this one was
-- written to disk and its upload thrown away.
syncState.uploadAt = nil
run(25)
check("a second autosave lands", save())
check("and wakes sync too, with no gap to wait out",
      syncState.uploadAt == syncState.clock)

-- sync off, unlinked, or nothing to send: writeSave arms nothing, and an
-- upload that does not exist is not this mod's to invent
syncState.uploadAt = nil
local realWrite = game.writeSave
game.writeSave = function()
  emit("save.writing")
  writes = writes + 1
  return true                        -- no uploadAt: sync has nothing to do
end
run(25)
check("an autosave with sync quiet still lands", save())
check("and no upload is conjured for it", syncState.uploadAt == nil)
game.writeSave = realWrite

-- ---------- 3. a manual save is none of this mod's business
--
-- It used to be: a manual save counted against the pacing gap, so the next
-- autosave's upload was thrown away.  With no gap there is nothing to count.

emit("save.loaded")
emit("save.writing")                 -- a manual save; its upload is on its way
syncState.uploadAt = nil
run(25)
check("an autosave after a manual save still lands", save())
check("and still wakes sync", syncState.uploadAt == syncState.clock)

-- ---------- 4. picking QUIT is exempt
--
-- Still well inside the gap opened by the manual save above.  There is no
-- five minute sweep coming for a game that is about to stop running, so this
-- write's upload goes now or never.

local function quitRow()
  local items = chains["ui.start_menu.items"](function(_, i) return i end, game,
    { { label = "QUIT", onSelect = function() return "quit" end } })
  for _, item in ipairs(items) do
    if item.label == "QUIT" then return item end
  end
end
local function lastBox() return boxes[#boxes] end

emit("world.stepped")                -- something worth saving on the way out
local beforeQuit = writes
quitRow().onSelect()
lastBox().opts.choice(true)
run(1 / 60)
check("YES puts a saving box up", lastBox().text == "Now saving...")
lastBox().opts.stay.onShown()
syncState.uploadAt = nil
run(1 / 60)
check("picking QUIT saves", writes == beforeQuit + 1)
check("and the quit save's upload is never paced away", syncState.uploadAt ~= nil)

syncState.uploadAt = nil             -- it went up; let the quit finish
run(1)
check("the quit then leaves", returned == 1)

-- ---------- 5. the garbage a sync cycle leaves behind
--
-- Planning decodes every slot into a full table again, a character at a time,
-- so a cycle throws away more than the write that caused it did.  Pay for it
-- in the frame it finished on -- for every cycle, not only the ones an
-- autosave woke: after pacing, most of them are the engine's own sweep.

emit("save.loaded")
gcSteps = 0
syncState.busy = true                -- checking, then uploading
run(3)
check("nothing is collected while a cycle is still running", gcSteps == 0)

syncState.busy = false               -- the cycle finished
run(1 / 60)
check("the cycle's garbage is settled the frame it lands", gcSteps == 1)
gcSteps = 0
run(5)
check("and settled once, not once a frame after", gcSteps == 0)

-- 5b. and not into a walk either
--
-- The plan is held out of the frames a dropped frame shows in, but the
-- transfer that follows it finishes on network time and answers to nothing.
-- Twelve collector steps landing in the middle of a stride is the same stutter
-- by another route, so the debt is remembered and paid on the first frame that
-- is not a moving screen.

held = true
gcSteps = 0
syncState.busy = true
run(1)
syncState.busy = false               -- the cycle finished, mid-walk
run(2)
check("a cycle finishing mid-walk collects nothing there", gcSteps == 0)
held = false
run(1)
check("and a one second pause is not a still frame", gcSteps == 0)
run(3)
check("and the debt is paid once the player really has stopped", gcSteps == 1)
gcSteps = 0
run(5)
check("once, and not again", gcSteps == 0)

-- a host with no sync engine at all is not a crash, and has no cycle to watch
noEngine = true
gcSteps = 0
check("no sync engine: the save still lands", save())
check("and only the write's own catch-up is asked for", gcSteps == 1)
gcSteps = 0
run(2)
check("with nothing collected for a cycle that cannot be seen", gcSteps == 0)
noEngine = false

-- ---------- 6. none of this happens with the mod switched off

opts.enabled = false
gcSteps = 0
syncState.uploadAt = 500
syncState.busy = true
local beforeOff = writes
emit("world.stepped")
run(60)
syncState.busy = false
run(1)
check("disabled writes nothing", writes == beforeOff)
check("disabled collects nothing", gcSteps == 0)
check("disabled leaves the upload alone", syncState.uploadAt == 500)

-- ---------- 7. QUIET SYNC: the stall lands where a dropped frame does not show
--
-- The expensive part of a cycle is the plan, and the plan runs on the frame
-- the SERVER'S REPLY lands (SyncEngine:update -> client:poll -> _planFrom).
-- Nothing the mod does can make that cheaper or predict when it arrives, so
-- what it does instead is keep it out of the frames a dropped frame shows in.
-- Mid-step is the only one of those: the walk cycle and the camera are both
-- part-way between tiles.
--
-- The engine ticks itself in the host, so the suite ticks it here -- through
-- the same instance the mod wrapped, which is what makes the hold visible.

opts.enabled = true
local ticked = 0
-- The mod wraps engine.update, and the stub's __newindex means that wrapper
-- REPLACES syncState.update -- so this is the inner function the wrapper
-- captures, and reassigning syncState.update later would throw the wrapper
-- away and test nothing.  `consumeReply` is how a later block makes the inner
-- update clear the pending reply, which is what a real plan does.
local consumeReply = false
syncState.update = function()
  ticked = ticked + 1
  if consumeReply then syncState.pending = nil end
end
syncState.pending = { handle = 1 }

player.moving = false
run(1 / 60)                          -- one frame to install the hold

local function tick(dt)
  local engine = game.syncEngine()
  engine.update(engine, dt or 1 / 60)
end

ticked = 0
tick()
check("a settled frame ticks the sync engine", ticked == 1)

player.moving = true
ticked = 0
for _ = 1, 10 do tick() end
check("a mid-step frame holds the cycle instead", ticked == 0)

player.moving = false
run(4)                               -- a real stop, not a gap between strides
tick()
check("and the player stopping releases it", ticked == 1)

-- The frame between two strides is not an opening.  `moving` is false on it,
-- which is what this test used to pass on, so the plan was released into the
-- exact frame the hold exists to protect -- several times a second, for as
-- long as the player kept walking.
player.moving = false
held = true
run(1)                               -- a held direction: the stop clock resets
ticked = 0
for _ = 1, 60 do tick() end
check("the gap between two strides does not release the plan", ticked == 0)

-- And there is no cap.  There was one -- three seconds -- which counted to
-- three without checking that the player had stopped and then ran the plan
-- wherever it landed.  Holding costs nothing but time: the reply is in hand,
-- the engine's clock stops with the hold, and letting go of the pad releases
-- it on the next frame.
player.moving = true
run(60)
ticked = 0
for _ = 1, 60 * 60 do tick() end
check("a minute of walking never forces the plan through", ticked == 0)

-- Letting go of the pad is not a stop.  run() rather than tick() from here,
-- because the stillness clock is kept by the mod's own update and a bare tick
-- of the sync engine does not advance it.
held = false
player.moving = false
ticked = 0
run(1)
tick()
check("a one second pause does not release it", ticked == 0)
run(3)
tick()
check("standing still for a few seconds does", ticked == 1)

-- Any menu, text box, battle or doorway releases it too: all of them take the
-- overworld off the top of the stack, and none of them is a frame a dropped
-- frame shows in.  This is the other half of what the save asked for: the
-- write goes down at the door, and the cycle it woke takes the NEXT window --
-- a conversation, a menu, the next battle -- rather than waiting on the same
-- one.
player.moving = true
held = true
screens[#screens + 1] = { menu = true }
run(1 / 30)
ticked = 0
tick()
check("a screen over the overworld releases it however the pad is held",
      ticked == 1)
table.remove(screens)

-- And a battle, which is a fine frame to spend even though it is not one to
-- write a save in.
screens[#screens + 1] = { battle = true }
emit("battle.started")
run(1 / 30)
ticked = 0
tick()
check("and so does a battle, which the write itself is barred from",
      ticked == 1)
emit("battle.ended")
table.remove(screens)
held = false
player.moving = false

-- A tick with nothing in flight is the cheap one that STARTS a cycle. Holding
-- that would stop the engine's clock for no reason at all.
syncState.pending = nil
player.moving = true
ticked = 0
tick()
check("a tick with no reply in flight is never held", ticked == 1)

-- The frame a reply lands on is the frame the plan runs on, and the plan is
-- the expensive half of a cycle -- so it is a hitch like a write is, and it
-- arms the engine's clamp for the same reason.  Without this the fade a
-- pulled-forward upload lands under gets skipped exactly as a write's did.
syncState.pending = { handle = 1 }
held = false
player.moving = false
run(4)                               -- a real stop: a quiet frame to run in
consumeReply = true
catchupDiscards = 0
ticked = 0
tick()
check("the plan runs on a quiet frame", ticked == 1)
check("and absorbs the frame it cost", catchupDiscards == 1)

-- a tick that consumes nothing arms nothing
consumeReply = false
syncState.pending = nil
catchupDiscards = 0
tick()
check("a tick with no reply to consume arms nothing", catchupDiscards == 0)

-- and the row turns it all the way off
syncState.pending = { handle = 1 }
opts.quiet_sync = false
player.moving = true
ticked = 0
tick()
check("QUIET SYNC off hands every frame straight through", ticked == 1)
opts.quiet_sync = true

-- as does switching the mod off, which must not leave sync held by a mod
-- that is no longer doing anything
opts.enabled = false
player.moving = true
ticked = 0
tick()
check("disabled holds nothing", ticked == 1)
opts.enabled = true
player.moving = false
