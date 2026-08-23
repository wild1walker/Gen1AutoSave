-- Geometry-only check of the indicator placement: replays the same math the
-- mod uses against real viewports -- an iPhone-shaped one (dpi 3) and a
-- desktop one (dpi 1), with FAITHFUL RATIO both ways.
local BOX_W, ICON_W, ICON_H, HUD_MARGIN = 20, 7, 3, 8

-- The corner indicators hang off whatever the world pass covers, and which
-- rect that is depends on FAITHFUL RATIO rather than being fixed:
--
--   locked   the world pass is sized to the locked viewport and everything
--            outside it is dead display, so the PICTURE is the screen
--   unlocked the world pass expands to fill the whole display -- letterbox
--            voids become more map -- so the VIEW is the screen, and the
--            160x144 canvas is only where the engine's furniture goes
--
-- `faithful` on a viewport table below stands in for FaithfulRes.scaleCap(),
-- which is the mobile lock and nil everywhere else (a desktop lock sizes the
-- window to the picture instead, so there the two rects are already equal).
local function anchor(v)
  if not v.faithful and (v.viewWidth or 0) > 0 and (v.viewHeight or 0) > 0 then
    return v.viewX or 0, v.viewY or 0, v.viewWidth, v.viewHeight
  end
  return v.gameX, v.gameY, v.gameWidth, v.gameHeight
end

local function panel(viewport, boxed)
  local gx, gy = viewport.gameX, viewport.gameY
  local gw, gh = viewport.gameWidth, viewport.gameHeight
  local ax, ay, aw, ah = anchor(viewport)
  local tw = boxed and BOX_W or ICON_W
  local th = boxed and 3 or ICON_H
  local sx = viewport.scale and viewport.scale / (viewport.dpiX or 1)
  local sy = viewport.scale and viewport.scale / (viewport.dpiY or 1)
  if not sx or sx <= 0 then sx = gw / (BOX_W * 8) end
  if not sy or sy <= 0 then sy = sx end
  local panelW, panelH = tw * 8, th * 8
  local bx0, by0, bw0, bh0 = ax, ay, aw, ah
  if boxed then bx0, by0, bw0, bh0 = gx, gy, gw, gh end
  local x, y
  if boxed then
    x = gx + math.floor((gw - panelW * sx) / 2)
    y = gy + gh - math.floor(panelH * sy)
  else
    x = ax + aw - math.floor((panelW + HUD_MARGIN) * sx)
    y = ay + math.floor(HUD_MARGIN * sy)
  end
  x = math.max(bx0, math.min(x, bx0 + bw0 - panelW * sx))
  y = math.max(by0, math.min(y, by0 + bh0 - panelH * sy))
  return x, y, panelW * sx, panelH * sy
end

local BALL_SIZE = 8

local function ballRect(v)
  local sx = v.scale / (v.dpiX or 1)
  local sy = v.scale / (v.dpiY or 1)
  local ax, ay, aw, ah = anchor(v)
  local x = ax + aw - math.floor((BALL_SIZE + HUD_MARGIN) * sx)
  local y = ay + math.floor(HUD_MARGIN * sy)
  x = math.max(ax, math.min(x, ax + aw - BALL_SIZE * sx))
  y = math.max(ay, math.min(y, ay + ah - BALL_SIZE * sy))
  return x, y, BALL_SIZE * sx, BALL_SIZE * sy
end

local function check(label, cond) print((cond and "PASS  " or "FAIL  ") .. label) end

-- ---- the two phone modes, which is where this went wrong twice ----------
-- iPhone-ish: 393x852 units, dpi 3, GB pixel = 2.45 units (Sp = 7).
-- Self-consistent: Sp=7 framebuffer px per GB px on a 3x screen means the
-- 160x144 canvas is 160*7/3 x 144*7/3 LOVE units, a band across the middle of
-- a tall screen either way.  What differs is what surrounds that band: black
-- bars under the lock, more map without it.
local phoneLocked = { gameX = 9.8, gameY = 300, gameWidth = 160 * 7 / 3,
                      gameHeight = 144 * 7 / 3, scale = 7, dpiX = 3, dpiY = 3,
                      width = 393, height = 852, faithful = true,
                      viewX = 0, viewY = 0, viewWidth = 393, viewHeight = 852 }
local phoneOpen = { gameX = 9.8, gameY = 258, gameWidth = 160 * 7 / 3,
                    gameHeight = 144 * 7 / 3, scale = 7, dpiX = 3, dpiY = 3,
                    width = 393, height = 852,
                    viewX = 0, viewY = 0, viewWidth = 393, viewHeight = 852 }

local bx, by, bw, bh = ballRect(phoneLocked)
check("faithful phone: ball is on the picture",
  bx >= phoneLocked.gameX
    and bx + bw <= phoneLocked.gameX + phoneLocked.gameWidth + 0.01)
