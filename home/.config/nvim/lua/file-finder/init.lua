local M = {}

-- local files = require("file-finder.files")
local ui = require("file-finder.ui")

local PLUGIN_NAME = 'file-finder'
local PLUGIN_LAST_FILES_OPEN_FILE_NAME = 'last_files_open.txt'
local MAX_SAVED_FILES = 80


-- TODO save the previous status per current dir, also save a timestamp for each last opening per dir
-- TODO when executing the algo, merge with saved openings of subdir, smart algo to merge depending on time
-- TODO   - can ignore subdir from the list of checks when it is too old, changes date on each pick
-- TODO when all exhausted, also search for all files in the current dir, ignoring special dirs, like the O version?
-- TODO   - by default: node_module(s?), .venv ... => Should be common with O?
-- TODO should merge the o and O version

-- TODO ADAPT
-- local home_path = os.getenv('HOME') or os.getenv('USERPROFILE') -- Unix or Windows
-- local data_path = vim.fn.stdpath('data') .. '/' .. PLUGIN_NAME .. '/' -- ~/.local/share/nvim/file-finder/ probably
-- local function find_index(table, value)
--     for i, v in ipairs(table) do if v == value then return i end end return nil
-- end
-- 
-- local function update_file_list(search_term)
--     if not popup_buf_id or not vim.api.nvim_buf_is_valid(popup_buf_id) then
--         return
--     end
--     local unfiltered_files = get_opened_files_in_table()
--     local old_files = {}
--     local old_files_lines = {}
-- 
--     for _, v in ipairs(unfiltered_files) do
--         local i = #old_files+1
--         if string.sub(v, 1, #home_path) == home_path then v = '~' .. string.sub(v, #home_path+1, -1) end
--         if search_term == "" or v:lower():find(search_term:lower(), 1, true) then
--             old_files[i] = v
--             old_files_lines[i] = string.format(' %2d ', i-1) .. v .. string.format(' %d ', i-1)
--         end
--     end
-- 
--     vim.api.nvim_buf_set_option(popup_buf_id, 'modifiable', true)
--     vim.api.nvim_buf_set_lines(popup_buf_id, 0, -1, false, old_files_lines)
--     local ns_id = vim.api.nvim_create_namespace('buf-color-namespace')
--     vim.api.nvim_buf_clear_namespace(popup_buf_id, ns_id, 0, -1)
--     for i = 0, #old_files_lines - 1 do
--         local color = (i % 3 == 0) and 'Statement' or ((i % 3 == 1) and 'String' or 'Title')
--         color = (i < 10) and color or 'Comment'
--         local reversed_slash_index = old_files_lines[i + 1]:reverse():find("/")
--         local last_slash_index = reversed_slash_index and (#old_files_lines[i + 1] - reversed_slash_index + 1) or 1000
--         vim.api.nvim_buf_add_highlight(popup_buf_id, ns_id, color, i, 0, last_slash_index)
--         vim.api.nvim_buf_add_highlight(popup_buf_id, ns_id, color, i, #old_files_lines[i+1]-3, #old_files_lines[i+1])
--     end
--     vim.api.nvim_buf_set_option(popup_buf_id, 'modifiable', false)
-- 
--     M.filtered_files = old_files
-- end
-- 
-- local function add_hook(buf_id, key)
--     vim.api.nvim_buf_set_keymap(buf_id, 'n', key,
--         ':lua require("' .. PLUGIN_NAME .. '").key_pressed("' .. string.gsub(key, "<", "!") .. '")<CR>',
--         {noremap = true, silent = true})
-- end
-- 
-- local function number_pressed(key)
--     if M.filtered_files and M.filtered_files[tonumber(key) + 1] then
--         local file_path = M.filtered_files[tonumber(key) + 1]
--         close_popup()
--         mark_open_from_name(file_path)
--         vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
--     else close_popup() end
-- end
-- 
-- function M.key_pressed(key)
--     if string.find('0123456789', key, 1, true) ~= nil then number_pressed(key)
--     elseif key == '!CR>' then number_pressed(0)
--     elseif key == '!Esc>' then close_popup()
--     elseif key == '!BS>' then remove_char_from_search()
--     elseif key == '!Space>' then add_char_to_search(' ')
--     else add_char_to_search(key) end
-- end

-- TODO when using O, selection should be searched for

function M.setup()
  -- TODO
  -- ensure_dir(data_path)
  -- ensure_file(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME)
  -- vim.api.nvim_set_keymap(
  --     'n', 'o', ':lua require("' .. PLUGIN_NAME .. '").show_popup()<CR>',  {noremap = true, silent = true}
  -- )
  -- vim.api.nvim_create_autocmd("BufEnter", {pattern = "*", callback = mark_open_from_table_of_infos})
  -- TODO o for previous plugin
  vim.keymap.set("n", "o",     ui.start_history_only, {desc = "Find files (history only)", silent = true})
  vim.keymap.set("n", "O",     ui.start             , {desc = "Find files", silent = true})
  vim.keymap.set("x", "<C-o>", ui.start             , {desc = "Find files", silent = true})
  -- TODO C-o in the plugin should switch between 2 modes (o and O)
  -- TODO command to start the reimplem of the regular file manager
  vim.api.nvim_create_user_command("FfFiles", ui.show_windows, {desc = "Find files with scoring"})
end

M.start = ui.start

return M
