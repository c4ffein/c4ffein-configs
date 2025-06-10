-- TODO save the previous status per current dir, also save a timestamp for each last opening per dir
-- TODO when executing the algo, merge with saved openings of subdir, smart algo to merge depending on time
-- TODO   - can ignore subdir from the list of checks when it is too old, changes date on each pick
-- TODO when all exhausted, also search for all files in the current dir, ignoring special dirs, like the O version?
-- TODO   - by default: node_module(s?), .venv ... => Should be common with O?
-- TODO should merge the o and O version

local M = {}

local PLUGIN_NAME = 'file-finder'
local PLUGIN_LAST_FILES_OPEN_FILE_NAME = 'last_files_open.txt'
local MAX_SAVED_FILES = 80

local home_path = os.getenv('HOME') or os.getenv('USERPROFILE') -- Unix or Windows
local data_path = vim.fn.stdpath('data') .. '/' .. PLUGIN_NAME .. '/' -- ~/.local/share/nvim/file-finder/ probably

local popup_win_id = nil
local popup_buf_id = nil
local search_win_id = nil
local search_buf_id = nil
local search_text = ''

local function find_index(table, value)
    for i, v in ipairs(table) do if v == value then return i end end return nil
end

local function ensure_dir(path)
    local ok, err = vim.loop.fs_stat(path)
    if not ok then vim.fn.mkdir(path, "p") end
end

local function ensure_file(path)
    local file = io.open(path, 'a')
    if file then file:close() end
end

local function get_opened_files_in_table()
    local lines = {}
    for line in io.lines(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME) do table.insert(lines, line) end
    return lines
end

local function write_opened_files_in_table(lines)
    local output_file = io.open(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME, "w")
    if not output_file then return false end
    output_file:write(table.concat(lines, '\n'))
    output_file:close()
    return true
end

local function mark_open_from_name(current_file_path)
    lines = get_opened_files_in_table()
    index = find_index(lines, current_file_path)
    local new_lines = {current_file_path}
    for i, line in ipairs(lines) do
        if #new_lines > MAX_SAVED_FILES then break end
        if i ~= index then table.insert(new_lines, line) end
    end
    return write_opened_files_in_table(new_lines)
end

local function mark_open_from_table_of_infos(table_of_infos)
    current_file_path = table_of_infos.match
    return mark_open_from_name(current_file_path)
end

