queries = {}
local ok = false

for line in io.lines("stress/queries.txt") do
  if #line > 0 and not line:match("^#") then
    queries[#queries + 1] = line
    ok = true
  end
end

if not ok or #queries == 0 then
  io.stderr:write("ERROR: no queries loaded from stress/queries.txt\n")
  os.exit(1)
end

math.randomseed(os.time())

request = function()
  local q = queries[math.random(#queries)]
  local safe = q:gsub(" ", "+"):gsub("([^%w%+%.%-])", function(c)
    return string.format("%%%02X", c:byte())
  end)
  return wrk.format("GET", "/embed?text=" .. safe)
end

response = function(status, headers, body)
  if status ~= 200 then
    io.stderr:write(string.format("ERROR %d: %s\n", status, body:sub(1, 200)))
  end
end
