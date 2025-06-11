local M = {}

function M.score(pattern, str, skip_regex_matching)  -- TODO also return pos
  local plain_pos = str:find(pattern, 1, true)  -- start at first char and plain text matching
  if plain_pos                   then return 3 end
  if skip_regex_matching         then return 0 end
  plain_pos = str:find(pattern)  -- now does pattern matching
  if plain_pos                   then return 1 end
  return 0
end

function M.filter(pattern, items, key_func)
  -- TODO handle this before, reuse history like with the o version?
  if not pattern or pattern == "" then return items end
  local do_regex_matching = pcall(string.find, "", pattern)  -- check the status of the protected call
  local scored_items = {}
  key_func = key_func or function(item) return item end
  
  for _, item in ipairs(items) do
    local key = key_func(item)
    local score = M.score(pattern, item, not do_regex_matching) * 1000
    local matched_lines_table = {}
    for line in io.lines(item) do
      score = score + M.score(pattern, line, not do_regex_matching)
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
