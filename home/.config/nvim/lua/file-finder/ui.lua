local M = {}

local config = require("file-finder.config")
local files = require("file-finder.files")
local history = require("file-finder.history")
local scoring = require("file-finder.scoring")
local ceil = math.ceil

local api = vim.api
local fn = vim.fn

M.history_only_mode = false
M.lines_per_file = config.shown_lines_per_file  -- Number of matched lines to show per file (adjustable with +/-)
M.main_buf,     M.prompt_buf,         M.backdrop_buf         = nil, nil, nil
M.main_win,     M.prompt_win,         M.backdrop_win         = nil, nil, nil
M.main_height,  M.prompt_win_height,  M.backdrop_win_height  =  20,  20,  20
M.main_width,   M.prompt_win_width,   M.backdrop_win_width   =  20,  20,  20
M.main_row,     M.prompt_row,         M.backdrop_row         =   0,   0,   0
M.main_col,     M.prompt_col,         M.backdrop_col         =   0,   0,   0
M.main_blend,   M.prompt_blend,       M.backdrop_blend       =   0,   0,   0
M.lines_infos = {}

function M.set_windows_characterisitcs()
  if M.history_only_mode then
    M.main_width, M.main_height     = 100, 22
    M.main_row,   M.main_col        = ceil((vim.o.lines - M.main_height)) / 2, ceil((vim.o.columns - M.main_width) / 2)
    M.main_blend, M.prompt_blend, M.backdrop_blend = 5, 5, 100
  else
    M.main_width, M.main_height     = vim.o.columns - 22, vim.o.lines - 9
    M.main_row,   M.main_col        = 6, 10
    M.main_blend, M.prompt_blend, M.backdrop_blend  = 0, 0, 15
  end
  M.prompt_width,   M.prompt_height   = M.main_width, 1
  M.prompt_row,     M.prompt_col      = M.main_row - 4, M.main_col
  M.backdrop_width, M.backdrop_height = vim.o.columns, vim.o.lines
end

local function make_win_opts(height, width, row, col, additional_opts)
  local returned_table = {
    relative = "editor", height = height, width = width, row = row, col = col, style = "minimal"
  }
  for k, v in pairs(additional_opts) do returned_table[k] = v end
  return returned_table
end

function M.create_backdrop_window()
  local backdrop_buf = api.nvim_create_buf(false, true)
  local height, width, row, col = M.backdrop_height, M.backdrop_width, M.backdrop_row, M.backdrop_col
  local win_opts = make_win_opts(height, width, row, col, { focusable = false, zindex = 1 })
  local win = api.nvim_open_win(backdrop_buf, false, win_opts)
  api.nvim_win_set_option(win, "winblend", M.backdrop_blend)
  return backdrop_buf, win
end

function M.create_floating_window()
  local buf = api.nvim_create_buf(false, true)
  local height, width, row, col = M.main_height, M.main_width, M.main_row, M.main_col
  local win_opts = make_win_opts(height, width, row, col, { zindex = 2, border = "single" })
  local win = api.nvim_open_win(buf, true, win_opts)
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "cursorline", true)
  api.nvim_win_set_option(win, "winblend", M.main_blend)
  return buf, win
end

function M.create_prompt_window()
  local prompt_buf = api.nvim_create_buf(false, true)
  local height, width, row, col = M.prompt_height, M.prompt_width, M.prompt_row, M.prompt_col
  local win_opts = make_win_opts(height, width, row, col, { border = "single" })
  local prompt_win = api.nvim_open_win(prompt_buf, true, win_opts)
  api.nvim_buf_set_option(prompt_buf, "buftype", "prompt")
  api.nvim_buf_set_option(prompt_buf, "swapfile", false)
  fn.prompt_setprompt(prompt_buf, "> ")
  return prompt_buf, prompt_win
end

function M.reset_windows()
  local function reset(win, height, width, row, col, blend)
    api.nvim_win_set_config(win, { relative = "editor", height = height, width = width, row = row, col = col })
    api.nvim_win_set_option(win, "winblend", blend)
  end
  reset(M.backdrop_win, M.backdrop_height, M.backdrop_width, M.backdrop_row, M.backdrop_col, M.backdrop_blend)
  reset(M.main_win,     M.main_height,     M.main_width,     M.main_row,     M.main_col,     M.main_blend    )
  reset(M.prompt_win,   M.prompt_height,   M.prompt_width,   M.prompt_row,   M.prompt_col,   M.prompt_blend  )
end

