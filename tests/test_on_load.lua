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

-- The post-battle return, as much of it as this path reads.  BattleState:
-- finish pops the battle, emits battle.ended, and only THEN pushes this
-- (src/battle/BattleState.lua) -- so the event fires on a frame with nothing
-- covering anything, and the screen is not solid until this arrives.  It
-- opens with POST_BATTLE_RETURN frames at alpha 1 and then steps the fade
-- (Transition.BattleReturn), which is the window and the thing the window
-- exists to keep the write out of, in that order.
local RETURN_HOLD, RETURN_FADE = 10, 24
local function pushReturn()
  local t = { t = 0 }
  function t:alpha()
    if self.t < RETURN_HOLD then return 1 end
    return math.max(0, 1 - (self.t - RETURN_HOLD) / RETURN_FADE)
  end
  screens[#screens + 1] = t
  return t
end

-- What a battle actually looks like on the way out: the event, then the
-- return transition on the next frame, then the fade -- and then the
-- transition pops itself and hands the map back, which is what leaves the
-- stack as this found it.
local function endBattle()
  emit("battle.ended")
  pushReturn()
  run(1 / 60)
  table.remove(screens)
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
check("the event alone is not the window: nothing is covering yet", writes == before)
local ret = pushReturn()
run(1 / 60)
check("the return transition's hold is, and it writes there", writes == before + 1)
table.remove(screens)

-- and it goes in the HOLD, not once the fade has started stepping: the whole
-- point is that every frame of the fade plays after the hitch
run(25)
before = writes
emit("pokemon.evolved")
run(1)
emit("battle.ended")
ret = pushReturn()
ret.t = RETURN_HOLD + 4          -- the fade is already part-way down
run(1 / 60)
check("a fade already stepping is not the window", writes == before)
ret.t = 0                        -- a fresh hold, solid again
run(1 / 60)
check("the next solid frame takes it", writes == before + 1)
table.remove(screens)

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

-- ---------- 8. a menu is NOT a window
--
-- It used to be the widest one this had: anything over the overworld -- the
-- START menu, the bag, the party, a PC, a mart, a text box -- on the grounds
-- that the player COULD not move and the map behind is a still picture, so a
-- dropped frame there is a frame nobody sees.
--
-- Nobody sees it.  They feel it.  A menu is not a pause in the playing, it is
-- the part with the most presses per second in it, and a frame lost there is
-- an INPUT lost there.  A stutter mid-stride is ugly; a swallowed A press is
-- the game not listening.
--
-- So a screen over the overworld is a refusal, and the doors are the three
-- the README always named: a warp, the end of a battle, and stopping.

held = true                          -- walking the whole time, so the route
                                     -- path can never be what writes
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, a due save is still waiting", writes == before)

-- talking to somebody: the box is up AND the script is mid-run
scripting = true
screens[#screens + 1] = { textbox = true }
run(2)
check("mid-conversation is not a moment to write one down", writes == before)

-- the conversation ends: the script is finished, the box is gone, and the
-- player is standing exactly where it left them -- which IS a window, and the
-- one a menu hands back to.  Closing is the moment, not opening.
scripting = false
held = false
table.remove(screens)
run(1)
check("the moment it ends is", writes == before + 1)
held = true

-- a plain menu, with nothing half-done behind it, and the player standing
-- still under it.  This is the case that used to write on the frame the menu
-- opened, and it is the one being asked for back: they opened the bag to USE
-- something, and the press they are about to make must not be eaten.
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, still waiting", writes == before)
held = false                          -- standing still, so only the menu is
screens[#screens + 1] = { menu = true }
run(2)
check("the START menu is not a window, however long it is up", writes == before)

-- and it is the menu doing the refusing, not the stillness: three seconds of
-- standing there would otherwise have been a window twice over
run(4)
check("not even past the stop this would otherwise have been", writes == before)

-- close it, and the save goes on the route the player is standing on
table.remove(screens)
run(1)
check("closing it hands the save back", writes == before + 1)
held = true

-- and the start of a battle is NOT a window, however covered its intro is.
--
-- It used to be.  The wipe is as blacked-out a screen as the game has, so on
-- this path's own reasoning it qualified -- but it is the only covered screen
-- the player is watching for a cue rather than waiting out: it opens onto a
-- menu they are already reaching for, on the most frequent transition in the
-- game.  Reported as stuttering going into battles.  The end of the same
-- battle writes the same route with the outcome in it as well, seconds later,
-- behind a screen nobody is waiting on.
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, still waiting", writes == before)
emit("battle.started")
run(2)
check("a battle starting writes nothing", writes == before)
endBattle()
check("the end of that battle is what writes it", writes == before + 1)

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

-- not even behind the battle's own covered screens, which answer the same
-- "the screen is solid" question the return transition does.  An arm left
-- over from the battle before this one is the way that could have happened.
pushReturn()
run(30)
check("nor behind a veil inside one", writes == before)
table.remove(screens)

table.remove(screens)
endBattle()
check("the end of it writes", writes == before + 1)

-- ---------- 10. a route seam is not a door
--
-- The engine says which map changes had a screen: map.entered carries `via`.
-- A door, stairs, a cave and FLY all fade out and back.  Walking from Route 1
-- into Viridian does not -- routes are stitched together, the map scrolls on,
-- and the player is mid-stride the whole way across.  So a seam is neither a
-- window to write in nor a checkpoint worth writing for.

held = true                          -- running, the whole section
run(25)
before = writes
emit("pokemon.caught")               -- something real to save
run(2)
check("running, a due save is waiting", writes == before)

emit("map.entered", { via = "connection" })
check("crossing a route seam does not write it there", writes == before)
run(2)
check("and does not sneak it into the walk after", writes == before)

emit("map.entered", { via = "reload" })
check("nor does a mod rebuilding the map underfoot", writes == before)

emit("map.entered", { via = "boot" })
check("nor the game starting up", writes == before)

emit("map.entered", { via = "warp" })
check("a door does", writes == before + 1)

-- and a seam does not make a save due in the first place: nothing else here
-- is a checkpoint, so if the crossing were one this would write at the door
run(25)
before = writes
emit("world.stepped")                -- dirty, but not a checkpoint
emit("map.entered", { via = "connection" })
run(2)
check("a seam does not make a save due either", writes == before)
held = false
run(5)
check("...not even once the player stands still", writes == before)
held = true

-- FLY has a screen of its own
run(25)
before = writes
emit("pokemon.caught")
emit("map.entered", { via = "fly" })
check("FLY writes, it has an animation of its own", writes == before + 1)

-- an engine too old to say anything keeps the old answer, so a build that
-- predates `via` cannot silently stop saving at doors
run(25)
before = writes
emit("pokemon.caught")
emit("map.entered")
check("a map.entered with no via at all still writes", writes == before + 1)

-- ---------- 12. the write goes at the START of the fade, not the end
--
-- map.entered is the END of a warp's animation: the fade to black has already
-- played by the time it fires, and the fade back is zero steps long.  A write
-- there had nothing left in front of it to hide under, so what the player saw
-- was the door popping them through.  The first frames of the transition are
-- the other side of the same black screen, and thirty-two steps of fade come
-- after them.
--
-- The transition is a screen over the overworld, exactly as it is in the
-- engine, so this also covers the ordering in writeWindow: an ordinary due
-- save must not take the fade for a menu and write into the middle of it.

held = true
run(25)
before = writes
emit("pokemon.caught")
run(2)
check("walking, a due save is waiting", writes == before)

-- the door: the screen starts going black, and the transition goes on the
-- stack the way the engine puts it there
ow.transitioning = true
screens[#screens + 1] = { transition = true }
run(1 / 60)
check("the save goes on the first frame of the fade", writes == before + 1)

-- ...and map.entered, which is the far end of that same fade, must not write
-- a second time for one door
before = writes
run(0.4)                             -- the rest of a 32-step fade
ow.transitioning = false
table.remove(screens)
emit("map.entered")
check("the far end of the same fade does not write again", writes == before)

-- A fade the player is mid-stride through is not writable -- that guard is
-- the whole point of the path -- and then map.entered is the fallback that
-- catches the warp.
run(25)
before = writes
emit("pokemon.caught")
player.moving = true
ow.transitioning = true
screens[#screens + 1] = { transition = true }
run(0.4)
check("a fade the player is still mid-stride through writes nothing",
      writes == before)
player.moving = false
ow.transitioning = false
table.remove(screens)
emit("map.entered")
check("and map.entered catches that warp instead", writes == before + 1)

-- TELEPORT blacks out through teleportOut rather than transitioning, and it
-- is the same window.
run(25)
before = writes
emit("pokemon.caught")
run(2)
ow.teleportOut = true
screens[#screens + 1] = { transition = true }
run(1 / 60)
check("TELEPORT's own fade is a window too", writes == before + 1)
ow.teleportOut = false
table.remove(screens)

-- With SAVE ON LOADS off, the fade is not a window and the save waits for the
-- player to stop, the same as every other screen.
opts.on_load = false
run(25)
before = writes
emit("pokemon.caught")
ow.transitioning = true
screens[#screens + 1] = { transition = true }
run(0.4)
check("SAVE ON LOADS off does not write under the fade", writes == before)
ow.transitioning = false
table.remove(screens)
held = false
run(4)
check("and the save comes back to the route", writes == before + 1)
held = true
opts.on_load = true

print(string.format("\n%d/%d checks passed  (gen1autosave on-load)",
                    passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
