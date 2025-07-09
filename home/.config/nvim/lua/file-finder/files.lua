local M = {}

local scoring = require("file-finder.scoring")

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
-- 
-- local function get_opened_files_in_table()
--     local lines = {}
--     for line in io.lines(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME) do table.insert(lines, line) end
--     return lines
-- end
-- 
-- local function write_opened_files_in_table(lines)
--     local output_file = io.open(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME, "w")
--     if not output_file then return false end
--     output_file:write(table.concat(lines, '\n'))
--     output_file:close()
--     return true
-- end
-- 
-- local function mark_open_from_name(current_file_path)
--     lines = get_opened_files_in_table()
--     index = find_index(lines, current_file_path)
--     local new_lines = {current_file_path}
--     for i, line in ipairs(lines) do
--         if #new_lines > MAX_SAVED_FILES then break end
--         if i ~= index then table.insert(new_lines, line) end
--     end
--     return write_opened_files_in_table(new_lines)
-- end
-- 
-- local function mark_open_from_table_of_infos(table_of_infos)
--     current_file_path = table_of_infos.match
--     return mark_open_from_name(current_file_path)
-- end


function M.get_files()
  -- doesn't follow symlinks - could add all targets to (links to check / results) if they don't exist, keeping naive rn
  local files = {}
  local ignored_dirs = { ".git", "node_modules", ".nvim", ".venv", "__pycache__", ".ruff_cache" }
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
