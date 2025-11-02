local M = {}

local operations = require("file-explorer.operations")

-- State
M.main_buf = nil
M.main_win = nil
M.backdrop_buf = nil
M.backdrop_win = nil
M.current_dir = nil
M.selected_line = 1
M.entries = {}  -- List of {name, is_dir, path}

local function get_directory_entries(dir)
  local entries = {}
  -- Add parent directory entry (unless we're at root)
  if dir ~= "/" then
    table.insert(entries, {name = "../", is_dir = true, path = vim.fn.fnamemodify(dir, ":h")})
  end
  local items = vim.fn.readdir(dir, function(item)
    return item ~= "." and item ~= ".."
  end)
  if not items then return entries end
  -- Sort: directories first, then files, alphabetically
  table.sort(items, function(a, b)
    local a_path = dir .. "/" .. a
    local b_path = dir .. "/" .. b
    local a_is_dir = vim.fn.isdirectory(a_path) == 1
    local b_is_dir = vim.fn.isdirectory(b_path) == 1
    if a_is_dir and not b_is_dir then
      return true
    elseif not a_is_dir and b_is_dir then
      return false
    else
      return a < b
    end
  end)
  for _, item in ipairs(items) do
    local full_path = dir .. "/" .. item
    local is_dir = vim.fn.isdirectory(full_path) == 1
    local display_name = is_dir and (item .. "/") or item
    table.insert(entries, {name = display_name, is_dir = is_dir, path = full_path})
  end
  return entries
end

local function update_display()
  if not M.main_buf or not vim.api.nvim_buf_is_valid(M.main_buf) then return end
  M.entries = get_directory_entries(M.current_dir)
  local lines = {}
  table.insert(lines, "  " .. M.current_dir)
  table.insert(lines, "")
  for i, entry in ipairs(M.entries) do
    local prefix = (i == M.selected_line) and "> " or "  "
    table.insert(lines, prefix .. entry.name)
  end
  -- Make buffer modifiable to update lines
  vim.api.nvim_buf_set_option(M.main_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.main_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.main_buf, "modifiable", false)
  -- Highlight selected line
  vim.api.nvim_buf_clear_namespace(M.main_buf, -1, 0, -1)
  if M.selected_line > 0 and M.selected_line <= #M.entries then
    vim.api.nvim_buf_add_highlight(M.main_buf, -1, "Visual", M.selected_line + 1, 0, -1)
  end
end

function M.close()
  if M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
    vim.api.nvim_win_close(M.main_win, true)
  end
  if M.backdrop_win and vim.api.nvim_win_is_valid(M.backdrop_win) then
    vim.api.nvim_win_close(M.backdrop_win, true)
  end
  M.main_buf = nil
  M.main_win = nil
  M.backdrop_buf = nil
  M.backdrop_win = nil
end

local function move_selection(delta)
  M.selected_line = math.max(1, math.min(#M.entries, M.selected_line + delta))
  update_display()
end

local function enter_selected()
  if M.selected_line < 1 or M.selected_line > #M.entries then return end
  local entry = M.entries[M.selected_line]
  if entry.is_dir then
    -- Navigate into directory
    M.current_dir = entry.path
    M.selected_line = 1
    update_display()
  else
    -- Open file
    M.close()
    vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
  end
end

local function go_up_directory()
  if M.current_dir == "/" then return end
  M.current_dir = vim.fn.fnamemodify(M.current_dir, ":h")
  M.selected_line = 1
  update_display()
end

local function create_file()
  vim.ui.input({prompt = "New file name: "}, function(filename)
    if not filename or filename == "" then return end
    local success, err = operations.create_file(M.current_dir, filename)
    if success then
      update_display()
      vim.notify("Created: " .. filename, vim.log.levels.INFO)
    else
      vim.notify(err, vim.log.levels.ERROR)
    end
  end)
end

local function create_directory()
  vim.ui.input({prompt = "New directory name: "}, function(dirname)
    if not dirname or dirname == "" then return end
    local success, err = operations.create_directory(M.current_dir, dirname)
    if success then
      update_display()
      vim.notify("Created: " .. dirname .. "/", vim.log.levels.INFO)
    else
      vim.notify(err, vim.log.levels.ERROR)
    end
  end)
end

local function delete_selected()
  if M.selected_line < 1 or M.selected_line > #M.entries then return end
  local entry = M.entries[M.selected_line]
  if entry.name == "../" then return end  -- Can't delete parent dir entry
  vim.ui.input({prompt = "Delete " .. entry.name .. "? (y/N): "}, function(confirm)
    if confirm and confirm:lower() == "y" then
      local success, err = operations.delete_path(entry.path)
      if success then
        update_display()
        vim.notify("Deleted: " .. entry.name, vim.log.levels.INFO)
      else
        vim.notify(err, vim.log.levels.ERROR)
      end
    end
  end)
end

local function rename_selected()
  if M.selected_line < 1 or M.selected_line > #M.entries then return end
  local entry = M.entries[M.selected_line]
  if entry.name == "../" then return end  -- Can't rename parent dir entry
  vim.ui.input({prompt = "Rename to: ", default = entry.name:gsub("/$", "")}, function(new_name)
    if not new_name or new_name == "" then return end
    local success, err = operations.rename_path(entry.path, new_name)
    if success then
      update_display()
      vim.notify("Renamed to: " .. new_name, vim.log.levels.INFO)
    else
      vim.notify(err, vim.log.levels.ERROR)
    end
  end)
end

function M.open()
  -- Get current working directory
  M.current_dir = vim.fn.getcwd()
  M.selected_line = 1
  -- Create backdrop
  M.backdrop_buf = vim.api.nvim_create_buf(false, true)
  local backdrop_lines = {}
  for _ = 1, vim.o.lines do
    table.insert(backdrop_lines, string.rep(" ", vim.o.columns))
  end
  vim.api.nvim_buf_set_lines(M.backdrop_buf, 0, -1, false, backdrop_lines)
  M.backdrop_win = vim.api.nvim_open_win(M.backdrop_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    zindex = 1
  })
  vim.api.nvim_win_set_option(M.backdrop_win, "winblend", 30)
  -- Create main window
  local width = math.floor(vim.o.columns * 0.7)
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  M.main_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.main_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(M.main_buf, "modifiable", false)
  M.main_win = vim.api.nvim_open_win(M.main_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 2
  })
  -- Set keybindings
  local opts = {buffer = M.main_buf, noremap = true, silent = true}
  vim.keymap.set("n", "j", function() move_selection(1) end, opts)
  vim.keymap.set("n", "k", function() move_selection(-1) end, opts)
  vim.keymap.set("n", "<C-k>", function() move_selection(1) end, opts)  -- Match file-finder
  vim.keymap.set("n", "<C-^>", function() move_selection(-1) end, opts)  -- Ctrl+i equivalent
  vim.keymap.set("n", "<CR>", enter_selected, opts)
  vim.keymap.set("n", "l", enter_selected, opts)
  vim.keymap.set("n", "h", go_up_directory, opts)
  vim.keymap.set("n", "a", create_file, opts)
  vim.keymap.set("n", "A", create_directory, opts)
  vim.keymap.set("n", "d", delete_selected, opts)
  vim.keymap.set("n", "r", rename_selected, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
  update_display()
end

return M
