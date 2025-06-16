local M = {}

local scoring = require("file-finder-from-content.scoring")
local ui = require("file-finder-from-content.ui")

local function get_files()  -- TODO check security
  local files = {}
  local ignored_dirs = { ".git", "node_modules", ".nvim", ".venv" }
  local max_files = 10000

  local function is_ignored_dir(dirname)
    for _, ignored in ipairs(ignored_dirs) do if dirname == ignored then return true end end
    return false
  end
  local function is_symlink(path) local stat = vim.loop.fs_lstat(path); return stat and stat.type == 'link' end

  local function scan_dir(path, relative_path)
    if #files >= max_files then vim.notify("Too many files in tree", vim.log.levels.WARN); return end  -- TODO custom
    
    local items = vim.fn.readdir(path)
    if not items then return end
    
    for _, item in ipairs(items) do
      local item_path = path .. "/" .. item

      if vim.fn.isdirectory(item_path) == 1 then
        if not is_ignored_dir(item) and not is_symlink(item) then
          local new_relative = relative_path == "" and item or relative_path .. "/" .. item
          scan_dir(item_path, new_relative)
        end
      else  -- TODO here, could be a symlink, what if the target is malformed on purpose
        local file_path = relative_path == "" and item or relative_path .. "/" .. item
        table.insert(files, file_path)
        if #files >= max_files then vim.notify("Too many files in tree", vim.log.levels.WARN); break end  -- TODO custom
      end
    end
  end
  
  scan_dir(".", "")
  return files
end

function M.find_files()
  local files = get_files()
  if #files == 0 then vim.notify("No files found", vim.log.levels.WARN) return end  -- TODO custom
  
  ui.setup_highlights()
  
  ui.buf, ui.win = ui.create_floating_window()
  ui.prompt_buf, ui.prompt_win = ui.create_prompt_window(ui.win)

  local filtered_files = files
  local selected_line = 0
  local pattern = ""
  local file_line_map = {}

  local function update_display()
    local display_items = {}
    file_line_map = {}
    for i = 1, math.min(#filtered_files, 50) do
      local item = filtered_files[i]
      if type(item) == "table" then
        file_line_map[#display_items] = i
        table.insert(display_items, item.file)
        if item.matched_lines and #item.matched_lines > 0 then
          for j, match in ipairs(item.matched_lines) do
            table.insert(display_items, "  " .. match.line_num .. ": " .. match.content)
          end
        end
      else
        file_line_map[#display_items] = i
        table.insert(display_items, item)
      end
    end
    ui.update_results(ui.buf, display_items, pattern, selected_line, file_line_map)
  end
  
  local function on_input_change()
    local lines = vim.api.nvim_buf_get_lines(ui.prompt_buf, 0, -1, false)
    local new_pattern = lines[1] and lines[1]:gsub("^> ", "") or ""
    
    if new_pattern ~= pattern then
      pattern = new_pattern
      filtered_files = scoring.filter(pattern, files)
      selected_line = 0
      update_display()
    end
  end
  
  local function select_file()
    local file_index = file_line_map[selected_line]
    if file_index and file_index <= #filtered_files then
      local item = filtered_files[file_index]
      local file = type(item) == "table" and item.file or item
      ui.close()
      vim.cmd("edit " .. vim.fn.fnameescape(file))
    end
  end
  
  local function move_selection(direction)
    local display_line_count = 0
    for _, _ in pairs(file_line_map) do display_line_count = display_line_count + 1 end
    local max_line = math.min(display_line_count - 1, 49)

    repeat
      selected_line = math.max(0, math.min(max_line, selected_line + direction))
    until file_line_map[selected_line] or selected_line == 0 or selected_line == max_line

    update_display()
    vim.api.nvim_win_set_cursor(ui.win, {selected_line + 1, 0})
  end
  
  vim.api.nvim_buf_attach(ui.prompt_buf, false, { on_lines = function() vim.schedule(on_input_change) end })
 
  local sk = vim.api.nvim_buf_set_keymap
  sk(ui.prompt_buf, "i", "<CR>",  "", { callback = select_file,                       noremap = true, silent = true })
  sk(ui.prompt_buf, "i", "<C-k>", "", { callback = function() move_selection(1) end,  noremap = true, silent = true })
  sk(ui.prompt_buf, "i", "<C-^>", "", { callback = function() move_selection(-1) end, noremap = true, silent = true })
  sk(ui.prompt_buf, "i", "<Esc>", "", { callback = ui.close,                          noremap = true, silent = true })
  sk(ui.buf,        "n", "<CR>",  "", { callback = select_file,                       noremap = true, silent = true })
  sk(ui.buf,        "n", "q",     "", { callback = ui.close,                          noremap = true, silent = true })
  sk(ui.buf,        "n", "<Esc>", "", { callback = ui.close,                          noremap = true, silent = true })
  update_display()
  vim.cmd("startinsert")
end

return M
