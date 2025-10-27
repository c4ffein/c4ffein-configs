-- Make Target Runner
-- Press 'm' to show Makefile targets, press number to run instantly
--
-- Security: Target names restricted to [a-zA-Z0-9._-] to prevent shell injection
-- Commands executed via list form of termopen (no shell interpretation)

local M = {}

-- Security: Separate charsets for different purposes - principle of least privilege
-- KISS: Explicit strings, no regex magic - paranoid char-by-char validation
local TARGET_SAFE_CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
local TIMESTAMP_SAFE_CHARSET = "0123456789"
local TEMPFILE_SUFFIX_SAFE_CHARSET = "0123456789."  -- After ".tmp." only digits and dots
-- ASCII printable chars for paths (reject unicode tricks, homoglyphs, zero-width chars)
local PATH_SAFE_CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/ "
  .. "!\"#$%&'()*+,:;<=>?@[\\]^`{|}~"  -- Other ASCII printable
-- ASCII printable for descriptions (no control chars, no escape sequences)
local DESC_SAFE_CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
  .. ".,!?;:'\"-_()[]{}/@#$%&*+=<>|~`"  -- Printable ASCII, no backslash/newline/tabs

-- State
local state = {
  win_main = nil, win_prompt = nil, win_output = nil, win_backdrop = nil,
  buf_main = nil, buf_prompt = nil, buf_output = nil,
  targets = {},
  filtered_targets = {},
  selected_idx = 1,
  search_query = "",
  history = {}, -- { target_name = timestamp } -- we can allow ourselves to stay KISS and have a common list to all
  makefile_dir = nil, -- Directory containing the Makefile (for make -C)
  job_id = nil, -- Job ID of running make process (for proper cleanup)
}

-- Validate target name (security: only allow safe characters)
-- KISS: Paranoid char-by-char validation, no pattern matching
local function is_valid_target_name(name)
  if not name or name == "" then return false end
  for i = 1, #name do
    local char = name:sub(i, i)
    if not TARGET_SAFE_CHARSET:find(char, 1, true) then return false end
  end
  return true
end

-- Validate timestamp (security: only allow digits)
-- KISS: Paranoid char-by-char validation, no pattern matching
local function is_valid_timestamp(timestamp)
  if not timestamp or timestamp == "" then return false end
  for i = 1, #timestamp do
    local char = timestamp:sub(i, i)
    if not TIMESTAMP_SAFE_CHARSET:find(char, 1, true) then return false end
  end
  return true
end

