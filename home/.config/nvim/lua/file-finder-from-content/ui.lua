local M = {}

-- TODO ctrl-o to switch with regular mode (merge it), ijkl to move with next versions

local api = vim.api
local fn = vim.fn

M.buf = nil
M.win = nil
M.prompt_buf = nil
M.prompt_win = nil

function M.create_floating_window(opts)
  opts = opts or {}
  
  local width  = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines   - height) / 2)
  local col = math.floor((vim.o.columns - width ) / 2)
  
  local buf = api.nvim_create_buf(false, true)
  local win_opts = {
    relative = "editor", width = width, height = height, row = row, col = col, style = "minimal", border = "rounded"
  }
  local win = api.nvim_open_win(buf, true, win_opts)
  api.nvim_win_set_option(win, "wrap", false)
  api.nvim_win_set_option(win, "cursorline", true)
  return buf, win
end

function M.create_prompt_window(main_win)
  local main_config = api.nvim_win_get_config(main_win)
  local width = main_config.width
  local row_val = main_config.row
  if type(row_val) == "table" then row_val = row_val[1] or 0 end
  local row = row_val - 1
  local col_val = main_config.col
  if type(col_val) == "table" then col_val = col_val[1] or 0 end
  local col = col_val
  local prompt_buf = api.nvim_create_buf(false, true)
  local prompt_opts = {
    relative = "editor", width = width, height = 1, row = row, col = col, style = "minimal", border = "rounded"
  }
  local prompt_win = api.nvim_open_win(prompt_buf, true, prompt_opts)
  api.nvim_buf_set_option(prompt_buf, "buftype", "prompt")
  api.nvim_buf_set_option(prompt_buf, "swapfile", false)
  fn.prompt_setprompt(prompt_buf, "> ")
  return prompt_buf, prompt_win
end

function M.setup_highlights()
  api.nvim_set_hl(0, "FuzzyFinderMatch",    { fg = "#ffff00", bold = true })
  api.nvim_set_hl(0, "FuzzyFinderSelected", { bg = "#444444" })
end

function M.highlight_line(buf, line_num, pattern, text)
  local scoring = require("file-finder-from-content.scoring")
  local matches = {}  -- TODO get it from args actually
  api.nvim_buf_clear_namespace(buf, -1, line_num, line_num + 1)
  for _, col in ipairs(matches) do api.nvim_buf_add_highlight(buf, -1, "FuzzyFinderMatch", line_num, col, col + 1) end
end

function M.update_results(buf, items, pattern, selected_line)
  api.nvim_buf_set_option(buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, items)
  api.nvim_buf_set_option(buf, "modifiable", false)
  
  api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  
  for i, item in ipairs(items) do
    local line_num = i - 1
    M.highlight_line(buf, line_num, pattern, item)
    if line_num == selected_line then api.nvim_buf_add_highlight(buf, -1, "FuzzyFinderSelected", line_num, 0, -1) end
  end
end

function M.close()
  if M.prompt_win and api.nvim_win_is_valid(M.prompt_win) then api.nvim_win_close(M.prompt_win, true)              end
  if M.win        and api.nvim_win_is_valid(M.win)        then api.nvim_win_close(M.win, true)                     end
  if M.prompt_buf and api.nvim_buf_is_valid(M.prompt_buf) then api.nvim_buf_delete(M.prompt_buf, { force = true }) end
  if M.buf        and api.nvim_buf_is_valid(M.buf)        then api.nvim_buf_delete(M.buf, { force = true })        end
  M.buf = nil; M.win = nil; M.prompt_buf = nil; M.prompt_win = nil
end

return M