function M.setup_highlights()
  api.nvim_set_hl(0, "FileFinderPathCd",     { fg = "#BB88FF" })
  api.nvim_set_hl(0, "FileFinderPathHome",   { fg = "#FF6E6E" })
  api.nvim_set_hl(0, "FileFinderPathRoot",   { fg = "#88EEFF" })
  api.nvim_set_hl(0, "FileFinderLineNumber", { fg = "#777777" })
  api.nvim_set_hl(0, "FileFinderLineMatch",  { fg = "#FF92DF" })
end

function M.update_results(buf, items, selected_line)
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, items)
  api.nvim_buf_set_option(buf, "modifiable", false)
  
  api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  
  for i, item in ipairs(items) do
    for _, color in ipairs(M.lines_infos[i].colors) do
      api.nvim_buf_add_highlight(buf, -1, color[1], i - 1, color[2], color[3])
    end
  end
end

function M.show_windows()
  if M.prompt_win or M.main_win or M.backdrop_win or M.prompt_buf or M.main_buf or M.backdrop_buf then
    M.close_windows()
  end
  M.set_windows_characterisitcs()
  M.backdrop_buf, M.backdrop_win = M.create_backdrop_window()
  M.main_buf,     M.main_win     = M.create_floating_window()
  M.prompt_buf,   M.prompt_win   = M.create_prompt_window()
end

function M.close_windows()
  local forced = { force = true }
  if M.prompt_win   and api.nvim_win_is_valid(M.prompt_win)   then api.nvim_win_close( M.prompt_win,   true)   end
  if M.main_win     and api.nvim_win_is_valid(M.main_win)     then api.nvim_win_close( M.main_win,     true)   end
  if M.backdrop_win and api.nvim_win_is_valid(M.backdrop_win) then api.nvim_win_close( M.backdrop_win, true)   end
  if M.prompt_buf   and api.nvim_buf_is_valid(M.prompt_buf)   then api.nvim_buf_delete(M.prompt_buf,   forced) end
  if M.main_buf     and api.nvim_buf_is_valid(M.main_buf)     then api.nvim_buf_delete(M.main_buf,     forced) end
  if M.backdrop_buf and api.nvim_buf_is_valid(M.backdrop_buf) then api.nvim_buf_delete(M.backdrop_buf, forced) end
  M.main_buf = nil; M.main_win = nil; M.prompt_buf = nil; M.prompt_win = nil; M.backdrop_buf = nil; M.backdrop_win = nil
end

local function get_visual_selection()
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then return "" end  -- Only works if currently selected
  local start_ds, end_ds = vim.fn.getpos("v"), vim.fn.getpos(".")
  -- if there is no current selection, could try previous selection with vim.fn.getpos("'<") and vim.fn.getpos("'>")
  local start_bufnum, start_lnum, start_col, start_off = start_ds[1], start_ds[2], start_ds[3], start_ds[4]
  local   end_bufnum,   end_lnum,   end_col,   end_off =   end_ds[1],   end_ds[2],   end_ds[3],   end_ds[4]
  if start_lnum == 0 or end_lnum == 0 then return "" end  -- Invalid selection (returns { 0, 0, 0, 0 })
  if start_bufnum ~= end_bufnum or start_lnum ~= end_lnum then return "" end  -- Could show a warning, simpler now
  local lines = vim.fn.getregion(start_ds, end_ds)
  if #lines == 0 then return "" end
  return lines[1]
end