check("faithful phone: ball is in the picture's top right",
  bx > phoneLocked.gameX + phoneLocked.gameWidth * 0.8
    and by - phoneLocked.gameY < phoneLocked.gameHeight * 0.1)
-- the first regression: the picture is a band across the middle and the bars
-- around it are dead display, so the screen's own corner is 300 units of
-- black above the game
check("faithful phone: ball is not up in the screen's corner",
  by >= phoneLocked.gameY)
print(string.format("       faithful phone ball: y=%.0f, picture starts at %.0f",
  by, phoneLocked.gameY))

bx, by, bw, bh = ballRect(phoneOpen)
check("open phone: ball is at the screen's top right",
  bx + bw > phoneOpen.viewWidth - 40 and by < phoneOpen.viewHeight * 0.1)
-- the second regression: with the lock off the world fills the display, so
-- the 160x144 canvas is an invisible box and its top edge is 258 units down
-- the screen -- a badge on its corner hangs in the middle of the map.  In
-- portrait it is the VERTICAL gap that gives it away: the canvas is 373 units
-- of a 393 unit screen across, so the sides barely differ.
check("open phone: ball is not stranded on the canvas's corner",
  by + bh < phoneOpen.gameY)
print(string.format("       open phone ball: x=%.0f y=%.0f of %.0fx%.0f (canvas ends at %.0f)",
  bx, by, phoneOpen.viewWidth, phoneOpen.viewHeight,
  phoneOpen.gameX + phoneOpen.gameWidth))

-- ball size and panel proportion do not change with the mode
check("ball is small", bw / phoneOpen.gameWidth < 0.09)
local x, y, w, h = panel(phoneLocked, false)
check("faithful phone: corner panel is a corner, not a banner",
  w / phoneLocked.gameWidth < 0.4)
check("faithful phone: corner panel stays on the picture",
  x >= phoneLocked.gameX
    and x + w <= phoneLocked.gameX + phoneLocked.gameWidth + 0.01)
x, y, w, h = panel(phoneOpen, false)
check("open phone: corner panel follows the ball to the screen corner",
  x + w > phoneOpen.viewWidth - 40 and y < phoneOpen.viewHeight * 0.1)

-- the old math, for the record
local bad = 7 * (ICON_W * 8 + 2)
check("phone: the un-divided scale really did overflow",
  bad > phoneOpen.gameWidth)
print(string.format("       old math wanted %.0f units of a %.0f unit picture",
  bad, phoneOpen.gameWidth))

-- ---- desktop ------------------------------------------------------------
-- An ordinary 960x576 window, lock off: the map fills it, so the badge rides
-- the window's corner even though the 10:9 canvas is narrower.
local desk = { gameX = 160, gameY = 0, gameWidth = 640, gameHeight = 576,
               scale = 4, dpiX = 1, dpiY = 1,
               width = 960, height = 576,
               viewX = 0, viewY = 0, viewWidth = 960, viewHeight = 576 }
-- FAITHFUL RATIO on a desktop sizes the WINDOW to 160N x 144N instead of
-- capping the render scale, so scaleCap is nil there and the two rects are
-- the same rect.  Both readings have to agree.
local deskLocked = { gameX = 0, gameY = 0, gameWidth = 640, gameHeight = 576,
                     scale = 4, dpiX = 1, dpiY = 1,
                     width = 640, height = 576,
                     viewX = 0, viewY = 0, viewWidth = 640, viewHeight = 576 }

bx, by, bw, bh = ballRect(desk)
check("desktop: ball is at the window's top right",
  bx + bw > desk.viewWidth - 40 and by < desk.viewHeight * 0.1)
x, y, w, h = panel(desk, false)
check("desktop: corner panel goes to the same corner",
  x + w > desk.viewWidth - 40 and y < desk.viewHeight * 0.1)
check("desktop: same panel proportion as the phone",
  math.abs(w / desk.gameWidth - 0.35) < 0.02)

bx, by, bw, bh = ballRect(deskLocked)
check("desktop lock: window is the picture, so both readings agree",
  math.abs((bx + bw) - (deskLocked.gameX + deskLocked.gameWidth) + 8 * 4) < 1.01)

-- ---- clearance ----------------------------------------------------------
-- One tile in from the corner of whatever it is anchored to, in every mode:
-- jammed against the edge is what it looked like at 4 GB pixels on a screen
-- the picture fills.
local function clearance(v)
  local bx2, by2, bw2 = ballRect(v)
  local sx = v.scale / (v.dpiX or 1)
  local sy = v.scale / (v.dpiY or 1)
  local ax, ay, aw = anchor(v)
  return ((ax + aw) - (bx2 + bw2)) / sx, (by2 - ay) / sy
end
for _, case in ipairs({ { "faithful phone", phoneLocked }, { "open phone", phoneOpen },
                        { "desktop", desk } }) do
  local right, top = clearance(case[2])
  check(case[1] .. ": ball is a tile clear of both edges",
    math.abs(right - 8) < 1.01 and math.abs(top - 8) < 1.01)
  print(string.format("       %s clearance: %.1f right, %.1f top (GB pixels)",
    case[1], right, top))
