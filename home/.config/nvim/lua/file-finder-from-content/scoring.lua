local M = {}

function M.score(pattern, str, skip_regex_matching)  -- TODO also return pos
  -- WARNING `find` raises on ["(" => ""] and ["t(" => "tt(("] but doesnt raise on ["t(" => ""]
  -- no easy and reliable way to do a pre-check, so just update the skip_regex_matching on first fail
  local plain_pos = str:find(pattern, 1, true)  -- start at first char and plain text matching
  if plain_pos                   then return skip_regex_matching, 3 end
  if skip_regex_matching         then return skip_regex_matching, 0 end
  local worked, pattern_pos = pcall(string.find, str, pattern)    -- now does pattern matching
  if not worked                  then return true,                0 end
  if pattern_pos                 then return skip_regex_matching, 1 end
  return                                     skip_regex_matching, 0
end

function M.filter(pattern, items, key_func)
  -- TODO the state of pattern matching or no should be shown in the ui
  -- TODO handle this before, reuse history like with the o version?
  if not pattern or pattern == "" then return items end
  local scored_items, skip_regex_matching = {}, false
  key_func = key_func or function(item) return item end
  
  for _, item in ipairs(items) do
    local key, item_score, current_score = key_func(item), 0, 0
    skip_regex_matching, current_score = M.score(pattern, item, skip_regex_matching)
    item_score = current_score * 1000
    local matched_lines = {}
    local line_num = 0
    for line in io.lines(item) do
      line_num = line_num + 1
      skip_regex_matching, current_score = M.score(pattern, line, skip_regex_matching)
      item_score = item_score + current_score
      if current_score > 0 and #matched_lines < 3 then
        table.insert(matched_lines, {line_num = line_num, content = line})
      end
    end
    if item_score > 0 then
      table.insert(scored_items, {item = item, score = item_score, key = key, matched_lines = matched_lines})
    end
  end
  
  table.sort(scored_items, function(a, b)
    return a.score > b.score
  end)
  
  local result = {}
  for _, scored_item in ipairs(scored_items) do
    table.insert(result, {file = scored_item.item, matched_lines = scored_item.matched_lines})
  end
  
  return result
end

return M
