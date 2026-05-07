-- Headless Lazy.nvim update with a clean summary.
-- Run via: nvim --headless -c "luafile <this>" +qa
-- `show = false` hides the floating UI; the headless flags below silence
-- per-task progress notifications that Lazy still emits otherwise.
local cfg = require("lazy.core.config").options.headless
cfg.process = false
cfg.log = false
cfg.task = false
cfg.colors = false

require("lazy").update({ wait = true, show = false })

local updated = {}
for _, plugin in pairs(require("lazy").plugins()) do
  local u = plugin._.updated
  if u and u.from and u.to and u.from ~= u.to then
    table.insert(updated, string.format("  %s %s → %s", plugin.name, u.from:sub(1, 7), u.to:sub(1, 7)))
  end
end
table.sort(updated)

if #updated > 0 then
  io.write(string.format("Updated %d plugin(s):\n", #updated))
  for _, line in ipairs(updated) do
    io.write(line .. "\n")
  end
else
  io.write("No plugin changes.\n")
end

-- Lazy.update keeps task errors on the plugin object instead of throwing,
-- so we must surface them explicitly; otherwise `nvim` exits 0 and
-- daily-update.sh records the step as OK despite real failures.
local Plugin = require("lazy.core.plugin")
local errors = {}
for _, plugin in pairs(require("lazy").plugins()) do
  if Plugin.has_errors(plugin) then
    table.insert(errors, plugin.name)
  end
end
table.sort(errors)

if #errors > 0 then
  io.stderr:write(string.format("Errors in %d plugin(s):\n", #errors))
  for _, name in ipairs(errors) do
    io.stderr:write("  " .. name .. "\n")
  end
  vim.cmd("cquit 1")
end
