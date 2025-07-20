local M = {}

local files = require("file-finder.files")
local history = require("file-finder.history")
local scoring = require("file-finder.scoring")
local ceil = math.ceil

-- TODO ctrl-o to switch with regular mode (merge it), ijkl to move with next versions
-- TODO would be nice if equivalent scores would get ranked by history
local api = vim.api
local fn = vim.fn

M.history_only_mode = false
M.main_buf,     M.prompt_buf,         M.backdrop_buf         = nil, nil, nil
M.main_win,     M.prompt_win,         M.backdrop_win         = nil, nil, nil
M.main_height,  M.prompt_win_height,  M.backdrop_win_height  =  20,  20,  20
M.main_width,   M.prompt_win_width,   M.backdrop_win_width   =  20,  20,  20
M.main_row,     M.prompt_row,         M.backdrop_row         =   0,   0,   0
M.main_col,     M.prompt_col,         M.backdrop_col         =   0,   0,   0
M.main_blend,   M.prompt_blend,       M.backdrop_blend       = 100, 100, 100
M.lines_infos = {}

function M.set_windows_characterisitcs(history_only_mode)
  M.history_only_mode = history_only_mode
  if history_only_mode then
    M.main_width, M.main_height     = 100, 22
    M.main_row,   M.main_col        = ceil((vim.o.lines - M.main_height)) / 2, ceil((vim.o.columns - M.main_width) / 2)
    M.main_blend, M.backdrop_blend  = 5, 100
  else
    M.main_width, M.main_height     = vim.o.columns - 22, vim.o.lines - 9
    M.main_row,   M.main_col        = 6, 10
    M.main_blend, M.backdrop_blend  = 0, 15
  end
  M.prompt_width,   M.prompt_height   = M.main_width, 1
  M.prompt_row,     M.prompt_col      = M.main_row - 4, M.main_col
  M.backdrop_width, M.backdrop_height = vim.o.columns, vim.o.lines
end

function M.create_backdrop_window()
  local backdrop_buf = api.nvim_create_buf(false, true)
  local backdrop_opts = {
    relative = "editor", width = M.backdrop_width, height = M.backdrop_height, row = M.backdrop_row, col = M.backdrop_col,
    style = "minimal", focusable = false, zindex = 1,
  }
  local backdrop_win = api.nvim_open_win(backdrop_buf, false, backdrop_opts)
  api.nvim_win_set_option(backdrop_win, "winblend", M.backdrop_blend)
  return backdrop_buf, backdrop_win
end

function M.create_floating_window()
  local buf = api.nvim_create_buf(false, true)
  local win_opts = {
    relative = "editor", width = M.main_width, height = M.main_height, row = M.main_row, col = M.main_col, zindex = 2,
    style = "minimal", border = "single",
  }
  local win = api.nvim_open_win(buf, true, win_opts)
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "cursorline", true)
  api.nvim_win_set_option(win, "winblend", M.main_blend)
  return buf, win
end

function M.create_prompt_window(main_win, first_pattern)
  local main_config = api.nvim_win_get_config(main_win)
  local width = main_config.width
  local prompt_buf = api.nvim_create_buf(false, true)
  local prompt_opts = {
    relative = "editor", width = width, height = 1, row = M.prompt_row, col = M.prompt_col,
    style = "minimal", border = "single"
  }
  local prompt_win = api.nvim_open_win(prompt_buf, true, prompt_opts)
  api.nvim_buf_set_option(prompt_buf, "buftype", "prompt")
  api.nvim_buf_set_option(prompt_buf, "swapfile", false)
  fn.prompt_setprompt(prompt_buf, "> ")
  return prompt_buf, prompt_win
end

-- TODO ADAPT
--     for _, key in ipairs({'<Space>', '<BS>', '<Esc>', '<CR>'}) do add_hook(search_buf_id, key) end
--     for i = 48,  57 do add_hook(search_buf_id, string.char(i)) end  -- 0 to 9

function M.setup_highlights()
  api.nvim_set_hl(0, "FileFinderPath",       { fg = "#BB88FF" })
  api.nvim_set_hl(0, "FileFinderLineNumber", { fg = "#777777" })
  api.nvim_set_hl(0, "FileFinderLineMatch",  { fg = "#FF92DF" })
  api.nvim_set_hl(0, "FileFinderSelected",   { bg = "#444444" })  -- TODO choose colors
end

function M.update_results(buf, items, selected_line)
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, items)
  api.nvim_buf_set_option(buf, "modifiable", false)
  
  api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  
  for i, item in ipairs(items) do
    -- if i == selected_line then api.nvim_buf_add_highlight(buf, -1, "FileFinderSelected", i, 0, -1) end  -- TODO
    for _, color in ipairs(M.lines_infos[i].colors) do
      api.nvim_buf_add_highlight(buf, -1, color[1], i - 1, color[2], color[3])
    end
  end
end

