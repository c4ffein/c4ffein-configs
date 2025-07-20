local M = {}

local scoring = require("file-finder.scoring")

M.HOME = vim.env.HOME or vim.env.USERPROFILE -- USERPROFILE for Windows
if M.HOME:sub(-1) ~= "/" then M.HOME = M.HOME .. "/" end

local function is_ignored_dir(dirname, ignored_dirs)
  for _, ignored in ipairs(ignored_dirs) do if dirname == ignored then return true end end
  return false
end

local function is_symlink(path) local stat = vim.loop.fs_lstat(path); return stat and stat.type == 'link' end

-- TODO + and - to get more and less lines per file
-- TODO adapt
-- local function ensure_dir(path)
--     local ok, err = vim.loop.fs_stat(path)
--     if not ok then vim.fn.mkdir(path, "p") end
-- end
-- 
-- local function ensure_file(path)
--     local file = io.open(path, 'a')
--     if file then file:close() end
-- end

function M.open_file(file_path, line_number)
  -- line number is optional
  if not line_number then vim.cmd("edit ".. vim.fn.fnameescape(file_path))
  else vim.cmd("edit +" .. line_number .. " " .. vim.fn.fnameescape(file_path)) end
end

function M.get_files()
  -- doesn't follow symlinks - could add all targets to (links to check / results) if they don't exist, keeping naive rn
  local files = {}
  local ignored_dirs = { ".git", "node_modules", ".nvim", ".venv", "__pycache__", ".ruff_cache", "package-lock.json" }
  local max_files = 10000

  local function scan_dir(path, relative_path)
    if #files >= max_files then vim.notify("Too many files in tree", vim.log.levels.WARN); return end  -- TODO custom
    local items = vim.fn.readdir(path)
    if not items then return end
    for _, item in ipairs(items) do
      local item_path = path .. "/" .. item
      if vim.fn.isdirectory(item_path) == 1 then
        if not is_ignored_dir(item, ignored_dirs) and not is_symlink(item_path) then  -- prevent loops, no dir symlinks
          local new_relative = relative_path == "" and item or relative_path .. "/" .. item
          scan_dir(item_path, new_relative)
        end
      else
        local file_path = relative_path == "" and item or relative_path .. "/" .. item
        if not is_symlink(item_path) then table.insert(files, file_path) end
      end
      if #files >= max_files then vim.notify("Too many files in tree", vim.log.levels.WARN); break end  -- TODO custom
    end
  end

  scan_dir(".", "")
  return files
end

return M
