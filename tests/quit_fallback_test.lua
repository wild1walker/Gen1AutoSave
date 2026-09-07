-- The vanilla QUIT fallback, run under BOTH Lua arrangements this mod ships
-- into.
--
-- Picking QUIT with nothing to save is the fallback path: the offer is
-- declined before it is made (quitSaveOffered is false on a clean save) and
-- the row's original handler is called instead, untouched.  That path was
-- broken in the game and green on the bench for the same reason -- the bench
-- runs Lua 5.4, where `table.unpack` exists, and LOVE runs LuaJIT, where it
-- does not:
--
--   mods/gen1autosave/main.lua:1970: attempt to call field 'unpack'
--   (a nil value)
--
-- reported as "load a save, pick QUIT straight away, and it crashes instead
-- of showing the prompt".  Straight away is the whole trigger: nothing has
-- happened yet, so the save is clean, so the fallback runs.
--
-- So this suite installs the mod TWICE, once with each arrangement of the
-- two names, and drives the row the way the engine drives it --
-- `item.onSelect()`, no arguments (src/ui/Menu.lua:101).

local passed, failed = 0, 0
local function ok(cond, description)
  if cond then
    passed = passed + 1
    io.write("  ok    ", description, "\n")
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end

local function source(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local text = handle:read("*a")
  handle:close()
  return text
end

local MAIN = source("main.lua")

-- Enough of the host for the entry chunk to install and hand back its
-- ui.start_menu.items chain.  `onquit` is on and the save is clean, which is
-- the state a just-loaded game is in.
local function fakeMod()
  local self = { id = "gen1autosave", path = ".", exports = {}, hooked = {} }
  local opts = { enabled = true, onquit = true, backups = false,
                 interval = 300, notify = "icon" }
  self.options = { define = function() end,
                   get = function(_, key) return opts[key] end }
  self.save = { get = function(_, _, fallback) return fallback end,
                set = function() end }
  self.cache = { read = function() end, write = function() end }
  self.storage = { read = function() end, write = function() end,
                   delete = function() end }
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function() end
  end
  self.hooks = { wrap = function(_, name, fn) self.hooked[name] = fn end }
  self.events = { on = function() end, once = function() end }
  self.ui = { push = function() end }
  self.content, self.world = {}, {}
  self.find = function() return nil end
  function self:read() return nil end
  return self
end

-- A game the offer cannot be made on: writeSave and returnToTitle are both
-- there, so the only thing standing the offer down is the clean save -- which
-- is exactly the reported repro rather than a rigged one.
local function fakeGame()
  return { writeSave = function() return true end,
           returnToTitle = function() return true end,
           stack = { push = function() end, top = function() return nil end } }
end

-- Install under one arrangement of (unpack, table.unpack), hand the wrapped
-- QUIT row to `body`, and put the globals back.
--
-- `body` runs INSIDE the swapped world, and that is not a detail: the chunk
-- resolves the name once at load, but the line this suite exists for looked
-- it up again on every call.  Restoring the globals before pressing the row
-- would let 5.4's `table.unpack` answer a call that LuaJIT could not, which
-- is the same blind spot in a smaller room.
local function underLua(globalUnpack, tableUnpack, row, body)
  local savedGlobal, savedTable = _G.unpack, table.unpack
  _G.unpack, table.unpack = globalUnpack, tableUnpack

  local ran, err = pcall(function()
    local mod = fakeMod()
    assert(load(MAIN, "@main.lua"))()(mod)
    local chain = mod.hooked["ui.start_menu.items"]
    assert(type(chain) == "function",
      "the mod did not wrap ui.start_menu.items")
    local items = chain(function(_, i) return i end, fakeGame(), { row })
    for _, item in ipairs(items) do
      if item.label == "QUIT" then return body(item) end
    end
    return body(nil)
  end)

  _G.unpack, table.unpack = savedGlobal, savedTable
  if not ran then error(err, 0) end
end

local REAL_UNPACK = table.unpack

-- LOVE: LuaJIT is 5.1, so the global `unpack` is the one that exists and
-- table.unpack is nil.  The sandbox copies the host's `table` faithfully
-- (src/mods/Sandbox.lua:154), so nothing fills the gap in.
local LUAJIT = { global = REAL_UNPACK, field = nil }
-- The bench: Lua 5.4 dropped the global and kept the field.
local LUA54 = { global = nil, field = REAL_UNPACK }

for _, world in ipairs({ { name = "LuaJIT (the game)", env = LUAJIT },
                         { name = "Lua 5.4 (the bench)", env = LUA54 } }) do
  io.write(world.name, "\n")

  -- 1. no arguments at all, which is how the Gen 1 start menu calls a row
  -- (src/ui/Menu.lua:101) and is the reported crash exactly.
  local called = 0
  underLua(world.env.global, world.env.field,
    { label = "QUIT", onSelect = function()
        called = called + 1
        return "vanilla quit"
      end },
    function(row)
      ok(row ~= nil, "the QUIT row survives the wrap")
      local okCall, result = pcall(row.onSelect)
      ok(okCall, "a clean save falls through without raising"
        .. (okCall and "" or ": " .. tostring(result)))
      ok(called == 1, "the engine's own QUIT handler ran exactly once")
      ok(result == "vanilla quit", "and its return value is passed back")
    end)

  -- 2. every argument arrives, not just the first.  `a and b or c` truncates
  -- b to ONE value, so the old line dropped the rest on the floor even where
  -- it did not crash -- and a nil first argument sent it down the `or` too.
  local seen
  underLua(world.env.global, world.env.field,
    { label = "QUIT", onSelect = function(...)
        seen = { n = select("#", ...), ... }
        return true
      end },
    function(row)
      ok(pcall(row.onSelect, "game", "menu", 3), "three arguments do not raise")
      ok(seen and seen.n == 3, "all three arrive (got "
        .. tostring(seen and seen.n) .. ")")
      ok(seen and seen[2] == "menu" and seen[3] == 3,
        "and they arrive in order")

      ok(pcall(row.onSelect, nil, "second"),
        "a nil first argument does not raise")
      ok(seen and seen.n == 2 and seen[1] == nil and seen[2] == "second",
        "a nil is forwarded as a nil rather than ending the list")
    end)
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