function M.show_windows(history_only_mode)
  if M.prompt_win or M.win or M.backdrop_win or M.prompt_buf or M.buf or M.backdrop_buf then M.close_windows() end
  M.set_windows_characterisitcs(history_only_mode)
  M.backdrop_buf, M.backdrop_win = M.create_backdrop_window()
  M.buf,          M.win          = M.create_floating_window()
  M.prompt_buf,   M.prompt_win   = M.create_prompt_window(M.win)
end

function M.close_windows()
  local forced = { force = true }
  if M.prompt_win   and api.nvim_win_is_valid(M.prompt_win)   then api.nvim_win_close( M.prompt_win,   true)   end
  if M.win          and api.nvim_win_is_valid(M.win)          then api.nvim_win_close( M.win,          true)   end
  if M.backdrop_win and api.nvim_win_is_valid(M.backdrop_win) then api.nvim_win_close( M.backdrop_win, true)   end
  if M.prompt_buf   and api.nvim_buf_is_valid(M.prompt_buf)   then api.nvim_buf_delete(M.prompt_buf,   forced) end
  if M.buf          and api.nvim_buf_is_valid(M.buf)          then api.nvim_buf_delete(M.buf,          forced) end
  if M.backdrop_buf and api.nvim_buf_is_valid(M.backdrop_buf) then api.nvim_buf_delete(M.backdrop_buf, forced) end
  M.buf = nil; M.win = nil; M.prompt_buf = nil; M.prompt_win = nil; M.backdrop_buf = nil; M.backdrop_win = nil
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

local function update_display(filtered_files)
  local display_items = {}
  M.lines_infos = {}
  for i = 1, math.min(#filtered_files, 50) do
    local item = filtered_files[i]
    if type(item) == "table" then
      -- TODO : ... after file name if more exemples?
      table.insert(display_items, item.file)
      table.insert(M.lines_infos, { file = item.file, colors = { { "FileFinderPath", 0, 9000 } } })
      if item.matched_lines and #item.matched_lines > 0 and not M.history_only_mode then
        for j, match in ipairs(item.matched_lines) do
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
      end
    else  -- TODO refactor the first file list so this case is useless
      table.insert(display_items, item)
      table.insert(M.lines_infos, { file = item, colors = {} })
    end
  end
  M.update_results(M.buf, display_items, selected_line, M.lines_infos)
end

function M.start(history_only_mode)
  local visual_selection = get_visual_selection()  -- get this value before UI setup

  local obtained_files = files.get_files()
  if #obtained_files == 0 then vim.notify("No files found", vim.log.levels.WARN) return end  -- TODO custom
  local file_history = history.load_history_for_ui()

  M.setup_highlights()
  M.show_windows(history_only_mode)

  local filtered_files = obtained_files
  local selected_line = 1
  local pattern = ""

  local function on_input_change()
    local lines = vim.api.nvim_buf_get_lines(M.prompt_buf, 0, -1, false)
    local new_pattern = lines[1] and lines[1]:gsub("^> ", "") or ""
    
    if new_pattern ~= pattern then
      pattern = new_pattern
      filtered_files = scoring.filter(pattern, obtained_files)
      selected_line = 1
      update_display(filtered_files)
    end
  end
  
  local function select_file()
    local line_infos = M.lines_infos[selected_line]
    M.close_windows()
    if not line_infos.line_number then vim.cmd("edit ".. vim.fn.fnameescape(line_infos.file))
    else vim.cmd("edit +" .. line_infos.line_number .. " " .. vim.fn.fnameescape(line_infos.file)) end
  end
  
  local function move_selection(direction)
    local display_line_count = 0
    for _, _ in pairs(M.lines_infos) do display_line_count = display_line_count + 1 end
    local max_line = math.min(math.min(display_line_count - 1, 49), #M.lines_infos)
    selected_line = math.max(1, math.min(max_line + 1, selected_line + direction))
    update_display(filtered_files)
    vim.api.nvim_win_set_cursor(M.win, {selected_line, 0})
  end

  vim.api.nvim_buf_attach(M.prompt_buf, false, { on_lines = function() vim.schedule(on_input_change) end })
 
  local sk = vim.api.nvim_buf_set_keymap
  sk(M.prompt_buf, "i", "<CR>",  "", { callback = select_file,                       noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<C-k>", "", { callback = function() move_selection(1) end,  noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<C-^>", "", { callback = function() move_selection(-1) end, noremap = true, silent = true })
  sk(M.prompt_buf, "i", "<Esc>", "", { callback = M.close_windows,                   noremap = true, silent = true })
  sk(M.buf,        "n", "<CR>",  "", { callback = select_file,                       noremap = true, silent = true })
  sk(M.buf,        "n", "q",     "", { callback = M.close_windows,                   noremap = true, silent = true })
  sk(M.buf,        "n", "<Esc>", "", { callback = M.close_windows,                   noremap = true, silent = true })
  if pattern and #pattern > 0 then filtered_files = scoring.filter(pattern, files) end
  update_display(filtered_files)
  vim.api.nvim_buf_set_lines(M.prompt_buf, 0, 1, false, { "> " .. visual_selection })  -- triggers recomputation
  vim.cmd("startinsert")
  vim.cmd('normal! $')
end

function M.start_history_only() M.start(true) end

return M
