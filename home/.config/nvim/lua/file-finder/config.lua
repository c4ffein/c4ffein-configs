local M = {}

M.PLUGIN_NAME = "file-finder"
M.PLUGIN_LAST_FILES_OPEN_FILE_NAME = "last_files_open.txt"
M.MAX_SAVED_FILES = 9000
M.MAX_PRINTABLE_FILES = 9000 -- a filter will be passed on the printable files, so better go as high as possible
M.MAX_LINES_PER_FILE = 60 -- Maximum lines per file that can be shown with + key
M.shown_lines_per_file = 3 -- Default/current number of lines shown per file

-- not really config past this line but state, should probably refactor

M.set_current_directory = function(current_directory)
  M.current_directory = current_directory -- WARNING must always end with a trailing slash
  if M.current_directory:sub(-1) ~= "/" then M.current_directory = M.current_directory .. "/" end
end

M.data_path = vim.fn.stdpath("data") .. "/file-finder"
M.data_file = vim.fn.stdpath("data") .. "/file-finder/history"
M.set_current_directory(vim.uv.cwd())
M.next_file_context_directory = nil

return M
