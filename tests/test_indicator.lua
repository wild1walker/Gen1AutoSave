-- Geometry-only check of the indicator panel: replays the same math the mod
-- uses against a real iPhone-shaped viewport (dpi 3) and a desktop one (dpi 1).
local BOX_W, ICON_W, ICON_H, ICON_MARGIN = 20, 7, 3, 2

-- The corner indicators hang off the region the game is given (margins and
-- all), not the 160x144 playfield inside it.  Same fallback order as the mod.
local function anchor(v)
  if (v.viewWidth or 0) > 0 and (v.viewHeight or 0) > 0 then
    return v.viewX or 0, v.viewY or 0, v.viewWidth, v.viewHeight
  end
  if (v.width or 0) > 0 and (v.height or 0) > 0 then
    return 0, 0, v.width, v.height
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
    x = ax + aw - math.floor((panelW + ICON_MARGIN) * sx)
    y = ay + math.floor(ICON_MARGIN * sy)
  end
  x = math.max(bx0, math.min(x, bx0 + bw0 - panelW * sx))
  y = math.max(by0, math.min(y, by0 + bh0 - panelH * sy))
  return x, y, panelW * sx, panelH * sy
end

local function check(label, cond) print((cond and "PASS  " or "FAIL  ") .. label) end

-- iPhone-ish: 393x852 units, dpi 3, GB pixel = 2.45 units (Sp = 7)
-- a self-consistent viewport: Sp=7 framebuffer px per GB px on a 3x screen
-- means the 160x144 playfield is 160*7/3 x 144*7/3 LOVE units
local phone = { gameX = 9.8, gameY = 300, gameWidth = 160 * 7 / 3,
                gameHeight = 144 * 7 / 3, scale = 7, dpiX = 3, dpiY = 3,
                width = 393, height = 852,
                viewX = 0, viewY = 0, viewWidth = 393, viewHeight = 852 }
local x, y, w, h = panel(phone, false)
check("phone: corner panel stays on screen",
  x >= 0 and x + w <= phone.viewWidth + 0.01)
check("phone: corner panel is a corner, not a banner",
  w / phone.gameWidth < 0.4)
check("phone: panel sits in the top right", y < phone.gameY + phone.gameHeight / 2)
print(string.format("       phone icon: x=%.1f y=%.1f w=%.1f h=%.1f (%.0f%% of width)",
  x, y, w, h, 100 * w / phone.gameWidth))

-- the old math, for the record
local bad = 7 * (ICON_W * 8 + 2)
check("phone: the un-divided scale really did overflow", bad > phone.gameWidth)
print(string.format("       old math wanted %.0f units of a %.0f unit screen",
  bad, phone.gameWidth))

-- desktop: dpi 1, integer scale 4
local desk = { gameX = 160, gameY = 0, gameWidth = 640, gameHeight = 576,
               scale = 4, dpiX = 1, dpiY = 1,
               width = 960, height = 576,
               viewX = 0, viewY = 0, viewWidth = 960, viewHeight = 576 }
x, y, w, h = panel(desk, false)
check("desktop: corner panel inside the screen", x >= 0 and x + w <= desk.viewWidth)
check("desktop: same proportion as the phone", math.abs(w / desk.gameWidth - 0.35) < 0.02)

-- classic text box, phone
x, y, w, h = panel(phone, true)
check("phone: text box spans the playfield width", math.abs(w - phone.gameWidth) < 1)
check("phone: text box sits on the bottom edge",
  math.abs((y + h) - (phone.gameY + phone.gameHeight)) < 1)

-- viewport missing scale/dpi entirely
local bare = { gameX = 0, gameY = 0, gameWidth = 320, gameHeight = 288 }
x, y, w, h = panel(bare, false)
check("bare viewport: falls back to playfield width", math.abs(w - 112) < 0.01)