end

-- ---- the classic text box ----------------------------------------------
-- The game's own furniture, so it goes where the engine's boxes go: centred
-- on the 160x144 canvas's bottom edge, in every mode.
for _, case in ipairs({ { "faithful phone", phoneLocked }, { "open phone", phoneOpen },
                        { "desktop", desk } }) do
  local v = case[2]
  x, y, w, h = panel(v, true)
  check(case[1] .. ": text box spans the canvas width",
    math.abs(w - v.gameWidth) < 1 and math.abs(x - v.gameX) < 1)
  check(case[1] .. ": text box sits on the canvas's bottom edge",
    math.abs((y + h) - (v.gameY + v.gameHeight)) < 1)
end

-- ---- the wobble ---------------------------------------------------------
-- Same tilt math as main.lua, checked as data rather than pixels.
local SHAKE_START, SHAKE_PERIOD, SHAKE_COUNT = 0.18, 0.34, 3
local NOTIFY_TIME, FADE_TIME = 1.6, 0.25

local function tiltAt(e)
  if e < SHAKE_START then return 0 end
  local since = e - SHAKE_START
  if since >= SHAKE_PERIOD * SHAKE_COUNT then return 0 end
  local s = math.sin(((since % SHAKE_PERIOD) / SHAKE_PERIOD) * 2 * math.pi)
  if math.abs(s) < 0.45 then return 0 end
  return s > 0 and 1 or -1
end

check("ball rests before the first shake", tiltAt(0) == 0 and tiltAt(0.17) == 0)
local swung = false
for i = 0, 100 do
  if tiltAt(SHAKE_START + i * SHAKE_PERIOD * SHAKE_COUNT / 100) ~= 0 then swung = true end
end
check("ball actually wobbles", swung)
check("ball is upright again when the shakes end",
  tiltAt(SHAKE_START + SHAKE_PERIOD * SHAKE_COUNT + 0.01) == 0)
check("ball is upright at the end of the notification", tiltAt(NOTIFY_TIME) == 0)

local seen = { [-1] = false, [0] = false, [1] = false }
for i = 0, 200 do seen[tiltAt(i * NOTIFY_TIME / 200)] = true end
check("all three tile shapes get used", seen[-1] and seen[0] and seen[1])
check("fade only in the final quarter second",
  (NOTIFY_TIME - FADE_TIME) > SHAKE_START + SHAKE_PERIOD * SHAKE_COUNT)

-- ---- widescreen ---------------------------------------------------------
-- 1920x1080 with the lock off.  The canvas is 10:9, so it is a 1120 wide box
-- with 400 units of margin either side -- and the map is drawn over that
-- margin too, so the badge belongs at the window's edge, not the canvas's.
-- self-consistent: fitScale picks whole GB pixels, so 1080/144 rounds down to
-- 7 and the canvas is 1120x1008 centred in the window.
local wide = { gameX = 400, gameY = 36, gameWidth = 1120, gameHeight = 1008,
               scale = 7, dpiX = 1, dpiY = 1,
               width = 1920, height = 1080,
               viewX = 0, viewY = 0, viewWidth = 1920, viewHeight = 1080 }
bx, by, bw, bh = ballRect(wide)
check("widescreen: ball is at the window's right edge",
  bx + bw > wide.viewWidth - 60)
check("widescreen: ball is out past the canvas, over the map",
  bx > wide.gameX + wide.gameWidth)
check("widescreen: ball is at the top", by < wide.viewHeight * 0.1)
print(string.format("       widescreen ball: x=%.0f of %.0f (canvas ends at %.0f)",
  bx, wide.viewWidth, wide.gameX + wide.gameWidth))

x, y, w, h = panel(wide, false)
check("widescreen: the SAVED panel goes to the same corner",
  x + w > wide.viewWidth - 60 and y < wide.viewHeight * 0.1)
x, y, w, h = panel(wide, true)
check("widescreen: the text box stays on the canvas",
  math.abs(w - wide.gameWidth) < 1 and math.abs(x - wide.gameX) < 1)

-- ---- hosts that publish less -------------------------------------------
-- No view rect at all (the Gen 2 viewport): the canvas is the only rect
-- there is, so everything hangs off it and nothing guesses at a window.
local legacy = { gameX = 400, gameY = 36, gameWidth = 1120, gameHeight = 1008,
                 scale = 7, dpiX = 1, dpiY = 1 }
bx, by, bw, bh = ballRect(legacy)
check("no view rect: falls back to the canvas corner",
  bx + bw <= legacy.gameX + legacy.gameWidth + 0.01
    and bx > legacy.gameX + legacy.gameWidth * 0.8)

-- no scale/dpi either
local bare = { gameX = 0, gameY = 0, gameWidth = 320, gameHeight = 288 }
x, y, w, h = panel(bare, false)
check("bare viewport: falls back to canvas width", math.abs(w - 112) < 0.01)
