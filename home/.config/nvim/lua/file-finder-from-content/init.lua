local M = {}

local files = require("file-finder-from-content.files")

function M.setup()
  vim.keymap.set("n", "O", files.find_files, {desc = "Find files", silent = true})
  vim.api.nvim_create_user_command("FfFiles", files.find_files, {desc = "Find files with fuzzy finder"})
end

M.find_files = files.find_files

return M
