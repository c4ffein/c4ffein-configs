-- Load and write history files
-- An history file must start by: C4NV-history-v0.0.0\0\n
-- An history file then contains entries separated by \0\n
-- An entry contains parts beginning by an \0 and another char defining the type of the part, for now there are 2 parts:
-- 1: the full path of an opened file
-- 2: the full path of the current directory at the time the file was opened - as it is possible to open files outside
-- That way, when viewing the history, it is possible to either match:
-- - files that are inside the current directory
-- - files that were opened from a directory that is (or is contained in) the current directory - could be useful again
-- When saving, we can remove file duplicates if the one we are saving is from a cd that is or contains the previous cd
-- WARNING Saving a file creates a temporary file.tmp

local M = {}

local FILE_HEADER = "C4NV-history-v0.0.0\0\n" -- KISS for now

local PART_FILEPATH = "1"
local PART_CURRENT_DIR = "2"
local ALLOWED_PARTS = PART_FILEPATH .. PART_CURRENT_DIR

local function load_chunk(chunk_data)
  -- Load a chunk (a part of the history file containing a file opened entry), returns info_table, error_message
  if #chunk_data == 0 then return nil, "no data" end
  local chunk_table = {}
  -- Parse parts within the chunk that start with \0 followed by another char
  local part_start = 1
  while part_start <= #chunk_data do
    if chunk_data:sub(part_start, part_start) ~= "\0" then return nil, "part entry not starting by \\0" end
    local key_char = chunk_data:sub(part_start + 1, part_start + 1)
    if #key_char == 0 or not ALLOWED_PARTS:find(key_char) then return nil, "part entry unknown" end
    local next_null = chunk_data:find("\0", part_start + 2)
    if next_null == nil then next_null = #chunk_data + 1 end -- consider the end of chunk_data as the end of that part
    chunk_table[key_char] = chunk_data:sub(part_start + 2, next_null - 1)
    part_start = next_null
  end
  if next(chunk_table) == nil then return nil, "empty chunk" end return chunk_table, nil
end

function M.load_history(filename)
  -- An history file that doesn't start with C4NV-history-v0.0.0\0\n can be considered as empty
  -- Ignore if there is no history, invalid entries are simply ignored, but a file must start with the correct header
  -- Now start by reading file
  local file = io.open(filename, "rb")
  if not file then return {}, nil end  -- ignore if no history
  local content = file:read("*all")
  file:close()
  local chunks = {}
  if string.sub(content, 1, #FILE_HEADER) ~= FILE_HEADER then return nil, "no correct header" end
  -- Split content by \0\n (null byte followed by newline), start just after the len of the accepted header
  local chunk_start = #FILE_HEADER + 1
  while chunk_start <= #content do
    local chunk_end = content:find("\0\n", chunk_start) or #content + 1 -- works whether the file ends with \0\n
    local chunk_data = content:sub(chunk_start, chunk_end - 1)
    local chunk_table, error_message = load_chunk(chunk_data)
    local chunk_verified = not error_message and chunk_table and next(chunk_table)
    chunk_verified = chunk_verified and chunk_table[PART_FILEPATH] and chunk_table[PART_CURRENT_DIR]
    if chunk_verified then table.insert(chunks, chunk_table) end
    chunk_start = chunk_end + 2 -- search new chunk past \0\n
  end
  return chunks, nil
end

local function write_history(file_path, chunks)
  -- Write the history file, returns did_work, optional_error_message
  -- Use this function on a non-existing file path, then move to your existing history to avoid race conditions
  local last_err, file, checked_err, _ -- last_err is unusual but cheap way to ensure the file is always closed
  file, checked_err = io.open(file_path, "wx") -- fails if not creating - we want that to avoid race conditions
  if checked_err or not file then return nil, "could not create the .tmp file" end
  _, checked_err = file:write(FILE_HEADER)
  if checked_err then last_err = checked_err end
  for i, chunk in ipairs(chunks) do
    for key, value in pairs(chunk) do
      if type(key) == "string" and #key == 1 then _, checked_err = file:write("\0" .. key .. value) end
      if checked_err then last_err = checked_err end
    end
    if i < #chunks then file:write("\0\n") end  -- chunk separator (except after the last chunk, load_history is ok)
  end
  _, checked_err = file:close()
  if checked_err then last_err = checked_err end
  if last_err then return nil, last_err end
  return true, nil
end

function M.append_to_history(history_file_path, added_to_history_file_path, current_directory, limit)
  -- WARNING Saving a file creates a temporary file.tmp
  -- Removes duplicates as explained in the top comment
  -- Returns success, error_message
  local current_history, error_msg = M.load_history(history_file_path)
  if error_msg then return false, error_msg end
  local new_history = {}
  if current_directory:sub(-1) ~= "/" then current_directory = current_directory .. "/" end -- trailing slash
  table.insert(new_history, {[PART_FILEPATH] = added_to_history_file_path, [PART_CURRENT_DIR] = current_directory})
  for _, entry in ipairs(current_history) do
    if entry[PART_CURRENT_DIR]:sub(-1) ~= "/" then entry[PART_CURRENT_DIR] = entry[PART_CURRENT_DIR] .. "/" end
    local entry_not_in_current_dir = entry[PART_CURRENT_DIR]:sub(1, #current_directory) ~= current_directory
    if entry[PART_FILEPATH] ~= added_to_history_file_path or entry_not_in_current_dir then
      table.insert(new_history, entry)
    end
  end
  while #new_history > limit do table.remove(new_history) end -- enforce limit
  local success, error_message = write_history(history_file_path .. ".tmp", new_history)
  if not success or error_message then return false, error_message end
  local success, error_message = os.rename(history_file_path .. ".tmp", history_file_path)
  if not success or error_message then return false, error_message end
  return true, nil
end

return M
