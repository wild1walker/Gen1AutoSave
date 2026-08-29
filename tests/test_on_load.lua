-- SAVE ON LOADS: a due save goes on a screen the game has already blacked out.
--
-- The write is not what is felt; where its frame lands is.  On the route that
-- frame is a stutter in the middle of walking.  A warp and the end of a battle
-- both cover the screen for their own reasons, and neither is a frame anyone
-- can see -- so a due save waits for one and goes there, and the loading
-- screen is a few frames longer instead.
--
-- Minimal harness: fake mod host + fake game, drives core.update.
local writes = 0
local emit                       -- forward: writeSave below emits through it

local opts = {
  enabled = true, interval = 0, events = true, onquit = true,
  notify = "icon", backups = false, on_load = true,
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

-- The player is WALKING for most of this suite, because that is the state the
-- whole path exists for.  `moving` is deliberately false alongside it: that is
-- the one frame between two strides, and it is where the hitch this mod was
-- reported for used to land.  A held direction is what tells the mod the next
-- stride starts on the next frame; the engine answers it with
-- OverworldState:dirHeld, and so does this.
local player = { moving = false }
local held = true
local scripting = false
local ow = { player = player, scriptMoves = {},
             runner = { isRunning = function() return scripting end },
             dirHeld = function() return held end }
local syncState = { busy = false, phase = "idle", uploadAt = nil }
local screens, returned = {}, 0
local noEngine = false
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
  -- sync engine, which arms the five second upload debounce.  A harness whose
  -- writeSave skips the event cannot see the mod counting its own write
  -- against the pacing gap, which is the one way this can go quietly wrong.
  writeSave = function()
    emit("save.writing")
    writes = writes + 1
    syncState.uploadAt = 5
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

local passed, failed = 0, 0
local function check(label, cond)
  if cond then passed = passed + 1 else failed = failed + 1 end
  print((cond and "PASS  " or "FAIL  ") .. label)
end

-- one frame, so the mod has a game handle before any event fires
run(1 / 60)

-- ---------- 1. a warp takes the save

local before = writes
emit("pokemon.caught")            -- dirty + due, and no black screen with it
run(5)
check("a due save does not go on the route straight away", writes == before)

emit("map.entered")               -- the warp's own screen, still covered
check("entering a map writes it there", writes == before + 1)

-- ---------- 2. and so does the end of a battle

run(25)                           -- clear MIN_GAP
before = writes
emit("pokemon.evolved")
run(5)
check("the next due save also waits", writes == before)
emit("battle.ended")
check("the end of a battle writes it", writes == before + 1)

-- ---------- 3. waiting is not on a clock
--
-- There was a 45-second cap here, on the reasoning that a player who had not
-- warped or fought in that long was standing somewhere quiet and a save on the
-- route beat no save.  It did not check that they had stopped, so what it
-- actually did was give up and write into a stride -- the one frame this path
-- exists to avoid, arriving reliably rather than by accident.
--
-- A due save now waits for as long as the walking lasts.  It leaves by one of
-- three doors and there is no fourth: a warp, the end of a battle, or the
-- player stopping.

run(25)
before = writes
emit("pokemon.caught")
run(60)
check("a minute of walking and it is still holding out", writes == before)
run(60)
check("two minutes, and still no frame spent on a moving screen",
      writes == before)

-- The third door: not a warp and not a battle, just standing still -- and it
-- has to be standing still, not the one-frame gap where a player lets go of
-- the pad to change direction.
held = false
run(1)
check("a second of not walking is not standing still", writes == before)
run(3)
check("a few seconds of it is, and it writes there", writes == before + 1)
held = true

-- And the frame between two strides is not standing still.  `moving` is false
-- on it -- which is what the old test was really passing on -- so this is the
-- assertion that fails if that check ever goes back to reading `moving` alone.
run(25)
before = writes
emit("pokemon.caught")
player.moving = false
run(5)
check("the gap between two strides is not an opening", writes == before)
held = false
run(4)
check("but a real stop is", writes == before + 1)
held = true

-- ---------- 4. the gates still apply on a loading screen

run(25)
before = writes
emit("pokemon.caught")
syncState.busy = true             -- a transfer in flight
emit("map.entered")
check("a warp does not write under a live sync transfer", writes == before)
syncState.busy = false
-- syncSettled arms a SYNC_RETRY re-check when it finds a transfer, so the
-- settle is not visible on the very next frame: it waits out the retry first
emit("map.entered")
check("nor on the frame the transfer clears", writes == before)
run(3)
emit("map.entered")
check("and writes on the next warp once the retry has passed",
      writes == before + 1)

run(25)
before = writes
emit("pokemon.caught")
player.moving = true
emit("map.entered")
check("nor while the player is still moving", writes == before)

-- and the moment it stops, the next warp takes it
player.moving = false
emit("map.entered")
check("the warp after that one does", writes == before + 1)

-- ---------- 5. MIN_GAP is not bypassed by a loading screen
--
-- No run() here on purpose: the write above landed on this same clock, so a
-- second warp arriving now is inside the floor and has to be refused like any
-- other write would be.

before = writes
emit("map.entered")
check("a warp cannot write inside MIN_GAP", writes == before)

-- ---------- 6. nothing due, nothing written

run(25)
before = writes
emit("map.entered")
run(1)
-- map.entered is itself a checkpoint, so it makes itself due; what must not
-- happen is a SECOND write from the same screen
check("one warp writes at most once", writes <= before + 1)

-- ---------- 7. the row turns it all the way off

opts.on_load = false
run(25)
before = writes
emit("pokemon.caught")
emit("map.entered")
check("SAVE ON LOADS off writes nothing on the screen", writes == before)
run(2)
check("and does not write into the walk either", writes == before)
held = false
run(4)
check("but hands the save back to the route once the player stops",
      writes == before + 1)
held = true
opts.on_load = true

-- ---------- 8. the windows that are not warps and not battles
--
-- A save has to go somewhere, and waiting for a door or a fight is waiting
-- longer than it has to.  Any moment the player COULD not move is a window:
-- a text box while an NPC is talking, the START menu, a mart, a PC, a Center's
-- heal.  The stack says so -- something over the overworld is something the
-- player is being held still by -- so none of them has to be named here.

held = true                          -- walking the whole time, so the route
                                     -- path can never be what writes
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, a due save is still waiting", writes == before)

-- talking to somebody: the box is up AND the script is mid-run, so the state
-- is half-written and this is not the moment
scripting = true
screens[#screens + 1] = { textbox = true }
run(2)
check("mid-conversation is not a moment to write one down", writes == before)

-- the conversation ends: the script is finished, the box is gone, and the
-- player is standing exactly where it left them -- which is a window in its
-- own right, without waiting out the three seconds a cold stop needs
scripting = false
held = false
table.remove(screens)
run(1)
check("the moment it ends is", writes == before + 1)
held = true

-- a plain menu is a window straight away: nothing is half-done behind it
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, still waiting", writes == before)
screens[#screens + 1] = { menu = true }
run(1 / 30)
check("the START menu is a window on the frame it opens", writes == before + 1)
table.remove(screens)

-- and the start of a battle, behind its own intro
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, still waiting", writes == before)
emit("battle.started")
check("a battle starting writes it behind the intro", writes == before + 1)
emit("battle.ended")

-- ---------- 9. and never inside the battle itself
--
-- Gen 1 has no save inside a battle and neither has this: the file would
-- record the overworld the fight started from while the player is somewhere
-- else entirely.  The END of it is a window and a better one.
--
-- No run() before this one on purpose: the battle above wrote on this same
-- clock, so MIN_GAP refuses the start of this one and the only thing left
-- that could write is the battle itself, which is the point.

before = writes
emit("battle.started")
emit("pokemon.caught")
screens[#screens + 1] = { battle = true }
run(30)
check("nothing is written inside a battle", writes == before)
table.remove(screens)
emit("battle.ended")
check("the end of it writes", writes == before + 1)

print(string.format("\n%d/%d checks passed  (gen1autosave on-load)",
                    passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
