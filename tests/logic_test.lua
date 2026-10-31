-- Loads the loot rules without the WoW client.
-- From the repo root: lua tests/logic_test.lua

local function script_dir()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  if source:sub(1, 1) == "@" then source = source:sub(2) end
  return (source:match("^(.*)[/\\]") or ".")
end

local root = script_dir():gsub("[/\\]tests$", "")
if root == script_dir() then root = script_dir() .. "/.." end

local function loadmod(path, namespace)
  local fh, openErr = io.open(path, "rb")
  if not fh then error("cannot open " .. path .. ": " .. tostring(openErr)) end
  local src = fh:read("*a")
  fh:close()
  if src:sub(1, 3) == string.char(239, 187, 191) then src = src:sub(4) end
  local loader = loadstring or load
  local chunk, err = loader(src, "@" .. path)
  if not chunk then error(err) end
  chunk("TGCLoot", namespace)
end

local ns = {}
local files = {
  "Core.lua",
  "Codec.lua",
  "Score.lua",
  "Comm.lua",
  "Loot.lua",
  "Roll.lua",
  "UI.lua",
  "Main.lua",
}
for _, name in ipairs(files) do
  loadmod(root .. "/TGCLoot/" .. name, ns)
end

local fine, passed, err = pcall(ns.SelfTest)
if not fine then
  io.write("error: " .. tostring(passed) .. "\n")
  os.exit(1)
end
if passed then
  io.write("ok\n")
  os.exit(0)
end
io.write(tostring(err) .. "\n")
os.exit(1)
