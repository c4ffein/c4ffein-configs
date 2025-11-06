local M = {}

local config = require("file-finder.config")

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

function M.filter(pattern, items, key_func, file_only_mode, history_rank)
  if not pattern or pattern == "" then return items, false end
  local scored_items, skip_regex_matching = {}, false
  key_func = key_func or function(item) return item end
  history_rank = history_rank or {}
  for _, item in ipairs(items) do
    local file_path, key, item_score, current_score = item.file, key_func(item), 0, 0
    skip_regex_matching, current_score, start_pos, end_pos = M.score(pattern, item.printed_path, skip_regex_matching)
    item_score = current_score * 1000
    local matched_lines = {}
    local line_num = 0
    if not file_only_mode then
      local abs_file_path = file_path:sub(1, 1) == "/" and file_path or (config.current_directory .. file_path)
      local ok, iter = pcall(io.lines, abs_file_path)
      if ok and iter then
        for line in iter do
          line_num = line_num + 1
          skip_regex_matching, current_score, start_pos, end_pos = M.score(pattern, line, skip_regex_matching)
          item_score = item_score + current_score
          -- Collect up to MAX_LINES_PER_FILE + 1 to know if "..." indicator is needed
          if current_score > 0 and #matched_lines < config.MAX_LINES_PER_FILE + 1 then
            table.insert(matched_lines, {line_num = line_num, content = line, start_pos = start_pos, end_pos = end_pos})
          end
        end
      end
    end
    if item_score > 0 then
      local rank = history_rank[file_path] or math.huge  -- Files not in history get worst rank
      table.insert(scored_items, {file_path = file_path, score = item_score, key = key, matched_lines = matched_lines, history_rank = rank, printed_path = item.printed_path})
    end
  end

  table.sort(scored_items, function(a, b)
    -- Primary sort by score (higher is better)
    if a.score ~= b.score then
      return a.score > b.score
    end
    -- Tiebreaker: use history rank (lower is better = more recent)
    return a.history_rank < b.history_rank
  end)

  local result = {}
  for _, scored_item in ipairs(scored_items) do
    table.insert(result, {file = scored_item.file_path, matched_lines = scored_item.matched_lines, printed_path = scored_item.printed_path})
  end
  return result, skip_regex_matching
end

return M
