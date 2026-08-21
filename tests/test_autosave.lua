-- Minimal harness: fake mod host + fake game, drives core.update.
local writes = 0
local vetoed = false

local opts = { enabled = true, interval = 300, events = true, onquit = true, notify = "icon" }

local handlers, chains = {}, {}
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
  ui = nil,
}

local player = { moving = false }
local ow = { player = player, scriptMoves = {}, runner = nil }
local syncState = { busy = false, phase = "idle", uploadAt = nil }
local game = {
  overworld = ow,
  stack = { top = function() return ow end },
  writeSave = function() if vetoed then return false end writes = writes + 1 return true end,
  syncEngine = function()
    return { busy = function() return syncState.busy end, phase = syncState.phase,
             uploadAt = syncState.uploadAt }
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

-- 4. an event right after a write respects the 60s floor
emit("save.writing")
emit("world.stepped")
emit("pokemon.caught")
run(30)
check("event save waits out the floor", writes == 1)
run(35)
check("event save lands after the floor", writes == 2)

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
local warns = 0
mod.log.warn = function() warns = warns + 1 end
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

-- 7. a manual save resets the clock
emit("world.stepped")
run(100)
emit("save.writing")
run(250)
check("manual save restarts the interval", writes == 6)

-- 8. quit saves when dirty
emit("world.stepped")
local ok = chains["core.quit_to_launcher"](function() return "bye" end)
check("exit save writes", writes == 7)
check("quit chain returns vanilla result", ok == "bye")

-- 9. quit does not write when nothing changed
chains["core.quit_to_launcher"](function() return "bye" end)
check("exit save skipped when clean", writes == 7)

-- 9b. quitting is a process restart, so an unfinished engine is a reason to
-- skip the exit save entirely -- there is no "try again in two seconds" here,
-- and writing anyway is what turns a killed upload into a false conflict.
emit("world.stepped")
syncState.busy = true
local ok9b = chains["core.quit_to_launcher"](function() return "bye" end)
check("no exit save while a transfer is in flight", writes == 7)
check("quit chain still returns vanilla while busy", ok9b == "bye")
syncState.busy = false

emit("world.stepped")
syncState.uploadAt = 12.5
chains["core.quit_to_launcher"](function() return "bye" end)
check("no exit save with an upload still pending", writes == 7)
syncState.uploadAt = nil

emit("world.stepped")
syncState.phase = "conflict"
chains["core.quit_to_launcher"](function() return "bye" end)
check("no exit save while a conflict is unresolved", writes == 7)
syncState.phase = "idle"

-- and once the engine is settled the exit save happens as before
chains["core.quit_to_launcher"](function() return "bye" end)
check("exit save writes once sync is settled", writes == 8)

-- 10. a vetoed write does not spin
vetoed = true
emit("world.stepped")
run(400)
check("vetoed write is not retried in a loop", writes == 8)
vetoed = false

-- 11. disabled does nothing
opts.enabled = false
emit("world.stepped")
run(400)
check("disabled writes nothing", writes == 8)