-- Validate temp file name (security: prevent malicious symlinks or files)
-- KISS: Check prefix, then paranoid char-by-char validation of suffix
local function is_valid_temp_file(file, history_file)
  local expected_prefix = history_file .. ".tmp."
  -- Must start with expected prefix
  if not file:sub(1, #expected_prefix) == expected_prefix then return false end
  -- Extract suffix after prefix
  local suffix = file:sub(#expected_prefix + 1)
  if not suffix or suffix == "" then return false end
  -- Validate suffix contains only digits and dots
  for i = 1, #suffix do
    local char = suffix:sub(i, i)
    if not TEMPFILE_SUFFIX_SAFE_CHARSET:find(char, 1, true) then return false end
  end
  return true
end

-- Validate path (security: reject unicode homoglyphs, zero-width chars, etc)
-- KISS: Paranoid char-by-char validation - ASCII printable only
local function is_valid_path(path)
  if not path or path == "" then return false end
  for i = 1, #path do
    local char = path:sub(i, i)
    if not PATH_SAFE_CHARSET:find(char, 1, true) then return false end
  end
  return true
end

-- Validate description (security: reject control chars, escape sequences)
-- KISS: Paranoid char-by-char validation, no ANSI codes or sneaky stuff
local function is_valid_desc(desc)
  if not desc then return false end
  if desc == "" then return true end  -- Empty desc is OK
  for i = 1, #desc do
    local char = desc:sub(i, i)
    if not DESC_SAFE_CHARSET:find(char, 1, true) then return false end
  end
  return true
end

-- History file
local history_file = vim.fn.stdpath("data") .. "/make-runner-history"

-- Clean up stale temp files (silent, forensic window for debugging)
local function cleanup_stale_temp_files()
  local pattern = history_file .. ".tmp.*"
  local files = vim.fn.glob(pattern, false, true)
  local cutoff = os.time() - 3600  -- 1 hour ago
  for _, file in ipairs(files) do
    -- Security: Paranoid validation - only delete files we created
    if is_valid_temp_file(file, history_file) then
      local mtime = vim.fn.getftime(file)
      if mtime > 0 and mtime < cutoff then os.remove(file) end
    end
  end
end

-- Load history
local function load_history()
  cleanup_stale_temp_files()  -- Clean up on load
  local file = io.open(history_file, "r")
  if not file then return {} end
  local history = {}
  for line in file:lines() do
    -- Security: Parse line, then paranoid char-by-char validation of BOTH fields
    local target, timestamp = line:match("^(.+):(.+)$")
    if target and timestamp and is_valid_target_name(target) and is_valid_timestamp(timestamp) then
      history[target] = tonumber(timestamp)
    end
  end
  file:close()
  return history
end

-- Save history (atomic write via temp file + rename)
local function save_history()
  -- Use PID + timestamp for uniqueness (overkill but guarantees no collision even with PID reuse)
  local pid = vim.fn.getpid()
  local unique = os.time() .. math.random(10000, 99999)  -- timestamp + random for uniqueness
  local temp_file = history_file .. ".tmp." .. pid .. "." .. unique
  local file = io.open(temp_file, "w")
  if not file then return end
  for target, timestamp in pairs(state.history) do file:write(target .. ":" .. timestamp .. "\n") end
  file:close()
  os.rename(temp_file, history_file)  -- atomic rename, last writer wins
end

-- Update history
local function update_history(target_name)
  state.history[target_name] = os.time()
  save_history()
end

-- Find Makefile by walking up directory tree
local function find_makefile()
  local current = vim.fn.getcwd()
  -- Security: Reject non-ASCII paths (unicode homoglyphs, zero-width chars, etc)
  if not is_valid_path(current) then return nil end
  while current ~= "/" do
    local makefile = current .. "/Makefile"
    if vim.fn.filereadable(makefile) == 1 then
      -- Security: Double-check constructed path is ASCII-only -- overly paranoid due to previous check but whatever
      if is_valid_path(makefile) then return makefile else return nil end
    end
    current = vim.fn.fnamemodify(current, ":h")
  end
  return nil
end

-- Parse Makefile for targets
local function parse_makefile(filepath)
  local targets = {}
  local file = io.open(filepath, "r")
  if not file then return targets end
  for line in file:lines() do
    -- Match: "target: ## Description"
    -- Security: Validate BOTH target AND description (no escape sequences, control chars)
    local target, desc = line:match("^([%w%.%-_]+):%s*##%s*(.+)")
    if target and desc and is_valid_target_name(target) and is_valid_desc(desc) then
      table.insert(targets, { name = target, desc = desc })
    else
      -- Match any target without description
      local target_only = line:match("^([%w%.%-_]+):$")
      if target_only and target_only ~= ".PHONY" and target_only ~= ".SILENT" and target_only ~= ".DEFAULT_GOAL" then
        -- Security check
        if is_valid_target_name(target_only) then
          -- Check if we haven't already added this target
          local exists = false
          for _, t in ipairs(targets) do if t.name == target_only then exists = true break end end
          if not exists then table.insert(targets, { name = target_only, desc = "" }) end
        end
      end
    end
  end
  file:close()
  return targets
end

-- Filter and sort targets
local function filter_targets()
  if state.search_query == "" then
    state.filtered_targets = vim.deepcopy(state.targets)
  else
    state.filtered_targets = {}
    local query_lower = state.search_query:lower()
    for _, target in ipairs(state.targets) do
      if target.name:lower():find(query_lower, 1, true) or target.desc:lower():find(query_lower, 1, true) then
        table.insert(state.filtered_targets, target)
      end
    end
  end
  -- Sort by history (most recent first)
  table.sort(state.filtered_targets, function(a, b)
    local time_a = state.history[a.name] or 0
    local time_b = state.history[b.name] or 0
    return time_a > time_b
  end)
  state.selected_idx = math.min(state.selected_idx, #state.filtered_targets)
  if state.selected_idx < 1 then state.selected_idx = 1 end
end

-- Render the UI
local function render()
  if not state.buf_main or not vim.api.nvim_buf_is_valid(state.buf_main) then return end
  local lines = {}
  local highlights = {}
  -- Targets
  for i, target in ipairs(state.filtered_targets) do
    local prefix = i <= 10 and string.format(" %d ", (i % 10)) or "   "
    local selected = (i == state.selected_idx) and "▶ " or "  "
    local desc_part = target.desc ~= "" and ("  " .. target.desc) or ""
    local line = prefix .. selected .. target.name .. desc_part
    table.insert(lines, line)
    -- Highlight number
    if i <= 10 then
      table.insert(highlights, { line = #lines - 1, col_start = 1, col_end = 3, hl_group = "Number" })
    end
    -- Highlight target name
    local name_start = #prefix + #selected
    table.insert(highlights, {
      line = #lines - 1,
      col_start = name_start,
      col_end = name_start + #target.name,
      hl_group = i == state.selected_idx and "String" or "Identifier"
    })
    -- Highlight description
    if target.desc ~= "" then
      table.insert(highlights, {
        line = #lines - 1,
        col_start = name_start + #target.name + 2,
        col_end = #line,
        hl_group = "Comment"
      })
    end
  end
  if #state.filtered_targets == 0 then
    table.insert(lines, "  No targets found")
  end
  -- Set lines
  vim.api.nvim_buf_set_option(state.buf_main, "modifiable", true)
  vim.api.nvim_buf_set_lines(state.buf_main, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf_main, "modifiable", false)
  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("make_runner")
  vim.api.nvim_buf_clear_namespace(state.buf_main, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf_main, ns_id, hl.hl_group, hl.line, hl.col_start, hl.col_end)
  end
  -- Sync cursor position to match selected_idx (fixes cursorline mismatch)
  if state.win_main and vim.api.nvim_win_is_valid(state.win_main) then
    vim.api.nvim_win_set_cursor(state.win_main, {state.selected_idx, 0})
  end
end

-- Update prompt display
local function update_prompt()
  if not state.buf_prompt or not vim.api.nvim_buf_is_valid(state.buf_prompt) then return end
  -- The prompt buffer automatically shows "> " + typed text
end

-- Kill process tree recursively (nuclear option for stubborn background jobs)
local function kill_process_tree(pid)
  if not pid or pid <= 0 then return end
  local pid_str = tostring(pid)
  -- PARANOID: Validate PID is digits only
  if not pid_str:match("^%d+$") then return end
  -- Find all children recursively using pgrep
  -- Use list form for safety
  local result = vim.fn.system({'pgrep', '-P', pid_str})
  local children = vim.split(result, '\n', {trimempty = true})
  -- Recursively kill all children first
  for _, child_pid_str in ipairs(children) do
    -- Paranoid validation of each child PID
    if child_pid_str:match("^%d+$") then
      kill_process_tree(tonumber(child_pid_str))
    end
  end
  -- Then kill the parent with SIGKILL
  vim.fn.system({'kill', '-KILL', pid_str})
end

-- Close output modal
local function close_output_modal()
  -- Kill the running job and ALL its descendants (prevents orphaned processes)
  if state.job_id then
    -- Use pcall to handle case where job already finished
    local ok, pid = pcall(vim.fn.jobpid, state.job_id)
    if ok and pid > 0 then
      -- Job is still running, kill it
      -- First try polite termination
      vim.fn.jobstop(state.job_id)
      -- Then nuclear option: recursively kill entire process tree
      kill_process_tree(pid)
    end
    -- Job already finished or was killed, just clean up
    state.job_id = nil
  end
  if state.win_output and vim.api.nvim_win_is_valid(state.win_output) then
    vim.api.nvim_win_close(state.win_output, true)
  end
  if state.win_backdrop and vim.api.nvim_win_is_valid(state.win_backdrop) then
    vim.api.nvim_win_close(state.win_backdrop, true)
  end
  state.win_output = nil
  state.win_backdrop = nil
  state.buf_output = nil
end

-- Run make target in modal
local function run_target(target_name)
  -- TODO SECURE OUTPUT IN MODAL
  -- Security: Double-check makefile_dir before using it
  if not state.makefile_dir or not is_valid_path(state.makefile_dir) then
    print("Invalid Makefile directory")
    return
  end
  -- Update history
  update_history(target_name)
  -- Close target selector UI (keep backdrop)
  if state.win_main and vim.api.nvim_win_is_valid(state.win_main) then
    vim.api.nvim_win_close(state.win_main, true)
  end
  if state.win_prompt and vim.api.nvim_win_is_valid(state.win_prompt) then
    vim.api.nvim_win_close(state.win_prompt, true)
  end
  state.win_main = nil
  state.win_prompt = nil
  -- Get editor dimensions
  local width = vim.o.columns
  local height = vim.o.lines
  local win_width = math.min(120, math.floor(width * 0.9))
  local win_height = math.min(30, math.floor(height * 0.8))
  local row = math.floor((height - win_height) / 2)
  local col = math.floor((width - win_width) / 2)
  -- Backdrop already exists (reuse it)
  -- Create output window (black background)
  state.buf_output = vim.api.nvim_create_buf(false, true)
  state.win_output = vim.api.nvim_open_win(state.buf_output, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })
  -- Set buffer options
  vim.api.nvim_buf_set_option(state.buf_output, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(state.buf_output, "buftype", "nofile")
  -- Set window options and hide cursor
  vim.api.nvim_win_set_option(state.win_output, "winhl", "Normal:Normal")
  -- Hide cursor by making it fully transparent (blend with background)
  vim.cmd("highlight TermCursor blend=100")
  vim.cmd("highlight TermCursorNC blend=100")
  -- Set up keybinds to close
  vim.keymap.set('n', 'q', close_output_modal, { buffer = state.buf_output, noremap = true, silent = true })
  vim.keymap.set('n', '<Esc>', close_output_modal, { buffer = state.buf_output, noremap = true, silent = true })
  -- Auto-close on focus lost
  vim.api.nvim_create_autocmd('WinLeave', { buffer = state.buf_output, once = true, callback = close_output_modal })
  -- Hide cursor for cleaner UX while output is streaming
  local saved_guicursor = vim.o.guicursor
  vim.api.nvim_create_autocmd('TermOpen', {
    buffer = state.buf_output,
    once = true,
    callback = function()
      vim.opt_local.guicursor = 'a:hor1-Cursor/lCursor'  -- Thin horizontal line (nearly invisible)
    end
  })
  -- Restore cursor when leaving
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = state.buf_output,
    once = true,
    callback = function()
      vim.o.guicursor = saved_guicursor
    end
  })
  -- Run make in terminal mode inside the buffer
  -- Use list form to prevent shell interpretation (security)
  -- Use -C to run from the Makefile's directory
  -- Store job_id for proper cleanup (kills all child processes on close)
  state.job_id = vim.fn.termopen({'make', '-C', state.makefile_dir, target_name})
  -- Move cursor to end for auto-scroll, then enter terminal mode
  vim.cmd("normal! G")
  vim.cmd("startinsert")
end

-- Handle prompt input
local function on_prompt_input()
  -- Check if buffer still exists
  if not state.buf_prompt or not vim.api.nvim_buf_is_valid(state.buf_prompt) then return end
  -- Get current prompt text (remove "> " prefix)
  local lines = vim.api.nvim_buf_get_lines(state.buf_prompt, 0, -1, false)
  if #lines > 0 then state.search_query = lines[1]:gsub("^> ", "") else state.search_query = "" end
  filter_targets()
  render()
end

-- Handle key press in main window
local function handle_key(key)
  if key == "q" or key == "<Esc>" then
    M.close()
  elseif key == "<CR>" then
    if #state.filtered_targets > 0 and state.selected_idx > 0 then
      run_target(state.filtered_targets[state.selected_idx].name)
    end
  elseif key == "k" or key == "<C-k>" then
    state.selected_idx = math.min(state.selected_idx + 1, #state.filtered_targets)
    render()
  elseif key == "i" or key == "<C-^>" then
    state.selected_idx = math.max(state.selected_idx - 1, 1)
    render()
  elseif key == "0" then
    M.close()
  elseif key:match("^[1-9]$") then
    local num = tonumber(key)
    if num <= #state.filtered_targets then run_target(state.filtered_targets[num].name) end
  end
end

-- Create UI windows
local function create_ui()
  -- Get editor dimensions
  local width = vim.o.columns
  local height = vim.o.lines
  -- Calculate window sizes (matching file-finder pattern)
  local main_width = math.min(100, math.floor(width * 0.8))
  local main_height = math.min(20, math.floor(height * 0.6))
  local main_row = math.floor((height - main_height) / 2)
  local main_col = math.floor((width - main_width) / 2)
  -- Prompt is ABOVE main window
  local prompt_width = main_width
  local prompt_height = 1
  local prompt_row = main_row - 3
  local prompt_col = main_col
  -- Create backdrop (reused for both select and execute states)
  local buf_backdrop = vim.api.nvim_create_buf(false, true)
  state.win_backdrop = vim.api.nvim_open_win(buf_backdrop, false, {
    relative = "editor",
    width = width,
    height = height,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 1,
  })
  vim.api.nvim_win_set_option(state.win_backdrop, "winblend", 30)
  -- Create prompt window (TOP)
  state.buf_prompt = vim.api.nvim_create_buf(false, true)
  state.win_prompt = vim.api.nvim_open_win(state.buf_prompt, true, {
    relative = "editor", style = "minimal", border = "single",
    width = prompt_width, height = prompt_height, row = prompt_row, col = prompt_col,
  })
  vim.api.nvim_buf_set_option(state.buf_prompt, "buftype", "prompt")
  vim.api.nvim_buf_set_option(state.buf_prompt, "bufhidden", "wipe")
  vim.fn.prompt_setprompt(state.buf_prompt, "> ")
  -- Set up prompt callback
  vim.fn.prompt_setcallback(state.buf_prompt, function()
    -- Enter pressed in prompt - run selected target
    if #state.filtered_targets > 0 and state.selected_idx > 0 then
      run_target(state.filtered_targets[state.selected_idx].name)
    end
  end)
  -- Watch for prompt changes
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    buffer = state.buf_prompt,
    callback = on_prompt_input
  })
  -- Main results window (BOTTOM)
  state.buf_main = vim.api.nvim_create_buf(false, true)
  state.win_main = vim.api.nvim_open_win(state.buf_main, false, {
    relative = "editor", style = "minimal", border = "single",
    width = main_width, height = main_height, row = main_row, col = main_col,
  })
  vim.api.nvim_buf_set_option(state.buf_main, "modifiable", false)
  vim.api.nvim_buf_set_option(state.buf_main, "bufhidden", "wipe")
  vim.api.nvim_win_set_option(state.win_main, "cursorline", true)
  -- Set up keymaps in main window
  local opts = { noremap = true, silent = true, buffer = state.buf_main }
  for _, key in ipairs({'q', '<Esc>', '<CR>', 'k', 'i', '<C-k>', '<C-^>'}) do
    vim.keymap.set('n', key, function() handle_key(key) end, opts)
  end
  for i = 0, 9 do vim.keymap.set('n', tostring(i), function() handle_key(tostring(i)) end, opts) end
  -- Mouse click support - select target on click
  vim.keymap.set('n', '<LeftRelease>', function()
    local pos = vim.fn.getmousepos()
    if pos.winid == state.win_main then
      local line = pos.line
      if line > 0 and line <= #state.filtered_targets then
        state.selected_idx = line
        render()
      end
    end
    return ""  -- Return empty string to prevent default mouse behavior
  end, { noremap = true, silent = true, buffer = state.buf_main, expr = true })
  -- Set up keymaps in prompt window (for navigation)
  local prompt_opts = { noremap = true, silent = true, buffer = state.buf_prompt }
  vim.keymap.set('n', 'q', function() M.close() end, prompt_opts)
  vim.keymap.set('n', '<Esc>', function() M.close() end, prompt_opts)
  -- Close from insert mode
  vim.keymap.set('i', '<Esc>', function() M.close() end, prompt_opts)
  -- Navigation from insert mode
  vim.keymap.set('i', '<C-k>', function()
    state.selected_idx = math.min(state.selected_idx + 1, #state.filtered_targets)
    render()
  end, prompt_opts)
  vim.keymap.set('i', '<C-^>', function()
    state.selected_idx = math.max(state.selected_idx - 1, 1)
    render()
  end, prompt_opts)
  -- Number shortcuts in prompt (insert mode - execute, don't type)
  -- 0 closes, 1-9 execute targets
  vim.keymap.set('i', '0', function()
    M.close()
  end, { noremap = true, silent = true, buffer = state.buf_prompt })

  for i = 1, 9 do
    vim.keymap.set('i', tostring(i), function()
      if i <= #state.filtered_targets then
        run_target(state.filtered_targets[i].name)
      end
    end, { noremap = true, silent = true, buffer = state.buf_prompt })
  end
  -- Close on focus lost
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = state.buf_prompt,
    callback = function()
      -- Only close if leaving both windows
      local current_win = vim.api.nvim_get_current_win()
      if current_win ~= state.win_main and current_win ~= state.win_prompt then
        M.close()
      end
    end
  })
  -- Start in insert mode in prompt
  vim.cmd("startinsert")
end

-- Open the make runner
function M.open()
  -- Clean up any existing state first (in case output modal is still open)
  if state.win_output and vim.api.nvim_win_is_valid(state.win_output) then
    vim.api.nvim_win_close(state.win_output, true)
    state.win_output = nil
  end
  if state.win_backdrop and vim.api.nvim_win_is_valid(state.win_backdrop) then
    vim.api.nvim_win_close(state.win_backdrop, true)
    state.win_backdrop = nil
  end
  local makefile = find_makefile()
  if not makefile then
    print("No Makefile found")
    return
  end
  -- Store the directory containing the Makefile for make -C
  state.makefile_dir = vim.fn.fnamemodify(makefile, ":h")
  -- Security: Paranoid validation of the directory path
  if not is_valid_path(state.makefile_dir) then
    print("Invalid Makefile directory path")
    return
  end
  state.targets = parse_makefile(makefile)
  if #state.targets == 0 then
    print("No targets found in Makefile")
    return
  end
  state.history = load_history()
  state.search_query = ""
  state.selected_idx = 1
  filter_targets()
  create_ui()
  render()
end

-- Close the UI
function M.close()
  if state.win_main and vim.api.nvim_win_is_valid(state.win_main) then
    vim.api.nvim_win_close(state.win_main, true)
  end
  if state.win_prompt and vim.api.nvim_win_is_valid(state.win_prompt) then
    vim.api.nvim_win_close(state.win_prompt, true)
  end
  if state.win_backdrop and vim.api.nvim_win_is_valid(state.win_backdrop) then
    vim.api.nvim_win_close(state.win_backdrop, true)
  end
  state.win_main = nil
  state.win_prompt = nil
  state.win_backdrop = nil
end

-- Setup
function M.setup() vim.keymap.set('n', 'm', M.open, { desc = 'Open make target runner' }) end

return M