-- ---- ball indicator ----------------------------------------------------
-- Same tilt/placement math as main.lua, checked as data rather than pixels.
local BALL_SIZE, BALL_MARGIN = 8, 4
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

local function ballRect(v)
  local sx = v.scale / (v.dpiX or 1)
  local sy = v.scale / (v.dpiY or 1)
  local ax, ay, aw, ah = anchor(v)
  local x = ax + aw - math.floor((BALL_SIZE + BALL_MARGIN) * sx)
  local y = ay + math.floor(BALL_MARGIN * sy)
  x = math.max(ax, math.min(x, ax + aw - BALL_SIZE * sx))
  y = math.max(ay, math.min(y, ay + ah - BALL_SIZE * sy))
  return x, y, BALL_SIZE * sx, BALL_SIZE * sy
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

local bx, by, bw, bh = ballRect(phone)
check("ball sits inside the screen",
  bx >= 0 and bx + bw <= phone.viewWidth + 0.01)
check("ball is small", bw / phone.gameWidth < 0.09)
check("ball is in the top right of the screen",
  bx > phone.viewWidth * 0.8 and by < phone.viewHeight * 0.2)
print(string.format("       phone ball: %.1f x %.1f units (%.0f%% of width)",
  bw, bh, 100 * bw / phone.gameWidth))

bx, by, bw, bh = ballRect(desk)
check("ball inside on desktop too",
  bx >= 0 and bx + bw <= desk.viewWidth)
check("fade only in the final quarter second",
  (NOTIFY_TIME - FADE_TIME) > SHAKE_START + SHAKE_PERIOD * SHAKE_COUNT)


-- ---- widescreen --------------------------------------------------------
-- 1920x1080.  The playfield is 10:9, so it is a 1200 wide box with 360 units
-- of margin either side; pinned to ITS corner the ball sat 360 units short of
-- the screen edge, which on a wide window reads as floating near the middle.
-- self-consistent: fitScale picks whole GB pixels, so 1080/144 rounds down to
-- 7 and the playfield is 1120x1008 centred in the window, not 1200 wide
local wide = { gameX = 400, gameY = 36, gameWidth = 1120, gameHeight = 1008,
               scale = 7, dpiX = 1, dpiY = 1,
               width = 1920, height = 1080,
               viewX = 0, viewY = 0, viewWidth = 1920, viewHeight = 1080 }
bx, by, bw, bh = ballRect(wide)
check("widescreen: ball is at the screen's right edge",
  bx + bw > wide.viewWidth - 40)
check("widescreen: ball is past the playfield, out over the margin",
  bx > wide.gameX + wide.gameWidth)
check("widescreen: ball is at the top", by < wide.viewHeight * 0.1)
print(string.format("       widescreen ball: x=%.0f of %.0f (playfield ends at %.0f)",
  bx, wide.viewWidth, wide.gameX + wide.gameWidth))

x, y, w, h = panel(wide, false)
check("widescreen: the SAVED panel goes to the same corner",
  x + w > wide.viewWidth - 40 and y < wide.viewHeight * 0.1)

-- the text box is the game's own furniture, so it stays on the playfield
x, y, w, h = panel(wide, true)
check("widescreen: the text box stays on the playfield",
  math.abs(w - wide.gameWidth) < 1 and math.abs(x - wide.gameX) < 1)
check("widescreen: text box still sits on the playfield's bottom edge",
  math.abs((y + h) - (wide.gameY + wide.gameHeight)) < 1)

-- a host that publishes neither view rect nor window falls back to playfield
local legacy = { gameX = 400, gameY = 36, gameWidth = 1120, gameHeight = 1008,
                 scale = 7, dpiX = 1, dpiY = 1 }
bx, by, bw, bh = ballRect(legacy)
check("no view rect: falls back to the playfield corner",
  bx + bw <= legacy.gameX + legacy.gameWidth + 0.01
    and bx > legacy.gameX + legacy.gameWidth * 0.8)
