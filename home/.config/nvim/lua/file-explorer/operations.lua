local M = {}

function M.create_file(directory, filename)
  local path = directory .. "/" .. filename
  local file = io.open(path, "w")
  if file then
    file:close()
    return true, nil
  end
  return false, "Failed to create file"
end

function M.create_directory(directory, dirname)
  local path = directory .. "/" .. dirname
  local success = vim.fn.mkdir(path, "p")
  if success == 1 then
    return true, nil
  end
  return false, "Failed to create directory"
end

function M.delete_path(path)
  if vim.fn.isdirectory(path) == 1 then
    local success = vim.fn.delete(path, "rf")
    if success == 0 then
      return true, nil
    end
    return false, "Failed to delete directory"
  else
    local success = vim.fn.delete(path)
    if success == 0 then
      return true, nil
    end
    return false, "Failed to delete file"
  end
end

function M.rename_path(old_path, new_name)
  local dir = vim.fn.fnamemodify(old_path, ":h")
  local new_path = dir .. "/" .. new_name
  local success = vim.fn.rename(old_path, new_path)
  if success == 0 then
    return true, nil
  end
  return false, "Failed to rename"
end

return M
