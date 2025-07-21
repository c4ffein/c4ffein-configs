local M = {}

local config = require("file-finder.config")

M.HOME = vim.env.HOME or vim.env.USERPROFILE -- USERPROFILE for Windows
if M.HOME:sub(-1) ~= "/" then M.HOME = M.HOME .. "/" end

local function is_ignored_dir(dirname, ignored_dirs)
  for _, ignored in ipairs(ignored_dirs) do if dirname == ignored then return true end end
  return false
end

local function is_symlink(path) local stat = vim.loop.fs_lstat(path); return stat and stat.type == 'link' end

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
    if #files >= max_files then vim.notify("Too many files in tree", vim.log.levels.WARN); return end
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
      if #files >= max_files then vim.notify("Too many files in tree", vim.log.levels.WARN); break end
    end
  end

  scan_dir(".", "")
  local return_table = {}
  for _, file in ipairs(files) do table.insert(return_table, { file = file }) end
  return return_table
end

function M.get_printable_file_infos(file_path)
  local path_starter, short_path, selected_color = "/", file_path, "FileFinderPathRoot"
  if short_path:sub(1, #config.current_directory) == config.current_directory then
    path_starter, selected_color = ".", "FileFinderPathCd"
    short_path = short_path:sub(#config.current_directory + 1, #short_path)
  elseif short_path:sub(1, #M.HOME) == M.HOME then
    path_starter, selected_color = "~", "FileFinderPathHome"
    short_path = short_path:sub(#M.HOME + 1, #short_path)
  else
    short_path = short_path:sub(2, #short_path)
  end
  return {
    full_path = file_path, path_starter = path_starter, short_path = short_path, selected_color = selected_color
  }
end

return M
