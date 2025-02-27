local M = {}

local home_path = os.getenv("HOME") or os.getenv("USERPROFILE") -- Unix or Windows

local popup_win_id = nil
local popup_buf_id = nil

function M.show_popup()
    popup_buf_id = vim.api.nvim_create_buf(false, true)

    local old_files = vim.v.oldfiles
    local old_files_lines = {}
    for i, v in ipairs(old_files) do
        if string.sub(v, 1, #home_path) == home_path then
            v = '~' .. string.sub(v, #home_path+1, -1)
        end
        old_files_lines[i] = string.format(' %2d ', i-1) .. v .. string.format(' %d ', i-1)
    end

    vim.api.nvim_buf_set_lines(popup_buf_id, 0, -1, false, old_files_lines)
    local ns_id = vim.api.nvim_create_namespace('buf-color-namespace')
    for i = 0, 40 do
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
        ':lua require("file-finder").close_popup()<CR>', 
        {noremap = true, silent = true})

    for i = 0, 9 do
        vim.api.nvim_buf_set_keymap(0, 'n', tostring(i),
            string.format(':lua require("file-finder").key_pressed(%d)<CR>', i),
            {noremap = true, silent = true})
    end

end

function M.key_pressed(key)
    M.close_popup()
    local old_files = vim.v.oldfiles
    local file_path = old_files[tonumber(key) + 1]
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
    vim.api.nvim_set_keymap('n', 'o', 
        ':lua require("file-finder").show_popup()<CR>', 
        {noremap = true, silent = true})
end

return M
