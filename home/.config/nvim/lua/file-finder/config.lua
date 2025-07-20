local M = {}

M.PLUGIN_NAME = "file-finder"
M.PLUGIN_LAST_FILES_OPEN_FILE_NAME = "last_files_open.txt"
M.MAX_SAVED_FILES = 9000

-- not really config past this line but state, should probably refactor

M.data_path = vim.fn.stdpath("data") .. "/file-finder"
M.data_file = vim.fn.stdpath("data") .. "/file-finder/history"
M.opened_file = vim.fn.expand("%:p")
M.current_directory = vim.uv.cwd()

return M
