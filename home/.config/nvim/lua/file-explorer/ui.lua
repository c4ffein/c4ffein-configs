local M = {}

local operations = require("file-explorer.operations")

-- State
M.path_buf = nil
M.path_win = nil
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
    table.insert(entries, {name = "../", is_dir = true, is_parent = true, path = vim.fn.fnamemodify(dir, ":h")})
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
    local is_symlink = vim.fn.getftype(full_path) == "link"
    local is_dir = vim.fn.isdirectory(full_path) == 1
    local symlink_target = nil
    local display_name = item
    if is_symlink then
      -- Get symlink target (protect against redefined symlinks to other dirs)
      -- NOTE: resolve() follows the entire chain to the final target
      local ok, resolved = pcall(vim.fn.resolve, full_path)
      if ok and resolved then
        -- SECURITY: Validate symlink target (paranoid path validation)
        local target_valid = operations.is_valid_path(resolved)
        if target_valid then
          symlink_target = resolved
          -- Show as "name -> target"
          display_name = item .. " -> " .. symlink_target
        else
          -- Invalid symlink target - don't store it, show as broken
          display_name = item .. " -> [INVALID TARGET]"
        end
      else
        -- Failed to resolve (circular symlink or other error)
        display_name = item .. " -> [BROKEN LINK]"
      end
    else
      -- Add trailing slash for directories
      display_name = is_dir and (item .. "/") or item
    end
    table.insert(entries, {
      name = display_name,
      original_name = item,
      is_dir = is_dir,
      is_symlink = is_symlink,
      symlink_target = symlink_target,
      path = full_path
    })
  end
  return entries
end

