local M = {}

local files = require("file-finder-from-content.files")


-- TODO when using O, selection should be searched for

function M.setup()
  -- TODO o for previous plugin
  vim.keymap.set("n", "O",     files.find_files, {desc = "Find files", silent = true})
  vim.keymap.set("n", "<C-o>", files.find_files, {desc = "Find files", silent = true})
  vim.keymap.set("x", "<C-o>", files.find_files, {desc = "Find files", silent = true})
  -- TODO C-o in the plugin should switch between 2 modes (o and O)
  -- TODO command to start the reimplem of the regular file manager
  vim.api.nvim_create_user_command("FfFiles", files.find_files, {desc = "Find files with scoring"})
end

M.find_files = files.find_files

return M
