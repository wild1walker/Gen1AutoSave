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

local player = { moving = false }
local ow = { player = player, scriptMoves = {}, runner = nil }
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

-- ---------- 3. but waiting is not forever
--
-- A player who has not changed maps or fought anything in three quarters of a
-- minute is standing somewhere quiet.  A save on the route beats no save.

run(25)
before = writes
emit("pokemon.caught")
run(30)
check("still holding out for a screen at 30s", writes == before)
run(20)
check("past LOAD_WAIT it gives up and writes on the route", writes == before + 1)

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
check("and hands the save straight back to the route", writes == before + 1)
opts.on_load = true

print(string.format("\n%d/%d checks passed  (gen1autosave on-load)",
                    passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
