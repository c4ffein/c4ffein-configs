local M = {}

local files = require("file-finder-from-content.files")


-- TODO when using O, selection should be searched for

function M.setup()
  vim.keymap.set("n", "O", files.find_files, {desc = "Find files", silent = true})
  vim.api.nvim_create_user_command("FfFiles", files.find_files, {desc = "Find files with scoring"})
end

M.find_files = files.find_files

return M