local function update_file_list(search_term)
    if not popup_buf_id or not vim.api.nvim_buf_is_valid(popup_buf_id) then
        return
    end
    local unfiltered_files = get_opened_files_in_table()
    local old_files = {}
    local old_files_lines = {}

    for _, v in ipairs(unfiltered_files) do
        local i = #old_files+1
        if string.sub(v, 1, #home_path) == home_path then v = '~' .. string.sub(v, #home_path+1, -1) end
        if search_term == "" or v:lower():find(search_term:lower(), 1, true) then
            old_files[i] = v
            old_files_lines[i] = string.format(' %2d ', i-1) .. v .. string.format(' %d ', i-1)
        end
    end

    vim.api.nvim_buf_set_option(popup_buf_id, 'modifiable', true)
    vim.api.nvim_buf_set_lines(popup_buf_id, 0, -1, false, old_files_lines)
    local ns_id = vim.api.nvim_create_namespace('buf-color-namespace')
    vim.api.nvim_buf_clear_namespace(popup_buf_id, ns_id, 0, -1)
    for i = 0, #old_files_lines - 1 do
        local color = (i % 3 == 0) and 'Statement' or ((i % 3 == 1) and 'String' or 'Title')
        color = (i < 10) and color or 'Comment'
        local reversed_slash_index = old_files_lines[i + 1]:reverse():find("/")
        local last_slash_index = reversed_slash_index and (#old_files_lines[i + 1] - reversed_slash_index + 1) or 1000
        vim.api.nvim_buf_add_highlight(popup_buf_id, ns_id, color, i, 0, last_slash_index)
        vim.api.nvim_buf_add_highlight(popup_buf_id, ns_id, color, i, #old_files_lines[i+1]-3, #old_files_lines[i+1])
    end
    vim.api.nvim_buf_set_option(popup_buf_id, 'modifiable', false)

    M.filtered_files = old_files
end

local function update_search_display()
    if search_buf_id and vim.api.nvim_buf_is_valid(search_buf_id) then
        vim.api.nvim_buf_set_option(search_buf_id, 'modifiable', true)
        vim.api.nvim_buf_set_lines(search_buf_id, 0, -1, false, {search_text})
        vim.api.nvim_buf_set_option(search_buf_id, 'modifiable', false)
    end
end

local function add_char_to_search(char)
    search_text = search_text .. char
    update_search_display()
    update_file_list(search_text)
end

local function remove_char_from_search()
    if #search_text > 0 then
        search_text = string.sub(search_text, 1, #search_text - 1)
        update_search_display()
        update_file_list(search_text)
    end
end

local function add_hook(buf_id, key)
    vim.api.nvim_buf_set_keymap(buf_id, 'n', key,
        ':lua require("' .. PLUGIN_NAME .. '").key_pressed("' .. string.gsub(key, "<", "!") .. '")<CR>',
        {noremap = true, silent = true})
end

local function create_search_window()
    search_buf_id = vim.api.nvim_create_buf(false, true)
    local editor_width = vim.api.nvim_get_option('columns')
    local editor_height = vim.api.nvim_get_option('lines')

    local win_height = 1
    local win_width = 60
    local row = math.ceil((editor_height - win_height) / 2 + 12) -- Position below the main popup
    local col = math.ceil((editor_width - win_width) / 2)

    local window_options = {
        style = 'minimal', relative = 'editor', border = 'single',
        width = win_width, height = win_height, row = row, col = col,
    }

    search_win_id = vim.api.nvim_open_win(search_buf_id, true, window_options)
    vim.api.nvim_buf_set_option(search_buf_id, 'modifiable', true)
    vim.api.nvim_buf_set_lines(search_buf_id, 0, -1, false, {""})
    vim.api.nvim_buf_set_option(search_buf_id, 'modifiable', false)

    for _, key in ipairs({'<Space>', '<BS>', '<Esc>', '<CR>'}) do add_hook(search_buf_id, key) end
    for i = 97, 122 do add_hook(search_buf_id, string.char(i)) end  -- a to z (lowercase)
    for i = 65,  90 do add_hook(search_buf_id, string.char(i)) end  -- A to Z (uppercase)
    for i = 48,  57 do add_hook(search_buf_id, string.char(i)) end  -- 0 to 9
    local special_chars = ',_-/:;@#&(){}+=|~`\'<>?!'
    for i = 1, #special_chars do add_hook(search_buf_id, string.sub(special_chars, i, i)) end
end

local function close_popup()
    if search_win_id and vim.api.nvim_win_is_valid(search_win_id) then
        vim.api.nvim_win_close(search_win_id, true)
    end
    if search_buf_id and vim.api.nvim_buf_is_valid(search_buf_id) then
        vim.api.nvim_buf_delete(search_buf_id, {force = true})
    end
    if popup_win_id and vim.api.nvim_win_is_valid(popup_win_id) then
        vim.api.nvim_win_close(popup_win_id, true)
    end
    if popup_buf_id and vim.api.nvim_buf_is_valid(popup_buf_id) then
        vim.api.nvim_buf_delete(popup_buf_id, {force = true})
    end
    search_win_id = nil
    search_buf_id = nil
    popup_win_id = nil
    popup_buf_id = nil
    search_text = ""
    M.filtered_files = nil
end

local function number_pressed(key)
    if M.filtered_files and M.filtered_files[tonumber(key) + 1] then
        local file_path = M.filtered_files[tonumber(key) + 1]
        close_popup()
        mark_open_from_name(file_path)
        vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
    else close_popup() end
end

function M.key_pressed(key)
    if string.find('0123456789', key, 1, true) ~= nil then number_pressed(key)
    elseif key == '!CR>' then number_pressed(0)
    elseif key == '!Esc>' then close_popup()
    elseif key == '!BS>' then remove_char_from_search()
    elseif key == '!Space>' then add_char_to_search(' ')
    else add_char_to_search(key) end
end

function M.show_popup()
    popup_buf_id = vim.api.nvim_create_buf(false, true)

    local editor_width = vim.api.nvim_get_option('columns')
    local editor_height = vim.api.nvim_get_option('lines')

    local win_height = 20
    local win_width = 100
    local row = math.ceil((editor_height - win_height) / 2 - 1)
    local col = math.ceil((editor_width - win_width) / 2)

    local window_options = {
        style = 'minimal', relative = 'editor', border = 'single',
        width = win_width, height = win_height, row = row, col = col,
    }

    popup_win_id = vim.api.nvim_open_win(popup_buf_id, true, window_options)
    vim.api.nvim_win_set_option(popup_win_id, 'winblend', 15)
    update_file_list('')
    create_search_window()
end

function M.setup()
    ensure_dir(data_path)
    ensure_file(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME)
    vim.api.nvim_set_keymap(
        'n', 'o', ':lua require("' .. PLUGIN_NAME .. '").show_popup()<CR>',  {noremap = true, silent = true}
    )
    vim.api.nvim_create_autocmd("BufEnter", {pattern = "*", callback = mark_open_from_table_of_infos})
end

return M
