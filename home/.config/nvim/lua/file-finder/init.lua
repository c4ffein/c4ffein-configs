local M = {}

local PLUGIN_NAME = 'file-finder'
local PLUGIN_LAST_FILES_OPEN_FILE_NAME = 'last_files_open.txt'
local MAX_SAVED_FILES = 40

local home_path = os.getenv("HOME") or os.getenv("USERPROFILE") -- Unix or Windows
local data_path = vim.fn.stdpath('data') .. '/' .. PLUGIN_NAME .. '/' -- ~/.local/share/nvim/file-finder/ probably

local popup_win_id = nil
local popup_buf_id = nil

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

function get_opened_files_in_table()
    local lines = {}
    for line in io.lines(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME) do table.insert(lines, line) end
    return lines
end

function write_opened_files_in_table(lines)
    local output_file = io.open(data_path .. PLUGIN_LAST_FILES_OPEN_FILE_NAME, "w")
    if not output_file then return false end
    output_file:write(table.concat(lines, '\n'))
    output_file:close()
    return true
end

function mark_open_from_name(current_file_path)
    lines = get_opened_files_in_table()
    index = find_index(lines, current_file_path)
    local new_lines = {current_file_path}
    for i, line in ipairs(lines) do
        if #new_lines > MAX_SAVED_FILES then break end
        if i ~= index then table.insert(new_lines, line) end
    end
    return write_opened_files_in_table(new_lines)
end

function mark_open_from_table_of_infos(table_of_infos)
    current_file_path = table_of_infos.match
    return mark_open_from_name(current_file_path)
end

function M.show_popup()
    popup_buf_id = vim.api.nvim_create_buf(false, true)

    local old_files = get_opened_files_in_table()
    local old_files_lines = {}
    for i, v in ipairs(old_files) do
        if string.sub(v, 1, #home_path) == home_path then v = '~' .. string.sub(v, #home_path+1, -1) end
        old_files_lines[i] = string.format(' %2d ', i-1) .. v .. string.format(' %d ', i-1)
    end

    vim.api.nvim_buf_set_lines(popup_buf_id, 0, -1, false, old_files_lines)
    local ns_id = vim.api.nvim_create_namespace('buf-color-namespace')
    for i = 0, 40 do
        if i >= #old_files_lines then break end
        local color = (i % 3 == 0) and 'Statement' or ((i % 3 == 1) and 'String' or 'Title')
        color = (i < 10) and color or 'Comment'
        local reversed_slash_index = old_files_lines[i + 1]:reverse():find("/")
        local last_slash_index = reversed_slash_index and (#old_files_lines[i + 1] - reversed_slash_index + 1) or 1000
        vim.api.nvim_buf_add_highlight(popup_buf_id, ns_id, color, i, 0, last_slash_index)
        vim.api.nvim_buf_add_highlight(popup_buf_id, ns_id, color, i, #old_files_lines[i+1]-3, #old_files_lines[i+1])
    end

    local editor_width = vim.api.nvim_get_option('columns')
    local editor_height = vim.api.nvim_get_option('lines')

    local win_height = 20
    local win_width = 100
    local row = math.ceil((editor_height - win_height) / 2 - 1)
    local col = math.ceil((editor_width - win_width) / 2)

    local window_options = {
        style = 'minimal',
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = row,
        col = col,
        border = 'single'
    }

    popup_win_id = vim.api.nvim_open_win(popup_buf_id, true, window_options)

    vim.api.nvim_win_set_option(popup_win_id, 'winblend', 15)

    vim.api.nvim_buf_set_keymap(popup_buf_id, 'n', '<Esc>', 
        ':lua require(PLUGIN_NAME).close_popup()<CR>', 
        {noremap = true, silent = true})

    for i = 0, 9 do
        vim.api.nvim_buf_set_keymap(0, 'n', tostring(i),
            string.format(':lua require("' .. PLUGIN_NAME .. '").key_pressed(%d)<CR>', i),
            {noremap = true, silent = true})
    end

end

function M.key_pressed(key)
    M.close_popup()
    local old_files = get_opened_files_in_table()
    local file_path = old_files[tonumber(key) + 1]
    mark_open_from_name(file_path)
    vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
end

function M.close_popup()
    if popup_win_id and vim.api.nvim_win_is_valid(popup_win_id) then
        vim.api.nvim_win_close(popup_win_id, true)
    end
    if popup_buf_id and vim.api.nvim_buf_is_valid(popup_buf_id) then
        vim.api.nvim_buf_delete(popup_buf_id, {force = true})
    end
    popup_win_id = nil
    popup_buf_id = nil
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