local function add_short_paths(items)
  for _, item in ipairs(items) do
    local abs_path = item.file
    local rel_path = abs_path
    if abs_path:sub(1, #config.current_directory) == config.current_directory then
      rel_path = abs_path:sub(#config.current_directory + 1)
    elseif abs_path:sub(1, #files.HOME) == files.HOME then
      rel_path = abs_path:sub(#files.HOME + 1)
    else
      rel_path = abs_path:sub(2)
    end
    item.short_path = rel_path
  end
  return items
end

local function enrich_display_info(items, count)
  for i = 1, math.min(#items, count or 50) do
    local item = items[i]
    local path_starter, selected_color = "/", "FileFinderPathRoot"
    if item.file:sub(1, #config.current_directory) == config.current_directory then
      path_starter, selected_color = ".", "FileFinderPathCd"
    elseif item.file:sub(1, #files.HOME) == files.HOME then
      path_starter, selected_color = "~", "FileFinderPathHome"
    end
    item.printable = {
      full_path = item.file,
      path_starter = path_starter,
      short_path = item.printed_path,
      selected_color = selected_color
    }
  end
  return items
end

local function update_display(filtered_files)
  if M.history_only_mode then
    enrich_display_info(filtered_files, 50)
  end
  local display_items = {}
  M.lines_infos = {}
  for i = 1, math.min(#filtered_files, 50) do
    local item = filtered_files[i]
    if type(item) ~= "table" then vim.notify("update_display consumed a non table", vim.log.levels.ERROR); return end

    if not M.history_only_mode then
      -- Show filename (without "..." - that comes after matched lines)
      table.insert(display_items, item.file)
      table.insert(M.lines_infos, { file = item.file, colors = { { "FileFinderPathCd", 0, 9000 } } })
    else
      local path_starter, short_path, selected_color = item.printable.path_starter, item.printable.short_path, item.printable.selected_color
      local line_number_as_str = tostring(i - 1)
      if i <  11 then line_number_as_str = " " .. line_number_as_str end
      if i < 101 then line_number_as_str = " " .. line_number_as_str end
      if i > 10 then selected_color = "FileFinderLineNumber" end
      local reversed_slash_pos = short_path:reverse():find("/")
      local slash_pos = reversed_slash_pos and #short_path - reversed_slash_pos + 1 or 0 -- 0 if not found
      table.insert(
        display_items, line_number_as_str .. " " .. path_starter .. " " .. short_path .. " " .. tostring(i - 1)
      )
      local colors = { { selected_color, 0, slash_pos + 6 }, { selected_color, #short_path + 6, 9000 } }
      table.insert(M.lines_infos, { file = item.file, colors = colors })
    end
    if item.matched_lines and #item.matched_lines > 0 and not M.history_only_mode then
      -- Show only up to lines_per_file matched lines
      local lines_to_show = math.min(#item.matched_lines, M.lines_per_file)
      for j = 1, lines_to_show do
        local match = item.matched_lines[j]
        local line_number = string.rep(' ', math.max(0, 5 - #tostring(match.line_num))) .. match.line_num
        local content = match.content:gsub("^%s+", "")
        local color_offset = #content - #match.content + #line_number
        table.insert(display_items, line_number .. ' ' .. content)
        table.insert(M.lines_infos, {
          file = item.file,
          colors = { { "FileFinderLineNumber", 0,                              #line_number                     },
                     { "FileFinderLineMatch",  color_offset + match.start_pos, color_offset + match.end_pos + 1 } },
          line_number = match.line_num
        } )
      end
      if #item.matched_lines > M.lines_per_file then
        table.insert(display_items, "      ...")
        table.insert(M.lines_infos, { file = item.file, colors = { { "FileFinderLineNumber", 0, 9000 } } })
      end
    end
  end
  M.update_results(M.main_buf, display_items, selected_line, M.lines_infos)
end

function M.start(history_only_mode)
  M.history_only_mode = history_only_mode
  local visual_selection = get_visual_selection()  -- get this value before UI setup

  local all_files_from_tree = files.get_files()
  local all_files_from_history = add_short_paths(history.load_history_for_ui())
  for _, item in ipairs(all_files_from_tree) do item.printed_path = item.file end
  for _, item in ipairs(all_files_from_history) do item.printed_path = item.short_path end
  local obtained_files, filtered_files, selected_line, pattern, skip_regex = {}, {}, 1, "", false

  -- Build history rank map: file_path -> rank (lower = more recent)
  -- Convert absolute paths from history to relative paths to match file tree
  local history_rank = {}
  for i, item in ipairs(all_files_from_history) do
    local abs_path = item.file
    local rel_path = abs_path
    -- Convert absolute to relative if it starts with current directory
    if abs_path:sub(1, #config.current_directory) == config.current_directory then
      rel_path = abs_path:sub(#config.current_directory + 1)
    end
    history_rank[rel_path] = i
  end

  M.setup_highlights()
  M.show_windows()

  local function set_obtained_files()
    obtained_files = M.history_only_mode and all_files_from_history or all_files_from_tree
  end

  set_obtained_files()
  filtered_files = obtained_files

  local function on_input_change(force)
    local lines = vim.api.nvim_buf_get_lines(M.prompt_buf, 0, -1, false)
    local new_pattern = lines[1] and lines[1]:gsub("^> ", "") or ""
    if new_pattern ~= pattern or force then
      pattern = new_pattern
      filtered_files, skip_regex = scoring.filter(pattern, obtained_files, nil, M.history_only_mode, history_rank)
      selected_line = 1
      update_display(filtered_files)
      local ns_id = vim.api.nvim_create_namespace("file_finder_prompt_color")
      vim.api.nvim_buf_clear_namespace(M.prompt_buf, ns_id, 0, -1)
      if skip_regex then
        vim.api.nvim_buf_set_extmark(M.prompt_buf, ns_id, 0, 0, {
          virt_text = {{">", "FileFinderLineMatch"}},
          virt_text_pos = "overlay"
        })
      end
    end
  end

  local function select_file()
    local line_infos = M.lines_infos[selected_line]
    if not line_infos then return end
    M.close_windows()
    files.open_file(line_infos.file, line_infos.line_number)
  end

  local function setup_number_keys()
    for i = 0, 9 do
      local local_i = i
      local key = tostring(i)
      if M.history_only_mode then
        local key_callback = function() selected_line = local_i + 1; select_file() end
        local sk = vim.api.nvim_buf_set_keymap
        sk(M.prompt_buf, "i", key, "", { callback = key_callback, noremap = true, silent = true })
        sk(M.main_buf,   "i", key, "", { callback = key_callback, noremap = true, silent = true })
      else
        pcall(vim.api.nvim_buf_del_keymap, M.prompt_buf, "i", key)
        pcall(vim.api.nvim_buf_del_keymap, M.main_buf, "i", key)
      end
    end
  end

  local function switch_mode()
    M.history_only_mode = not M.history_only_mode
    setup_number_keys()
    M.set_windows_characterisitcs()
    M.reset_windows()
    set_obtained_files()
    M.set_windows_characterisitcs()
    on_input_change(true)
  end

  local function move_selection(direction)
    local display_line_count = 0
    for _, _ in pairs(M.lines_infos) do display_line_count = display_line_count + 1 end
    local max_line = math.min(math.min(display_line_count - 1, 49), #M.lines_infos)
    selected_line = math.max(1, math.min(max_line + 1, selected_line + direction))
    update_display(filtered_files)
    vim.api.nvim_win_set_cursor(M.main_win, {selected_line, 0})
  end

  vim.api.nvim_buf_attach(M.prompt_buf, false, { on_lines = function() vim.schedule(on_input_change) end })
  local sk = vim.api.nvim_buf_set_keymap
  sk(M.prompt_buf, "i", "<CR>",  "", { callback = select_file,                       noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<C-o>", "", { callback = switch_mode,                       noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<C-k>", "", { callback = function() move_selection(1) end,  noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<C-^>", "", { callback = function() move_selection(-1) end, noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<Esc>", "", { callback = M.close_windows,                   noremap = true, silent = true })
  sk(M.main_buf,   "n", "<CR>",  "", { callback = select_file,                       noremap = true, silent = true })
  sk(M.main_buf,   "n", "<C-o>", "", { callback = switch_mode,                       noremap = true, silent = true })
  sk(M.main_buf,   "n", "q",     "", { callback = M.close_windows,                   noremap = true, silent = true })
  sk(M.main_buf,   "n", "<Esc>", "", { callback = M.close_windows,                   noremap = true, silent = true })
  setup_number_keys()
  -- Functions to adjust lines per file
  local function increase_lines_per_file()
    M.lines_per_file = math.min(M.lines_per_file + 1, config.MAX_LINES_PER_FILE)
    update_display(filtered_files)
  end

  local function decrease_lines_per_file()
    M.lines_per_file = math.max(M.lines_per_file - 1, 1)  -- Min 1 line per file
    update_display(filtered_files)
  end

  -- Add keybindings for ≠ (Ctrl+=) and – (Ctrl+-) to adjust lines per file
  -- Configure in Alacritty: Ctrl+= sends ≠, Ctrl+- sends –
  sk(M.prompt_buf, "i", "≠", "", { callback = increase_lines_per_file, noremap = true, silent = true })
  sk(M.prompt_buf, "i", "–", "", { callback = decrease_lines_per_file, noremap = true, silent = true })
  sk(M.main_buf,   "n", "≠", "", { callback = increase_lines_per_file, noremap = true, silent = true })
  sk(M.main_buf,   "n", "–", "", { callback = decrease_lines_per_file, noremap = true, silent = true })

  update_display(filtered_files)
  vim.api.nvim_buf_set_lines(M.prompt_buf, 0, 1, false, { "> " .. visual_selection })  -- triggers recomputation
  vim.cmd("startinsert")
  vim.cmd('normal! $')
end

function M.start_history_only() M.start(true) end

return M
