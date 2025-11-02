local M = {}

local ui = require("file-explorer.ui")

function M.setup()
  -- Keybinding: Ctrl+o to open file explorer
  vim.keymap.set("n", "<C-o>", ui.open, {desc = "Open file explorer", silent = true})
end

M.open = ui.open

return M
