local M = {}

local config = require("file-finder.config")
local files = require("file-finder.files")

function M.score(pattern, str, skip_regex_matching)
  -- WARNING `find` raises on ["(" => ""] and ["t(" => "tt(("] but doesnt raise on ["t(" => ""]
  -- no easy and reliable way to do a pre-check, so just update the skip_regex_matching on first fail
  local low_str, low_pattern = str:lower(), pattern:lower()
  local start_pos, end_pos =     str:find(    pattern, 1, true)  -- start at first char and plain text matching
  if start_pos                       then return skip_regex_matching, 6, start_pos, end_pos end
  local start_pos, end_pos = low_str:find(low_pattern, 1, true)  -- start at first char and plain text matching (low)
  if start_pos                       then return skip_regex_matching, 3, start_pos, end_pos end
  if skip_regex_matching             then return skip_regex_matching, 0, start_pos, end_pos end
  local worked, start_pos, end_pos = pcall(string.find,     str,     pattern)    -- now does pattern matching
  if not worked                      then return true,                0, start_pos, end_pos end
  if start_pos                       then return skip_regex_matching, 2, start_pos, end_pos end
  local worked, start_pos, end_pos = pcall(string.find, low_str, low_pattern)    -- now does pattern matching (low)
  if not worked                      then return skip_regex_matching, 0, start_pos, end_pos end
  if start_pos                       then return skip_regex_matching, 1, start_pos, end_pos end
  return                                         skip_regex_matching, 0, start_pos, end_pos
end

function M.filter(pattern, items, key_func, file_only_mode)
  -- TODO the state of pattern matching or no should be shown in the ui
  -- TODO handle this before, reuse history like with the o version?
  --      => so that path computation should actually be done elsewhere
  if not pattern or pattern == "" then return items end
  local scored_items, skip_regex_matching = {}, false
  key_func = key_func or function(item) return item end
  for _, item in ipairs(items) do
    local file_path, key, item_score, current_score = item.file, key_func(item), 0, 0
    local printed_path = files.get_printable_file_infos(item.file).short_path -- may refactor to avoid double exec
    -- next line is a quick and dirty fix, this function should receive full and partial path anyway
    if not file_only_mode then printed_path = item.file end -- otherwise match on title doesn't work with O
    skip_regex_matching, current_score, start_pos, end_pos = M.score(pattern, printed_path, skip_regex_matching)
    item_score = current_score * 1000
    local matched_lines = {}
    local line_num = 0
    if not file_only_mode then
      for line in io.lines(file_path) do
        line_num = line_num + 1
        skip_regex_matching, current_score, start_pos, end_pos = M.score(pattern, line, skip_regex_matching)
        item_score = item_score + current_score
        -- Collect up to max_lines_per_file + 1 to know if "..." indicator is needed
        if current_score > 0 and #matched_lines < config.max_lines_per_file + 1 then
          table.insert(matched_lines, {line_num = line_num, content = line, start_pos = start_pos, end_pos = end_pos})
        end
      end
    end
    if item_score > 0 then
      table.insert(scored_items, {file_path = file_path, score = item_score, key = key, matched_lines = matched_lines})
    end
  end
  
  table.sort(scored_items, function(a, b)
    return a.score > b.score
  end)
  
  local result = {}
  for _, scored_item in ipairs(scored_items) do
    table.insert(result, {file = scored_item.file_path, matched_lines = scored_item.matched_lines})
  end
  return result
end

return M
