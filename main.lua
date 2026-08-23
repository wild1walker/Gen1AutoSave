-- Gen1AutoSave
--
-- Saves on its own so manual saving becomes optional, and stays out of the
-- built-in save sync's way while doing it:
--
--   * the timer runs during battles and menus, not only while you stand still
--     on the map -- the write itself still waits for a settled overworld
--   * nothing happened since the last write => no write, so idling on the map
--     never bumps the save revision or wakes an upload
--   * never writes while sync is mid-transfer or holding an unresolved
--     conflict; the save is retried once sync settles
--   * a floor between writes so an event burst can't hammer the file
--   * writes on the way out to the launcher
--
-- Game:writeSave() already tells the sync engine it happened (5s upload
-- debounce), so no sync calls are needed here -- only restraint about when.

return function(mod)
  local MIN_GAP = 20        -- seconds between any two autosaves
  local EVENT_GAP = 60      -- and between two event-triggered ones
  local SYNC_RETRY = 2.0    -- re-check a busy sync this often
  local NOTIFY_TIME = 1.6

  local BOX_W, BOX_H = 20, 3
  local ICON_W, ICON_H = 7, 3
  -- One 8x8 tile in from the playfield's corner, the same inset the engine
  -- gives its own furniture.  Both indicators use it, so the ball and the
  -- SAVED panel land on the same spot.  At 2 and 4 GB pixels they sat all but
  -- touching the corner, which on a screen the picture fills is close enough
  -- to the edge to look like a mistake -- and on a phone close enough to go
  -- under a rounded corner.
  local HUD_MARGIN = 8
  local MESSAGE_TEXT = "Game saved."
  local ICON_TEXT = "SAVED"
  local HELD_MESSAGE = "Autosave paused."
  local HELD_ICON = "PAUSED"

  local state = {
    clock = 0,
    elapsed = 0,
    lastWriteAt = -math.huge,
    lastEventAt = -math.huge,
    dirty = false,
    due = false,
    reason = nil,
    inBattle = false,
    saving = false,
    syncWaitUntil = 0,
    notify = 0,
    heldTold = false,
    game = nil,
  }

  mod.options:define({
    {
      key = "enabled",
      type = "toggle",
      label = "AUTO SAVE",
      default = true,
      help = "Save progress automatically while you play.",
    },
    {
      key = "interval",
      type = "choice",
      label = "INTERVAL",
      default = 300,
      choices = {
        { "OFF", 0 },
        { "1 MIN", 60 },
        { "2 MIN", 120 },
        { "5 MIN", 300 },
        { "10 MIN", 600 },
        { "15 MIN", 900 },
      },
      help = "Time played between saves. Counts battles and menus too.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "events",
      type = "toggle",
      label = "AFTER EVENTS",
      default = true,
      help = "Also save after battles, catches, evolutions and new areas.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "onquit",
      type = "toggle",
      label = "ON QUIT",
      default = true,
      help = "Save when you pick QUIT, before leaving.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "notify",
      type = "choice",
      label = "INDICATOR",
      default = "ball",
      choices = {
        { "OFF", "off" },
        { "POKE BALL", "ball" },
        { "SAVED TEXT", "icon" },
        { "TEXT BOX", "box" },
      },
      help = "How an autosave announces itself.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "backups",
      type = "toggle",
      label = "SAVE BACKUPS",
      default = false,
      help = "Keep rollback copies of recent autosaves. START menu: BACKUPS.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "keep",
      type = "choice",
      label = "BACKUPS KEPT",
      default = 5,
      choices = {
        { "3", 3 },
        { "5", 5 },
        { "10", 10 },
        { "20", 20 },
      },
      help = "How many rollback copies to keep before the oldest is dropped.",
      visible_if = { key = "backups", equals = true },
    },
  })

  -- defined further down, next to the storage helpers it needs
  local captureBackup

  -- ---------- options

  local function on()
    return mod.options:get("enabled") == true
  end

  local function intervalSeconds()
    local value = mod.options:get("interval")
    if type(value) ~= "number" then return 0 end
    return value
  end

  -- ---------- when a write is allowed

  -- Same settled-overworld rule the engine uses for its own snapshots: no
  -- movement, no script, no transition, and the overworld actually on top.
  local function overworldIdle(game)
    local ow = game and game.overworld
    if not (ow and ow.player) then return false end
    if game.stack and game.stack:top() ~= ow then return false end
    if ow.player.moving then return false end
    if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
      return false
    end
    if #(ow.scriptMoves or {}) > 0 then return false end
    if ow.engaging or ow.emote or ow.teleportOut or ow.transitioning then
      return false
    end
    return true
  end

  -- A transfer in flight or a conflict waiting on the player are both reasons
  -- to hold the file still: writing now either races the upload or adds a
  -- third revision to a disagreement the player has not answered yet.
  local function syncSettled(game)
    if state.clock < state.syncWaitUntil then return false end
    local ok, engine = pcall(function() return game:syncEngine() end)
    if not ok or type(engine) ~= "table" then return true end
    local busy, conflict = false, false
    pcall(function()
      conflict = engine.phase == "conflict"
      busy = engine:busy() == true or conflict
    end)
    if busy then
      state.syncWaitUntil = state.clock + SYNC_RETRY
      return false, conflict and "conflict" or "transfer"
    end
    return true
  end

  -- Returning to the launcher is a process restart (HostShell.restart), so
  -- whatever the engine has not finished by the time the hook returns never
  -- finishes.  A PUT already in flight is the dangerous one: the server can
  -- apply it while the reply dies with the process, leaving this device a
  -- revision behind without knowing it -- and a local write on top of that is
  -- the second half of a conflict the player then has to answer, about a save
  -- only ever touched on one device.
  --
  -- uploadAt is the engine's own debounce field: set when a write is waiting
  -- to go up, cleared once it has.  It is read rather than called because
  -- there is no accessor for it, and a pending upload matters here for the
  -- same reason an in-flight one does -- the restart is going to eat it.
  local function syncIdleForExit(game)
    local ok, engine = pcall(function() return game:syncEngine() end)
    if not ok or type(engine) ~= "table" then return true end
    local idle = true
    pcall(function()
      idle = not (engine:busy() == true or engine.phase == "conflict"
        or engine.uploadAt ~= nil)
    end)
    return idle
  end

  -- ---------- the write

  local function announce(held)
    if mod.options:get("notify") ~= "off" then
      state.notify = NOTIFY_TIME
      state.held = held == true
    end
  end

  local function clearNotifyText()
    if state.notify <= 0 then
      state.notifyText = nil
      state.held = false
    end
  end

  -- An unresolved sync conflict holds every write, with no timeout and no way
  -- out but the player answering the launcher's prompt -- so staying quiet
  -- about it reads exactly like the mod having stopped working.  Said once
  -- per hold, not once per frame: it is a standing condition, not an event.
  local function tellHeld(why)
    if why ~= "conflict" or state.heldTold then return end
    state.heldTold = true
    announce(true)
    mod.log:warn("autosave held: save sync is waiting on a conflict answer")
  end

  local function write(game)
    if state.saving then return end
    -- snapshot first: a backup taken a frame before the write it accompanies
    -- is the same state, and a failed capture must not cost us the save
    captureBackup(game)
    state.saving = true
    local ok, result = pcall(game.writeSave, game)
    state.saving = false

    if ok and result ~= false then
      if state.reason == "event" then state.lastEventAt = state.clock end
      state.elapsed = 0
      state.dirty = false
      state.due = false
      state.reason = nil
      state.lastWriteAt = state.clock
      announce()
      mod.log:info("autosave written")
    elseif ok then
      -- another mod vetoed this write through save.write; stop asking
      state.due = false
      state.reason = nil
    else
      state.due = false
      state.reason = nil
      mod.log:warn("autosave failed: %s", tostring(result))
    end
  end

  local function request(reason)
    if not on() then return end
    state.due = true
    -- a timer request outranks an event one: it uses the shorter floor
    if reason ~= "event" or state.reason == nil then
      state.reason = reason
    end
  end

  -- ---------- what counts as progress
  --
  -- The digest problem in one line: playtime always moves, so comparing save
  -- bytes would call every idle minute a change.  Instead the events the
  -- engine already emits mark the save dirty, and a save with nothing dirty
  -- is skipped -- which is what keeps sync quiet while the game sits paused.

  local TOUCHED = {
    "world.stepped", "world.interacted", "world.object_toggled",
    "world.block_replaced", "world.boulder_moved", "flag.changed",
    "battle.started", "battle.ended", "pokemon.caught", "pokemon.received",
    "pokemon.evolved", "pokemon.level_up", "pokemon.move_learned",
    "egg.hatched", "trade.completed", "mail.written", "happiness.changed",
    "map.entered",
  }

  for _, name in ipairs(TOUCHED) do
    mod.events:on(name, function() state.dirty = true end)
  end

  local CHECKPOINTS = {
    "battle.ended", "map.entered", "pokemon.caught", "pokemon.evolved",
    "egg.hatched", "trade.completed", "world.blacked_out",
  }

  for _, name in ipairs(CHECKPOINTS) do
    mod.events:on(name, function()
      state.dirty = true
      if mod.options:get("events") then request("event") end
    end)
  end

  mod.events:on("battle.started", function() state.inBattle = true end)
  mod.events:on("battle.ended", function() state.inBattle = false end)

  -- A manual save resets everything: the player just did the thing.  It is
  -- otherwise none of this mod's business -- writeSave notifies the sync
  -- engine itself, whoever called it.
  mod.events:on("save.writing", function()
    state.elapsed = 0
    state.dirty = false
    state.due = false
    state.reason = nil
    state.lastWriteAt = state.clock
  end)

  local function reset()
    state.elapsed = 0
    state.dirty = false
    state.due = false
    state.reason = nil
    state.inBattle = false
    state.notify = 0
    state.heldTold = false
    state.held = false
    state.lastWriteAt = state.clock
  end

  mod.events:on("save.loaded", reset)
  mod.events:on("save.created", reset)

  mod.events:on("mod.options_changed", function(ev)
    if ev and ev.mod == mod and (ev.key == "enabled" or ev.key == "interval") then
      state.elapsed = 0
      state.due = false
    end
  end)

  -- ---------- backups
  --
  -- A backup is an engine checkpoint (the data-only progress snapshot plus the
  -- player's map/tile/facing and the RNG state) parked in mod storage, which is
  -- scoped per game version and per playthrough and written atomically.  It
  -- deliberately does NOT touch save.lua: the sync engine watches that file, so
  -- keeping history beside it costs no revisions and no uploads.
  --
  -- Only autosave moments get captured: Checkpoint.inspect refuses while a
  -- menu is on top, and a manual save happens from inside the START menu.  A
  -- manual save is untouched either way -- it writes and syncs exactly as it
  -- does without this mod, and just resets the timer here.

  local INDEX_KEY = "backups"

  local function slotKey(seq) return "backup/b" .. tostring(seq) end

  local function readIndex(game)
    local ok, data = pcall(function() return mod.storage:read(game, INDEX_KEY) end)
    if ok and type(data) == "table" and type(data.list) == "table" then
      data.seq = tonumber(data.seq) or 0
      return data
    end
    return { seq = 0, list = {} }
  end

  local function writeIndex(game, index)
    pcall(function() return mod.storage:write(game, INDEX_KEY, index) end)
  end

  local function keepCount()
    local value = mod.options:get("keep")
    if type(value) ~= "number" or value < 1 then return 5 end
    return value
  end

  -- Label the row with wall-clock time, which is the thing a player actually
  -- recognizes ("the one from before the gym").  Map ids are engine constants
  -- and would need sanitizing for the tile font, so they stay out of the list.
  local function stamp(game, at)
    local ok, text = pcall(function() return mod.datetime:time(game, at) end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return os.date("%H:%M", at)
  end

  function captureBackup(game)
    if not (mod.options:get("backups") and mod.checkpoints and mod.storage) then
      return
    end
    local ok, checkpoint = pcall(function()
      return mod.checkpoints:capture(game)
    end)
    if not ok or type(checkpoint) ~= "table" then return end

    local index = readIndex(game)
    index.seq = index.seq + 1
    local key = slotKey(index.seq)
    local stored = pcall(function()
      return mod.storage:write(game, key, checkpoint)
    end)
    if not stored then return end

    index.list[#index.list + 1] = { seq = index.seq, at = os.time() }
    local keep = keepCount()
    while #index.list > keep do
      local dropped = table.remove(index.list, 1)
      pcall(function() return mod.storage:delete(game, slotKey(dropped.seq)) end)
    end
    writeIndex(game, index)
  end

  local function say(game, text)
    local TextBox = mod.ui and mod.ui.TextBox
    if not (TextBox and game and game.stack) then return end
    pcall(function() game.stack:push(TextBox.new(game, text)) end)
  end

  local function confirmRestore(game, entry)
    local TextBox = mod.ui and mod.ui.TextBox
    if not TextBox then return end
    game.stack:push(TextBox.new(game,
      "Roll back to the\nsave from " .. stamp(game, entry.at) .. "?", nil, {
        defaultNo = true,
        choice = function(yes)
          if not yes then return end
          -- Don't touch the stack here: the text box is still tearing itself
          -- down.  Park the request and let the update pump unwind the menus.
          state.pendingRestore = entry.seq
        end,
      }))
  end

  local function openBackups(game)
    local ListMenu = mod.ui and mod.ui.ListMenu
    if not ListMenu then return end
    local index = readIndex(game)
    local items = {}
    -- newest first: the row a player wants is almost always the last one taken
    for i = #index.list, 1, -1 do
      local entry = index.list[i]
      items[#items + 1] = { label = stamp(game, entry.at), value = entry }
    end
    game.stack:push(ListMenu.new(game, "BACKUPS", items, {
      kind = "gen1autosave_backups",
      footer = #items == 0 and "No backups yet." or nil,
      onChoose = function(item)
        if item and item.value then confirmRestore(game, item.value) end
      end,
    }))
  end

  -- Decorate after next(), the documented convention for this hook.
  -- Picking QUIT is the last moment the game is still fully alive: the confirm
  -- box is still to come, the engine is still pumping, and an upload started
  -- here runs its course normally.  Writing at the other end -- inside the
  -- engine's quit hook, whichever exit it is -- is what kept manufacturing
  -- conflicts, because a write there can only ever be a revision nothing gets
  -- to finish sending.
  local function saveBeforeQuit(game)
    if not (game and game.writeSave) then return end
    if not (state.dirty and not state.inBattle) then return end
    if not syncIdleForExit(game) then return end
    local ow = game.overworld
    -- no overworldIdle here: the start menu is on top of it by definition.
    -- Mid-script and mid-step are still reasons to leave the file alone.
    if not ow then return end
    if (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
        or #(ow.scriptMoves or {}) > 0
        or ow.teleportOut or ow.transitioning then
      return
    end
    captureBackup(game)
    state.saving = true
    local ok, err = pcall(game.writeSave, game)
    state.saving = false
    if ok then
      state.dirty = false
      state.lastWriteAt = state.clock
      announce()
    else
      mod.log:warn("quit save failed: %s", tostring(err))
    end
  end

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" then return out end
    if on() and mod.options:get("onquit") then
      for _, item in ipairs(out) do
        local isQuit = item.id == "quit" or item.label == "QUIT"
        if isQuit and type(item.onSelect) == "function"
            and not item.gen1autosaveWrapped then
          local original = item.onSelect
          item.gen1autosaveWrapped = true
          item.onSelect = function(...)
            saveBeforeQuit(game)
            return original(...)
          end
        end
      end
    end
    if not (on() and mod.options:get("backups")) then return out end
    local row = {
      label = "BACKUPS",
      onSelect = function() openBackups(game) end,
    }
    if mod.ui and mod.ui.insertBefore then
      mod.ui.insertBefore(out, "QUIT", row)
    else
      out[#out + 1] = row
    end
    return out
  end)

  -- Restoring needs the same settled overworld a capture does, so it waits for
  -- the menus to come down instead of forcing them.
  local function stepRestore(game)
    local seq = state.pendingRestore
    if not seq then return end

    local top = game.stack and game.stack:top()
    if top ~= game.overworld then
      -- unwind the backups list / start menu, one screen per frame
      if game.stack and game.stack.pop then
        state.popped = (state.popped or 0) + 1
        if state.popped > 8 then
          state.pendingRestore, state.popped = nil, nil
          return
        end
        pcall(function() game.stack:pop() end)
      end
      return
    end
    state.popped = nil

    local ok, checkpoint = pcall(function()
      return mod.storage:read(game, slotKey(seq))
    end)
    if not ok or type(checkpoint) ~= "table" then
      state.pendingRestore = nil
      say(game, "That backup could\nnot be read.")
      return
    end

    local ok2, result, code, message = pcall(function()
      return mod.checkpoints:restore(game, checkpoint)
    end)
    if ok2 and result == true then
      state.pendingRestore, state.retries = nil, nil
      -- Persist immediately so the file (and the next sync upload) carries the
      -- rolled-back state rather than the newer one it replaced.
      state.dirty = true
      state.lastWriteAt = -math.huge
      state.notifyText = "LOADED"
      request("timer")
      return
    end
    -- These refusals mean "not this frame": a script, an animation or a step
    -- in flight.  Keep the request parked and try again.
    local TRANSIENT = {
      screen_busy = true, script_busy = true, animation_busy = true,
      movement_busy = true, transition_busy = true,
    }
    if ok2 and TRANSIENT[code] then
      state.retries = (state.retries or 0) + 1
      if state.retries < 600 then return end
    end
    state.pendingRestore, state.retries = nil, nil
    say(game, type(message) == "string" and message
      or "That backup could\nnot be restored.")
  end

  -- ---------- indicator

  -- An 8x8 ball, the size the games themselves use for a ball icon.  Drawn as
  -- plain rectangles rather than an image asset: there is no ball sprite a mod
  -- can reach (the battle ones live in the animation tilesets), and 64 filled
  -- pixels cost nothing next to loading a texture.
  --   1 outline  2 top shell  3 bottom shell  4 band  5 button
  local BALL = {
    { 0, 0, 1, 1, 1, 1, 0, 0 },
    { 0, 1, 2, 2, 2, 2, 1, 0 },
    { 1, 2, 2, 2, 2, 2, 2, 1 },
    { 1, 4, 4, 5, 5, 4, 4, 1 },
    { 1, 3, 3, 3, 3, 3, 3, 1 },
    { 1, 3, 3, 3, 3, 3, 3, 1 },
    { 0, 1, 3, 3, 3, 3, 1, 0 },
    { 0, 0, 1, 1, 1, 1, 0, 0 },
  }
  local BALL_COLORS = {
    { 0.09, 0.09, 0.09 },
    { 0.85, 0.25, 0.22 },
    { 0.97, 0.97, 0.97 },
    { 0.09, 0.09, 0.09 },
    { 0.97, 0.97, 0.97 },
  }
  local BALL_SIZE = 8
  local SHAKE_START, SHAKE_PERIOD, SHAKE_COUNT = 0.18, 0.34, 3
  local FADE_TIME = 0.25

  -- Which of the three shapes shows this frame.  The wobble is quantized to
  -- -1/0/+1 instead of a smooth angle because the original does the same: it
  -- swaps in pre-tilted tiles rather than rotating anything.
  local function tiltAt(elapsed)
    if elapsed < SHAKE_START then return 0 end
    local since = elapsed - SHAKE_START
    if since >= SHAKE_PERIOD * SHAKE_COUNT then return 0 end
    local phase = (since % SHAKE_PERIOD) / SHAKE_PERIOD
    local s = math.sin(phase * 2 * math.pi)
    if math.abs(s) < 0.45 then return 0 end
    return s > 0 and 1 or -1
  end

  -- Poor man's rotation, again the way the hardware does it: the top of the
  -- ball leans one way, the base the other, the band stays put.
  local function rowShift(tilt, row)
    if tilt == 0 then return 0 end
    if row <= 2 then return tilt end
    if row >= 7 then return -tilt end
    return 0
  end

  local function drawBall(g, elapsed, alpha)
    local tilt = tiltAt(elapsed)
    for row = 1, BALL_SIZE do
      local shift = rowShift(tilt, row)
      for col = 1, BALL_SIZE do
        local value = BALL[row][col]
        if value ~= 0 then
          local color = BALL_COLORS[value]
          g.setColor(color[1], color[2], color[3], alpha)
          g.rectangle("fill", col - 1 + shift, row - 1, 1, 1)
        end
      end
    end
  end

  local function drawNotify(viewport)
    if state.notify <= 0 then return end
    local mode = mod.options:get("notify")
    if mode == "off" then return end

    local g = love and love.graphics
    local Font = mod.ui and mod.ui.Font
    if not (g and viewport) then return end
    -- a held notice is text even in ball mode, so the font matters there too
    if not Font and (mode ~= "ball" or state.held) then return end

    local gx, gy = viewport.gameX or 0, viewport.gameY or 0
    local gw, gh = viewport.gameWidth or 0, viewport.gameHeight or 0
    if gw <= 0 or gh <= 0 then return end

    -- gameX/gameWidth are the PLAYFIELD: the 160x144 picture, letterboxed
    -- inside whatever window or screen the host gives it whenever that is not
    -- 10:9.  The corner indicators hang off THAT corner.  The window's corner
    -- is not the same place and is not what the player means by "top right":
    -- at a faithful aspect ratio on a phone the picture is a band across the
    -- middle with the touch controls under it and the status bar above, so a
    -- ball pinned to the window sat most of a screen clear of the game with
    -- nothing around it.  A badge belongs on the picture it is a badge for,
    -- widescreen desktop and faithful-ratio phone alike.

    local boxed = mode == "box"

    -- viewport.scale is Sp: FRAMEBUFFER pixels per GB pixel.  gameX/gameY/
    -- gameWidth/gameHeight are LOVE units -- Sp divided by the display's DPI
    -- scale.  Drawing at Sp inside a unit-space transform multiplies the panel
    -- by the DPI factor, which on a 3x phone screen is a box three times too
    -- wide that runs off the edge.  Sx/Sy (scale/dpi) is the unit scale, and
    -- the playfield width is the fallback when a field is missing.
    local sx = viewport.scale and viewport.scale / (viewport.dpiX or 1)
    local sy = viewport.scale and viewport.scale / (viewport.dpiY or 1)
    if not sx or sx <= 0 then sx = gw / (BOX_W * 8) end
    if not sy or sy <= 0 then sy = sx end

    -- The ball is its own little panel: sprite-sized, top right, and it fades
    -- on the way out instead of blinking off.
    if mode == "ball" and not state.held then
      local elapsed = NOTIFY_TIME - state.notify
      local alpha = 1
      if state.notify < FADE_TIME then alpha = state.notify / FADE_TIME end
      local bx = gx + gw - math.floor((BALL_SIZE + HUD_MARGIN) * sx)
      local by = gy + math.floor(HUD_MARGIN * sy)
      bx = math.max(gx, math.min(bx, gx + gw - BALL_SIZE * sx))
      by = math.max(gy, math.min(by, gy + gh - BALL_SIZE * sy))
      g.push("all")
      g.translate(bx, by)
      g.scale(sx, sy)
      drawBall(g, elapsed, alpha)
      g.pop()
      return
    end

    local tw = boxed and BOX_W or ICON_W
    local th = boxed and BOX_H or ICON_H
    local text
    if state.held then
      text = boxed and HELD_MESSAGE or HELD_ICON
    else
      text = boxed and MESSAGE_TEXT or (state.notifyText or ICON_TEXT)
    end
    local panelW, panelH = tw * 8, th * 8
    local textX = math.floor((panelW - #text * 8) / 2)

    -- The text box is the game's own furniture -- it stands in for the box the
    -- engine would have drawn -- so it sits where the engine's boxes sit:
    -- centred on the playfield's bottom edge.  The small corner panel is a HUD
    -- badge like the ball, so it takes the playfield's top right with it.
    local x, y
    if boxed then
      x = gx + math.floor((gw - panelW * sx) / 2)
      y = gy + gh - math.floor(panelH * sy)
    else
      x = gx + gw - math.floor((panelW + HUD_MARGIN) * sx)
      y = gy + math.floor(HUD_MARGIN * sy)
    end
    -- never let a rounding error or an odd viewport push it off the playfield
    x = math.max(gx, math.min(x, gx + gw - panelW * sx))
    y = math.max(gy, math.min(y, gy + gh - panelH * sy))

    g.push("all")
    g.translate(x, y)
    g.scale(sx, sy)
    Font.drawBox(0, 0, tw, th)
    g.setColor(0, 0, 0, 1)
    Font.draw(text, textX, 8)
    g.pop()
  end

  -- ---------- pumps

  mod.hooks:wrap("core.update", function(nextFn, game, dt)
    nextFn(game, dt)

    state.game = game
    state.clock = state.clock + dt
    if state.notify > 0 then state.notify = state.notify - dt end
    clearNotifyText()
    if not on() then return end

    -- A parked rollback outranks everything else this frame.
    if state.pendingRestore then
      stepRestore(game)
      return
    end

    -- Time accrues wherever the player is.  A long gym battle counts toward
    -- the interval, so "5 MIN" means five minutes of playing rather than five
    -- minutes of standing on a route doing nothing.
    local interval = intervalSeconds()
    if interval > 0 then
      state.elapsed = state.elapsed + dt
      if state.elapsed >= interval then request("timer") end
    end

    if not state.due then return end
    if not state.dirty then
      -- nothing happened; don't spend a revision on it
      state.due = false
      state.reason = nil
      state.elapsed = 0
      return
    end
    -- Two floors, because they answer different questions.  MIN_GAP is about
    -- the file: no two writes closer than this, whatever asked for them.
    -- EVENT_GAP is about bursts of events -- a row of door transitions -- and
    -- so it counts from the last event save, not from the last save of any
    -- kind.  Measuring it from the latter is what made a battle that ended
    -- just after a timer save produce nothing for a minute: the save was
    -- real, it simply landed later and somewhere else, which reads exactly
    -- like "it doesn't save after battles".
    if state.clock - state.lastWriteAt < MIN_GAP then return end
    if state.reason == "event"
        and state.clock - state.lastEventAt < EVENT_GAP then
      return
    end
    if not overworldIdle(game) then return end
    local settled, why = syncSettled(game)
    if not settled then
      tellHeld(why)
      return
    end
    state.heldTold = false

    write(game)
  end)

  mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
    nextFn(game, viewport)
    drawNotify(viewport)
  end)

  -- The engine's quit hook writes nothing at all now.  Both ways out of it
  -- have the same shape: a write here can only produce a revision that
  -- nothing survives to finish sending, and a PUT the server applies while
  -- its reply dies with the process is exactly half of a "played at the same
  -- time" conflict.  The save that used to live here happens when QUIT is
  -- picked instead, while there is still a game running to finish it.
  --
  -- What is left is the other half: disarm an upload that has been scheduled
  -- but not started, so the exit cannot cut one open. Nothing is lost by
  -- waiting -- the next launch sees an ordinary local change and uploads it.
  mod.hooks:wrap("core.quit_to_launcher", function(nextFn)
    local game = state.game
    if game then
      pcall(function()
        local engine = game:syncEngine()
        if type(engine) == "table" then engine.uploadAt = nil end
      end)
    end
    return nextFn()
  end)
end
