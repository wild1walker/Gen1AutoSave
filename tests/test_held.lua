-- What a HELD save looks like, and what it takes to get one.
--
-- The other harnesses check when the mod writes; this one checks the badge it
-- puts up when it deliberately does not.  In POKE BALL mode that badge used to
-- be the word PAUSED -- a font panel in a slot that is otherwise a picture --
-- and it is now a cross that blinks in exactly the ball's 8x8 corner.
--
-- So this loads main.lua for real against a recording love.graphics and reads
-- back what got drawn, rather than mirroring the drawing code and checking the
-- mirror.

-- SAVE ON LOADS off: the hold badge is about the route path's refusal to write
-- under an unresolved conflict, which is what this drives.
local opts = {
  enabled = true, interval = 0, events = true, onquit = true,
  notify = "ball", backups = false, on_load = false,
}

-- ---- a love.graphics that writes down what it was asked to draw ----------
-- push/pop/translate/scale are recorded too: the sprites draw in their own
-- 0..8 space, so where the badge actually lands is the transform, not the
-- rectangles.
local drawn, xform = {}, { x = 0, y = 0, sx = 1, sy = 1 }
local colour = { 1, 1, 1, 1 }
love = {
  graphics = {
    push = function() end,
    pop = function() end,
    translate = function(x, y) xform.x, xform.y = x, y end,
    scale = function(sx, sy) xform.sx, xform.sy = sx, sy end,
    setColor = function(r, g, b, a) colour = { r, g, b, a or 1 } end,
    rectangle = function(_, x, y, w, h)
      drawn[#drawn + 1] = {
        r = colour[1], g = colour[2], b = colour[3], a = colour[4],
        x = xform.x + x * xform.sx, y = xform.y + y * xform.sy,
        w = w * xform.sx, h = h * xform.sy,
      }
    end,
    setFont = function() end,
    print = function() end,
  },
}

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
  log = { info = function() end, warn = function() end },
  -- No Font on purpose: ball mode draws both of its states itself, so neither
  -- the ball nor the cross may depend on one being there.
  ui = { TextBox = { new = function() return {} end } },
}

local player = { moving = false }
local ow = { player = player, scriptMoves = {}, runner = nil }
local syncState = { busy = false, phase = "idle", uploadAt = nil,
                    protectedKey = nil, conflicts = nil }
local writes = 0
local game = {
  overworld = ow,
  stack = { top = function() return ow end, push = function() end,
            pop = function() end },
  returnToTitle = function() end,
  writeSave = function()
    writes = writes + 1
    syncState.uploadAt = 5
    return true
  end,
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

-- A desktop viewport: scale 4, dpi 1, no FAITHFUL lock, so the picture and the
-- view are the same rect and the corner arithmetic is the plain case.
local viewport = {
  gameX = 0, gameY = 0, gameWidth = 160 * 4, gameHeight = 144 * 4,
  viewX = 0, viewY = 0, viewWidth = 160 * 4, viewHeight = 144 * 4,
  scale = 4, dpiX = 1, dpiY = 1,
}

local function emit(name) for _, fn in ipairs(handlers[name] or {}) do fn() end end
local function frame(dt)
  chains["core.update"](function() end, game, dt or 1 / 60)
  drawn = {}
  chains["render.hud"](function() end, game, viewport)
  return drawn
end

-- Step until the badge appears, and hand back the frame it appeared in.
local function untilDrawn(limit)
  local t = 0
  while t < limit do
    local f = frame()
    t = t + 1 / 60
    if #f > 0 then return f end
  end
  return {}
end

local function check(label, cond) print((cond and "PASS  " or "FAIL  ") .. label) end

local function near(a, b) return math.abs(a - b) < 0.02 end
local function has(f, r, g, b)
  for _, px in ipairs(f) do
    if near(px.r, r) and near(px.g, g) and near(px.b, b) then return true end
  end
  return false
end
local function bounds(f)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, px in ipairs(f) do
    x0, y0 = math.min(x0, px.x), math.min(y0, px.y)
    x1, y1 = math.max(x1, px.x + px.w), math.max(y1, px.y + px.h)
  end
  return x0, y0, x1, y1
end
local function maxAlpha(f)
  local a = 0
  for _, px in ipairs(f) do a = math.max(a, px.a) end
  return a
end

-- ---- 1. an ordinary save draws the ball ---------------------------------
emit("battle.ended")
local ball = untilDrawn(5)
check("a save that lands draws something", #ball > 0)
check("and it is the ball: it has the white lower shell",
  has(ball, 0.97, 0.97, 0.97))
check("with the shell red above it", has(ball, 0.85, 0.25, 0.22))
local bx0, by0, bx1, by1 = bounds(ball)
check("in an 8x8 sprite slot", near(bx1 - bx0, 8 * 4) and near(by1 - by0, 8 * 4))
check("in the top right corner",
  near(bx1, 160 * 4 - 8 * 4) and near(by0, 8 * 4))

-- ---- 2. a held save draws the cross instead ------------------------------
-- Held means a conflict over the save being played, standing longer than the
-- grace -- the only thing that puts this badge up at all.
local HOLD_GRACE = 15
while true do local f = frame() if #f == 0 then break end end   -- let the ball fade
syncState.protectedKey = "red/now-playing"
syncState.conflicts = { { key = "red/now-playing" } }
syncState.phase = "conflict"
frame(30)                     -- clear MIN_GAP in one go
emit("battle.ended")
local cross = untilDrawn(HOLD_GRACE + 10)
check("a held save draws something too", #cross > 0)
check("and it is not a ball: no white shell", not has(cross, 0.97, 0.97, 0.97))
check("it is the cross, in its own red", has(cross, 0.90, 0.22, 0.20))
check("outlined in the ball's own outline colour", has(cross, 0.09, 0.09, 0.09))
check("and no write went out under it", writes == 1)

local cx0, cy0, cx1, cy1 = bounds(cross)
check("the cross fills the ball's slot exactly",
  near(cx0, bx0) and near(cy0, by0) and near(cx1, bx1) and near(cy1, by1))

-- ---- 3. and it blinks ----------------------------------------------------
-- Hard on/off on a 0.4s period: sampling a quarter of a second in lands in the
-- off half, which dims rather than disappears.
local lit = maxAlpha(cross)
local dim
local t = 0
while t < 0.25 do dim = frame() t = t + 1 / 60 end
check("the off half is dimmer", maxAlpha(dim) < lit)
check("but still on screen", #dim > 0 and maxAlpha(dim) > 0)
local t2 = 0
while t2 < 0.2 do lit = maxAlpha(frame()) t2 = t2 + 1 / 60 end
check("and it comes back up again", lit > maxAlpha(dim))

-- ---- 4. OFF still draws nothing, held or not ----------------------------
opts.notify = "off"
syncState.phase = "idle"
syncState.conflicts = nil
frame(30)
emit("battle.ended")
check("INDICATOR OFF draws nothing", #untilDrawn(5) == 0)
