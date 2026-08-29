-- Backup-ring and rollback harness: in-memory storage, a fake checkpoint
-- service and a fake screen stack.
local writes, captures = 0, 0
-- SAVE ON LOADS off: the ring is about what a write leaves behind, not about
-- which screen the write happened on, so this drives the route path directly.
local opts = { enabled = true, interval = 300, events = true, onquit = true,
               notify = "icon", backups = true, keep = 3, on_load = false }

local handlers, chains = {}, {}
local store = {}
local restoreResult = { true }
local said = {}

local mod = {
  options = { define = function(_, s) return s end, get = function(_, k) return opts[k] end },
  events = { on = function(_, n, fn) handlers[n] = handlers[n] or {}; table.insert(handlers[n], fn) end },
  hooks = { wrap = function(_, n, fn) chains[n] = fn end },
  log = { info = function() end, warn = function() end },
  datetime = { time = function(_, _, at) return os.date("!%H:%M", at) end },
  storage = {
    read = function(_, _, key) return store[key] end,
    write = function(_, _, key, value) store[key] = value return value end,
    delete = function(_, _, key) store[key] = nil return true end,
    list = function(_, _, prefix)
      local out = {}
      for k in pairs(store) do if k:sub(1, #prefix) == prefix then out[#out + 1] = k end end
      return out
    end,
  },
  checkpoints = {
    capture = function() captures = captures + 1 return { kind = "overworld", id = captures } end,
    restore = function() return table.unpack(restoreResult) end,
  },
  ui = {
    insertBefore = function(items, anchor, item)
      for i, it in ipairs(items) do
        if it.label == anchor then table.insert(items, i, item) return items end
      end
      items[#items + 1] = item
      return items
    end,
    ListMenu = { new = function(game, title, items, o)
      return { screen = "list", title = title, items = items, opts = o }
    end },
    TextBox = { new = function(game, text, onDone, o)
      said[#said + 1] = text
      return { screen = "textbox", text = text, opts = o }
    end },
    Font = nil,
  },
}

local ow = { player = { moving = false }, scriptMoves = {} }
local stack = { ow }
local game = {
  overworld = ow,
  stack = {
    top = function() return stack[#stack] end,
    push = function(_, s) stack[#stack + 1] = s end,
    pop = function() return table.remove(stack) end,
  },
  writeSave = function() writes = writes + 1 return true end,
  syncEngine = function() return nil end,
}

loadfile("../main.lua")()(mod)

local function emit(n, ev) for _, fn in ipairs(handlers[n] or {}) do fn(ev) end end
local function run(seconds, dt)
  dt = dt or 1 / 60
  local t = 0
  while t < seconds do chains["core.update"](function() end, game, dt) t = t + dt end
end
local function check(l, c) print((c and "PASS  " or "FAIL  ") .. l) end
local function countBackups()
  local n = 0
  for k in pairs(store) do if k:match("^backup/b%d+$") then n = n + 1 end end
  return n
end
local function clearScreens()
  while #stack > 1 do table.remove(stack) end
end
-- save.loaded resets the same counters without queueing a manual-save
-- snapshot, so it is the neutral baseline here
local function autosave()
  emit("save.loaded")
  emit("world.stepped")
  run(302)
end

-- 1. a backup lands with each autosave
autosave()
check("autosave wrote the save", writes == 1)
check("autosave stored one backup", countBackups() == 1)
check("index tracks the backup", store["backups"] and #store["backups"].list == 1)

-- 2. the ring prunes to KEEP
for _ = 1, 5 do autosave() end
check("six autosaves happened", writes == 6)
check("ring pruned to KEEP=3", countBackups() == 3)
check("index pruned to KEEP=3", #store["backups"].list == 3)
check("oldest snapshot key was deleted", store["backup/b1"] == nil)
check("newest snapshot key survives", store["backup/b6"] ~= nil)

-- 3. START menu row
local items = chains["ui.start_menu.items"](function(_, i) return i end, game,
  { { label = "SAVE" }, { label = "QUIT" } })
local labels = {}
for _, it in ipairs(items) do labels[#labels + 1] = it.label end
check("BACKUPS row inserted before QUIT",
  labels[1] == "SAVE" and labels[2] == "BACKUPS" and labels[3] == "QUIT")

-- 4. opening the list shows newest first
local row
for _, it in ipairs(items) do if it.label == "BACKUPS" then row = it end end
row.onSelect()
local list = stack[#stack]
check("list screen pushed", list.screen == "list" and list.title == "BACKUPS")
check("list holds the kept backups", #list.items == 3)
check("newest is first", list.items[1].value.seq == 6)

-- 5. choosing one asks for confirmation, and NO does nothing
list.opts.onChoose(list.items[1])
local box = stack[#stack]
check("confirm text box pushed", box.screen == "textbox")
box.opts.choice(false)
run(1)
check("declining leaves the stack alone", #stack == 3)

-- 6. YES unwinds the menus and restores, then persists the rollback
local before = writes
box.opts.choice(true)
run(2)
check("stack unwound back to the overworld", stack[#stack] == ow and #stack == 1)
check("rollback was written to the save file", writes > before)

-- 7. a transient refusal is retried rather than dropped
restoreResult = { false, "script_busy", "Wait for the script." }
row.onSelect()
list = stack[#stack]
list.opts.onChoose(list.items[1])
stack[#stack].opts.choice(true)
run(0.2)
check("transient refusal keeps trying", stack[#stack] == ow)
restoreResult = { true }
local pending = writes
run(0.5)
check("succeeds once the refusal clears", writes > pending)

-- 8. a hard failure reports instead of looping
restoreResult = { false, "checkpoint_mismatch", "Different playthrough." }
said = {}
row.onSelect()
list = stack[#stack]
list.opts.onChoose(list.items[1])
stack[#stack].opts.choice(true)
run(1)
check("hard failure surfaced a message", said[#said] == "Different playthrough.")

-- 9. backups off: no capture, no menu row
restoreResult = { true }
opts.backups = false
local capturesBefore = captures
autosave()
check("no capture while backups are off", captures == capturesBefore)
local plain = chains["ui.start_menu.items"](function(_, i) return i end, game,
  { { label = "SAVE" }, { label = "QUIT" } })
check("no BACKUPS row while off", #plain == 2)

-- 10. a manual save is left alone: no snapshot, and the timer just resets
opts.backups = true
clearScreens()
store, said = {}, {}
local menu = { screen = "start_menu" }
stack[#stack + 1] = menu                    -- player opened START
emit("save.writing")                        -- ... and chose SAVE
table.remove(stack)                         -- menu closes
run(2)
check("manual save takes no backup", countBackups() == 0)
check("manual save is not re-written by the mod", true)

-- 11. autosaves still back up normally afterwards
local n = countBackups()
autosave()
check("autosave adds exactly one backup", countBackups() == n + 1)
