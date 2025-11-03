local M = {}

-- Validate filename: only allow a-zA-Z0-9.-_ and space, reject "." and ".."
local function is_valid_filename(name)
  if not name or name == "" then return false, "Filename cannot be empty" end
  -- Reject "." and ".."
  if name == "." or name == ".." then return false, "Invalid filename: '.' and '..' are not allowed" end
  -- Check character by character (no regex)
  for i = 1, #name do
    local byte = string.byte(name, i)
    local valid = (byte >= 48 and byte <= 57)   -- 0-9
               or (byte >= 65 and byte <= 90)   -- A-Z
               or (byte >= 97 and byte <= 122)  -- a-z
               or byte == 32  -- space
               or byte == 45  -- -
               or byte == 46  -- .
               or byte == 95  -- _
    if not valid then
      local char = string.char(byte)
      return false, "Invalid character in filename. Only a-z, A-Z, 0-9, ' ', '.', '-', '_' are allowed"
    end
  end
  return true, nil
end

-- Validate path: same rules as filename but / is allowed, with anti-traversal checks
local function is_valid_path(path)
  if not path or path == "" then
    return false, "Path cannot be empty"
  end
  -- Reject "." and ".."
  if path == "." or path == ".." then return false, "Invalid path: '.' and '..' are not allowed" end
  -- Check for path traversal patterns
  if path:sub(1, 2) == "./" or path:sub(1, 3) == "../" then return false, "Path cannot start with './' or '../'" end
  if path:sub(-2) == "/."   or path:sub(-3) == "/.."   then return false, "Path cannot end with '/.' or '/..'"   end
  if path:find("/%.%./")    or path:find("/%./")       then return false, "Path cannot contain '/./' or '/../'"  end
  -- Check character by character (no regex) - same as filename but / is allowed
  for i = 1, #path do
    local byte = string.byte(path, i)
    local valid = (byte >= 48 and byte <= 57)   -- 0-9
               or (byte >= 65 and byte <= 90)   -- A-Z
               or (byte >= 97 and byte <= 122)  -- a-z
               or byte == 32  -- space
               or byte == 45  -- -
               or byte == 46  -- .
               or byte == 47  -- /
               or byte == 95  -- _
    if not valid then
      local char = string.char(byte)
      return false, string.format("Invalid character '%s' in path. Only a-z, A-Z, 0-9, ' ', '.', '-', '_', '/' are allowed", char)
    end
  end
  return true, nil
end

-- Sanitize filename for display: replace invalid characters with 'X'
local function sanitize_for_display(name)
  local result = {}
  for i = 1, #name do
    local byte = string.byte(name, i)
    local valid = (byte >= 48 and byte <= 57)   -- 0-9
               or (byte >= 65 and byte <= 90)   -- A-Z
               or (byte >= 97 and byte <= 122)  -- a-z
               or byte == 32  -- space
               or byte == 45  -- -
               or byte == 46  -- .
               or byte == 95  -- _
    if valid then table.insert(result, string.char(byte)) else table.insert(result, "X") end
  end
  return table.concat(result)
end

-- Export validation and helper functions for use in UI
M.is_valid_filename = is_valid_filename
M.is_valid_path = is_valid_path
M.sanitize_for_display = sanitize_for_display

function M.create_file(directory, filename)
  -- Validate filename
  local valid, err = is_valid_filename(filename)
  if not valid then return false, err end
  local path = directory .. "/" .. filename
  -- Check if file already exists
  if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
    return false, "File or directory already exists"
  end
  local file = io.open(path, "w")
  if file then
    file:close()
    return true, nil
  end
  return false, "Failed to create file"
end

function M.create_directory(directory, dirname)
  -- Validate directory name
  local valid, err = is_valid_filename(dirname)
  if not valid then return false, err end
  local path = directory .. "/" .. dirname
  local success = vim.fn.mkdir(path, "p")
  if success == 1 then return true, nil end
  return false, "Failed to create directory"
end

function M.delete_path(path)
  if vim.fn.isdirectory(path) == 1 then
    local success = vim.fn.delete(path, "rf")
    if success == 0 then return true, nil end
    return false, "Failed to delete directory"
  else
    local success = vim.fn.delete(path)
    if success == 0 then return true, nil end
    return false, "Failed to delete file"
  end
end

function M.rename_path(old_path, new_name)
  -- Validate new name
  local valid, err = is_valid_filename(new_name)
  if not valid then return false, err end
  local dir = vim.fn.fnamemodify(old_path, ":h")
  local new_path = dir .. "/" .. new_name
  local success = vim.fn.rename(old_path, new_path)
  if success == 0 then return true, nil end
  return false, "Failed to rename"
end

return M
