local M = {}

-- TODO ctrl-o to switch with regular mode (merge it), ijkl to move with next versions

local api = vim.api
local fn = vim.fn

M.buf = nil
M.win = nil
M.prompt_buf = nil
M.prompt_win = nil
M.backdrop_buf = nil
M.backdrop_win = nil

function M.create_backdrop_window()
  local backdrop_buf = api.nvim_create_buf(false, true)
  local backdrop_opts = {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 1
  }
  local backdrop_win = api.nvim_open_win(backdrop_buf, false, backdrop_opts)
  api.nvim_win_set_option(backdrop_win, "winblend", 15)
  return backdrop_buf, backdrop_win
end

function M.create_floating_window()
  M.backdrop_buf, M.backdrop_win = M.create_backdrop_window()
  
  local width  = vim.o.columns - 22
  local height = vim.o.lines - 9
  local row = 6
  local col = 10
  
  local buf = api.nvim_create_buf(false, true)
  local win_opts = {
    relative = "editor", width = width, height = height, row = row, col = col, style = "minimal", border = "single", zindex = 2
  }
  local win = api.nvim_open_win(buf, true, win_opts)
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "cursorline", true)
  return buf, win
end

function M.create_prompt_window(main_win, first_pattern)
  local main_config = api.nvim_win_get_config(main_win)
  local width = main_config.width
  local row = 2
  local col_val = main_config.col
  if type(col_val) == "table" then col_val = col_val[1] or 0 end
  local col = 10
  local prompt_buf = api.nvim_create_buf(false, true)
  local prompt_opts = {
    relative = "editor", width = width, height = 1, row = row, col = col, style = "minimal", border = "single"
  }
  local prompt_win = api.nvim_open_win(prompt_buf, true, prompt_opts)
  api.nvim_buf_set_option(prompt_buf, "buftype", "prompt")
  api.nvim_buf_set_option(prompt_buf, "swapfile", false)
  fn.prompt_setprompt(prompt_buf, "> ")
  return prompt_buf, prompt_win
end

function M.setup_highlights()
  api.nvim_set_hl(0, "FileFinderPath",       { fg = "#BB88FF" })
  api.nvim_set_hl(0, "FileFinderLineNumber", { fg = "#777777" })
  api.nvim_set_hl(0, "FileFinderLineMatch",  { fg = "#FF92DF" })
  api.nvim_set_hl(0, "FileFinderSelected",   { bg = "#444444" })  -- TODO choose colors
end

function M.update_results(buf, items, selected_line, lines_infos)
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, items)
  api.nvim_buf_set_option(buf, "modifiable", false)
  
  api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  
  for i, item in ipairs(items) do
    -- if i == selected_line then api.nvim_buf_add_highlight(buf, -1, "FileFinderSelected", i, 0, -1) end  -- TODO
    for _, color in ipairs(lines_infos[i].colors) do
      api.nvim_buf_add_highlight(buf, -1, color[1], i - 1, color[2], color[3])
    end
  end
end

function M.close()
  local forced = { force = true }
  if M.prompt_win   and api.nvim_win_is_valid(M.prompt_win)   then api.nvim_win_close( M.prompt_win,   true)   end
  if M.win          and api.nvim_win_is_valid(M.win)          then api.nvim_win_close( M.win,          true)   end
  if M.backdrop_win and api.nvim_win_is_valid(M.backdrop_win) then api.nvim_win_close( M.backdrop_win, true)   end
  if M.prompt_buf   and api.nvim_buf_is_valid(M.prompt_buf)   then api.nvim_buf_delete(M.prompt_buf,   forced) end
  if M.buf          and api.nvim_buf_is_valid(M.buf)          then api.nvim_buf_delete(M.buf,          forced) end
  if M.backdrop_buf and api.nvim_buf_is_valid(M.backdrop_buf) then api.nvim_buf_delete(M.backdrop_buf, forced) end
  M.buf = nil; M.win = nil; M.prompt_buf = nil; M.prompt_win = nil; M.backdrop_buf = nil; M.backdrop_win = nil
end

return M
