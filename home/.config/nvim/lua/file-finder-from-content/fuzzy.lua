local M = {}

function M.score(pattern, str)
  if pattern == "" then return  end  -- TODO handle this before, reuse history like with the o version?
  local pattern_len = #pattern
  local str_len = #str
  if pattern_len > str_len then return 0 end
  return str:find(pattern) and 1 or 0  -- TODO better if it can be perf enough
end

function M.filter(pattern, items, key_func)
  if not pattern or pattern == "" then
    return items
  end
  
  local scored_items = {}
  key_func = key_func or function(item) return item end
  
  for _, item in ipairs(items) do
    local key = key_func(item)
    local score = M.score(pattern, item) * 1000
    local matched_lines_table = {}
    for line in io.lines(item) do
      score = score + M.score(pattern, line)
      -- TODO
      -- if line_score > 0 then
      --   table.insert(matched_lines_table, {item = item, score = score, key = key})
      -- end
    end
    if score > 0 then
      table.insert(scored_items, {item = item, score = score, key = key})
    end
  end
  
  table.sort(scored_items, function(a, b)
    return a.score > b.score
  end)
  
  local result = {}
  for _, scored_item in ipairs(scored_items) do
    table.insert(result, scored_item.item)
  end
  
  return result
end

return M
