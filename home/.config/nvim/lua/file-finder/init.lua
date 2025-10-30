local M = {}

local config = require("file-finder.config")
local ui = require("file-finder.ui")
local history = require("file-finder.history")

-- TODO when you add a file outside cd through the file explorer, it is still added to the current history
-- TODO you can set cd from the file explorer
-- DONE: + and - to get more and less lines per file (adjustable with M.lines_per_file, bound to +/- keys)

function M.setup()
  vim.keymap.set("n", "o",     ui.start_history_only, {desc = "Find files (history only)", silent = true})
  vim.keymap.set("n", "O",     ui.start             , {desc = "Find files", silent = true})
  vim.keymap.set("x", "<C-o>", ui.start             , {desc = "Find files", silent = true})
  vim.api.nvim_create_user_command("FfFiles", ui.show_windows, {desc = "Find files with scoring"})
end

M.start = ui.start

vim.api.nvim_create_autocmd({"VimEnter", "BufReadPost", "BufEnter"}, { -- BufEnter sometimes needed when switching
  callback = function()
    opened_file = vim.fn.expand("%:p")
    if opened_file == "" then return end
    vim.fn.mkdir(config.data_path, "p")
    history.append_to_history(config.data_file, opened_file, config.current_directory, config.MAX_SAVED_FILES)
  end
})

return M