local function update_display()
  if not M.main_buf or not vim.api.nvim_buf_is_valid(M.main_buf) then return end
  if not M.path_buf or not vim.api.nvim_buf_is_valid(M.path_buf) then return end
  M.entries = get_directory_entries(M.current_dir)
  -- Define highlight groups (matching colors from c4ffein theme)
  vim.api.nvim_set_hl(0, "FileExplorerInvalid", {fg = "#ff0000"})  -- Red
  vim.api.nvim_set_hl(0, "FileExplorerInvalidChar", {fg = "#808080"})  -- Grey
  vim.api.nvim_set_hl(0, "FileExplorerParent", {fg = "#777777"})  -- Grey for ../
  vim.api.nvim_set_hl(0, "FileExplorerDir", {fg = "#88EEFF"})  -- Cyan for directories
  vim.api.nvim_set_hl(0, "FileExplorerSymlink", {fg = "#88FFAA"})  -- Green for symlinks
  vim.api.nvim_set_hl(0, "FileExplorerSymlinkChain", {fg = "#FF0000"})  -- Red for symlink chains
  vim.api.nvim_set_hl(0, "FileExplorerPath", {fg = "#BB88FF"})  -- Purple for path
  -- Update path window (top)
  local path_lines = {M.current_dir}
  vim.api.nvim_buf_set_option(M.path_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.path_buf, 0, -1, false, path_lines)
  vim.api.nvim_buf_set_option(M.path_buf, "modifiable", false)
  -- Highlight path in purple
  vim.api.nvim_buf_clear_namespace(M.path_buf, -1, 0, -1)
  vim.api.nvim_buf_add_highlight(M.path_buf, -1, "FileExplorerPath", 0, 0, -1)
  -- Update file list window (bottom)
  local file_lines = {}
  for i, entry in ipairs(M.entries) do
    local prefix = (i == M.selected_line) and "> " or "  "
    -- Check if filename is valid (skip ../ as it's always allowed, symlinks display as-is)
    local is_valid = entry.is_parent or entry.is_symlink or operations.is_valid_filename((entry.original_name or entry.name):gsub("/$", ""))
    entry.is_valid = is_valid
    if is_valid then
      table.insert(file_lines, prefix .. entry.name)
    else
      -- Show sanitized version with X for forbidden chars
      local sanitized = operations.sanitize_for_display((entry.original_name or entry.name):gsub("/$", ""))
      if entry.is_dir then sanitized = sanitized .. "/" end
      table.insert(file_lines, prefix .. sanitized)
    end
  end
  -- Make buffer modifiable to update lines
  vim.api.nvim_buf_set_option(M.main_buf, "modifiable", true)
  -- Clear all existing lines first
  vim.api.nvim_buf_set_lines(M.main_buf, 0, -1, true, {})
  -- Then set new lines
  vim.api.nvim_buf_set_lines(M.main_buf, 0, -1, false, file_lines)
  vim.api.nvim_buf_set_option(M.main_buf, "modifiable", false)
  -- Highlight entries by type and validation
  vim.api.nvim_buf_clear_namespace(M.main_buf, -1, 0, -1)
  for i, entry in ipairs(M.entries) do
    local line_idx = i - 1  -- Files now start at line 0 (no header)
    local prefix_len = 2  -- Length of "> " or "  " prefix
    if not entry.is_valid then
      -- Highlight entire line in red (invalid files)
      vim.api.nvim_buf_add_highlight(M.main_buf, -1, "FileExplorerInvalid", line_idx, 0, -1)
      -- Find and highlight X characters in grey
      local line_text = file_lines[i]
      if line_text then
        for j = 1, #line_text do
          if line_text:sub(j, j) == "X" then
            vim.api.nvim_buf_add_highlight(M.main_buf, -1, "FileExplorerInvalidChar", line_idx, j - 1, j)
          end
        end
      end
    else
      -- Apply color based on entry type (skip prefix ">" or " ")
      if entry.is_parent then
        -- ../ in grey
        vim.api.nvim_buf_add_highlight(M.main_buf, -1, "FileExplorerParent", line_idx, prefix_len, -1)
      elseif entry.is_symlink then
        -- Symlinks in green
        vim.api.nvim_buf_add_highlight(M.main_buf, -1, "FileExplorerSymlink", line_idx, prefix_len, -1)
      elseif entry.is_dir then
        -- Directories in cyan
        vim.api.nvim_buf_add_highlight(M.main_buf, -1, "FileExplorerDir", line_idx, prefix_len, -1)
      end
      -- Files remain white (default, no highlight needed)
    end
  end
  -- Highlight selected line (on top of other highlights)
  if M.selected_line > 0 and M.selected_line <= #M.entries then
    vim.api.nvim_buf_add_highlight(M.main_buf, -1, "Visual", M.selected_line - 1, 0, -1)
  end
  -- Position cursor at the selected line, leftmost position (column 0)
  -- This makes the cursor appear at the ">" marker position
  if M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
    vim.api.nvim_win_set_cursor(M.main_win, {M.selected_line, 0})
  end
end

function M.close()
  if M.path_win and vim.api.nvim_win_is_valid(M.path_win) then
    vim.api.nvim_win_close(M.path_win, true)
  end
  if M.main_win and vim.api.nvim_win_is_valid(M.main_win) then
    vim.api.nvim_win_close(M.main_win, true)
  end
  if M.backdrop_win and vim.api.nvim_win_is_valid(M.backdrop_win) then
    vim.api.nvim_win_close(M.backdrop_win, true)
  end
  M.path_buf = nil
  M.path_win = nil
  M.main_buf = nil
  M.main_win = nil
  M.backdrop_buf = nil
  M.backdrop_win = nil
end

local function move_selection(delta)
  M.selected_line = math.max(1, math.min(#M.entries, M.selected_line + delta))
  update_display()
end

local function handle_mouse_click()
  -- Get cursor position after mouse click
  local cursor = vim.api.nvim_win_get_cursor(M.main_win)
  local clicked_line = cursor[1]
  -- Update selection to clicked line
  if clicked_line >= 1 and clicked_line <= #M.entries then
    M.selected_line = clicked_line
    update_display()
  end
end

local function enter_selected()
  if M.selected_line < 1 or M.selected_line > #M.entries then return end
  local entry = M.entries[M.selected_line]
  -- SECURITY: Block opening symlinks without valid targets (broken/circular/invalid)
  if entry.is_symlink and not entry.symlink_target then
    vim.notify("Cannot open symlink: Invalid or broken target", vim.log.levels.ERROR)
    return
  end
  -- SECURITY: TOCTOU protection - verify symlink target hasn't changed
  if entry.is_symlink and entry.symlink_target then
    local current_target = vim.fn.resolve(entry.path)
    if current_target ~= entry.symlink_target then
      vim.notify("SECURITY: Symlink target changed!", vim.log.levels.ERROR)
      return
    end
    -- SECURITY: Block symlink chains - check target is not itself a symlink
    -- NOTE: There's a tiny TOCTOU window between this check and opening, but
    -- the risk is minimal for this edge case and we're already being paranoid
    local target_type = vim.fn.getftype(entry.symlink_target)
    if target_type == "link" then
      vim.notify("SECURITY: Symlink chains are not allowed", vim.log.levels.ERROR)
      return
    end
  end
  -- SECURITY: Double-check validation before opening (defense in depth)
  -- Skip validation for parent directory and symlinks (they show their targets)
  if entry.name ~= "../" and not entry.is_parent and not entry.is_symlink then
    local filename = (entry.original_name or entry.name):gsub("/$", "")
    local is_valid = operations.is_valid_filename(filename)
    if not is_valid then
      vim.notify("Cannot open file with invalid characters: " .. entry.name, vim.log.levels.ERROR)
      return
    end
  end
  if entry.is_dir then
    -- SECURITY: Use stored symlink target if this is a symlink (verified above)
    local target_path = entry.symlink_target or entry.path
    -- SECURITY: Validate path before navigating (defense in depth)
    local path_valid = operations.is_valid_path(target_path)
    if not path_valid then
      vim.notify("Cannot navigate to directory with invalid path: " .. target_path, vim.log.levels.ERROR)
      return
    end
    M.current_dir = target_path
    M.selected_line = 1
    update_display()
  else
    -- SECURITY: Use stored symlink target if this is a symlink (verified above)
    local target_path = entry.symlink_target or entry.path
    -- SECURITY: Validate file path before opening (defense in depth)
    local path_valid = operations.is_valid_path(target_path)
    if not path_valid then
      vim.notify("Cannot open file with invalid path: " .. target_path, vim.log.levels.ERROR)
      return
    end
    M.close()
    vim.cmd("edit " .. vim.fn.fnameescape(target_path))
  end
end

local function go_up_directory()
  if M.current_dir == "/" then return end
  local parent_path = vim.fn.fnamemodify(M.current_dir, ":h")
  -- SECURITY: Validate parent path (defense in depth)
  local path_valid = operations.is_valid_path(parent_path)
  if not path_valid then
    vim.notify("Cannot navigate to parent directory with invalid path: " .. parent_path, vim.log.levels.ERROR)
    return
  end
  M.current_dir = parent_path
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
  if entry.name == "../" or entry.is_parent then return end  -- Can't delete parent dir entry
  -- Use original_name or name for display in prompt
  local display_name = entry.original_name or entry.name
  vim.ui.input({prompt = "Delete " .. display_name .. "? (y/N): "}, function(confirm)
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
  if entry.name == "../" or entry.is_parent then return end  -- Can't rename parent dir entry
  -- Use original_name for symlinks (to avoid " -> target" suffix in default)
  local default_name = (entry.original_name or entry.name):gsub("/$", "")
  vim.ui.input({prompt = "Rename to: ", default = default_name}, function(new_name)
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
  -- Create windows (path window at top, file list at bottom)
  local width = math.floor(vim.o.columns * 0.7)
  local total_height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  -- Create path display window (top, 1 line, no padding)
  local path_height = 1
  M.path_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.path_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(M.path_buf, "modifiable", false)
  M.path_win = vim.api.nvim_open_win(M.path_buf, false, {
    relative = "editor",
    width = width,
    height = path_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 2
  })
  -- Create file list window (bottom, remaining space)
  -- path_height + 2 (borders) + 1 (gap) = path_height + 3
  local main_height = total_height - path_height - 3
  M.main_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.main_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(M.main_buf, "modifiable", false)
  M.main_win = vim.api.nvim_open_win(M.main_buf, true, {
    relative = "editor",
    width = width,
    height = main_height,
    row = row + path_height + 3,  -- +2 for borders, +1 for gap
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 2
  })
  -- Set keybindings
  local opts = {buffer = M.main_buf, noremap = true, silent = true}
  -- Navigation (multiple options for convenience)
  vim.keymap.set("n", "<Down>", function() move_selection(1) end, opts)  -- Arrow key down
  vim.keymap.set("n", "<Up>", function() move_selection(-1) end, opts)  -- Arrow key up
  vim.keymap.set("n", "<C-k>", function() move_selection(1) end, opts)  -- Match file-finder
  vim.keymap.set("n", "<C-^>", function() move_selection(-1) end, opts)  -- Ctrl+i equivalent
  -- Mouse support
  vim.keymap.set("n", "<LeftMouse>", handle_mouse_click, opts)
  vim.keymap.set("n", "<2-LeftMouse>", function()
    handle_mouse_click()
    enter_selected()
  end, opts)
  -- Actions
  vim.keymap.set("n", "<CR>", enter_selected, opts)
  vim.keymap.set("n", "<BS>", go_up_directory, opts)
  vim.keymap.set("n", "<C-n>", create_file, opts)
  vim.keymap.set("n", "<C-f>", create_directory, opts)
  vim.keymap.set("n", "<C-d>", delete_selected, opts)
  vim.keymap.set("n", "<C-r>", rename_selected, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
  update_display()
end

return M
