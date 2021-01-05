local function case(name, run)
  print(name .. '...')
  run()
  print('', '...ok')
end

local function json_decode(text_or_it)
  local function skip_whitespace(itx)
    local x
    repeat x = itx() until x == nil or x:match('%s') == nil
    return x
  end
  local it = type(text_or_it) == 'string' and text_or_it:gmatch('.') or
                 text_or_it

  local e = skip_whitespace(it)
  if not e or e == '}' or e == ']' then
    return nil
  elseif e == '{' then
    local o = {}
    while true do
      local k = json_decode(it)
      if not k then return o end
      if type(k) ~= 'string' then
        error('json: expect string key for object')
      end
      if skip_whitespace(it) ~= ':' then
        error('json: missing ":" in object')
      end
      local x_sep = nil
      o[k], x_sep = json_decode(it)
      local sep = x_sep and x_sep or skip_whitespace(it)
      if sep == '}' then return o end
      if sep ~= ',' then error('json: missing "," or "}" closing object') end
    end

  elseif e == '[' then
    local a = {}
    while true do
      local x_sep = nil
      local v, x_sep = json_decode(it)
      if not v then return a end
      a[#a + 1] = v
      local sep = x_sep and x_sep or skip_whitespace(it)
      if sep == ']' then return a end
      if sep ~= ',' then error('json: missing "," or "]" closing array') end
    end
  elseif e == '"' then
    local st = {}
    e = it()
    repeat
      table.insert(st, e)
      e = it()
    until e == nil or e == '"'
    local s = table.concat(st):gsub('\\n', '\n')
    return s
  else
    local n = ''
    repeat
      n = n .. e
      e = it()
    until e == nil or e:match('%S') == nil or e == ',' or e == '}' or e == ']'
    if n == 'true' then
      return true, e
    elseif n == 'false' then
      return false, e
    elseif n == 'null' then
      return nil, e
    end
    local ln = tonumber(n)
    if not ln then error('json: unknown keyword: "' .. n .. '"') end
    return ln, e
  end
end

local function exec(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  return s;
end

local function exec_fang(args)
  return exec('lua fang.lua ' .. table.concat(args, ' '))
end

local function tests_suites(s)
  assert(type(s) == 'table')
  assert(s.type and (s.type == 'suite' or s.type == 'test'),
         'unexpected table type ' .. tostring(s))
  assert(s.label and type(s.label) == 'string',
         'missing label in suite' .. s.type)
  assert(s.id and type(s.id) == 'string', 'missing id in ' .. s.type)

  if s.type == 'suite' then
    assert(s.children and type(s.children) == 'table',
           'no children list in ' .. s.type)
    for _, v in ipairs(s.children) do tests_suites(v) end
  elseif s.type == 'test' then
    assert(s.line and type(s.line) == 'number',
           'missing test information \'line\'')
    assert(s.file and type(s.file) == 'string',
           'missing test information \'file\'')
  else
    assert(false, 'missing test implementation')
  end
end

local function count_suites_and_cases(suites)
  local s, t = 0, 0
  if suites.type == 'suite' then
    s = s + 1
    for _, v in ipairs(suites.children) do
      local ss, tt = count_suites_and_cases(v)
      s, t = s + ss, t + tt
    end
  elseif suites.type == 'test' then
    t = t + 1
  else
    assert(false, 'missing implementation')
  end
  return s, t
end

local num_suites, num_cases
case('Checking a list of all suites', function()
  local suites_json = exec_fang({'suite', 'tests/examples'})
  -- print(suites_json)
  local suites = json_decode(suites_json)
  tests_suites(suites)

  num_suites, num_cases = count_suites_and_cases(suites)
  assert(num_suites == 5,
         'expected different test suite count then ' .. num_suites)
  assert(num_cases == 7, 'expected different test case count then ' .. num_cases)
end)

case('Check list no test files defined', function()
  local out = exec_fang({'suite', 'tests/dir_with_out_tests'})
  local json = json_decode(out)
  assert(json.children and type(json.children) == 'table')
  assert(#json.children == 0)
end)

case('Check list only empty test files defined', function()
  local out = exec_fang({'suite', 'tests/dir_with_empty_test_files'})
  local json = json_decode(out)
  assert(json.children and type(json.children) == 'table')
  assert(#json.children == 0)
end)

case('Checking running all test', function()
  local unique_running_set = {}
  local running = {suite = {}, test = {}}
  local failed_tests = {}
  for s in exec_fang({'run', 'tests/examples'}):gmatch('[^\r\n]+') do
    -- print(s)
    local event = json_decode(s)
    assert(event.type and (event.type == 'suite' or event.type == 'test'))
    assert(event.state and type(event.state) == 'string')
    assert(event[event.type] and type(event[event.type]) == 'string')

    if event.state == 'running' then
      local id = event[event.type]
      assert(unique_running_set[id] == nil, 'A non unique id found: ' .. id)
      unique_running_set[id] = true
      running[event.type][#running[event.type] + 1] = id
    else
      if event.type == 'test' then
        assert(event.state == 'passed' or event.state == 'failed',
               'wrong test event state ' .. event.state)
        assert(event.decorations and type(event.decorations) == 'table',
               'wrong test decorations')
        if event.state == 'passed' then
          assert(#event.decorations == 0)
        elseif event.state == 'failed' then
          assert(#event.decorations > 0)
          failed_tests[event[event.type]] = event.decorations
        end
      elseif event.type == 'suite' then
        assert(event.state == 'completed')
      else
        assert(false, 'missing test implementation')
      end
    end

    -- print(event.type, event.state, event[event.type], s)
  end

  -- do not count 'root'
  assert(#running.suite == num_suites - 1,
         'did not run all suites ' .. #running.suite)
  assert(#running.test == num_cases, 'did not run all test cases')

  local f1 =
      failed_tests['tests/examples/factorial_test.lua::factorial_tests::broken::two']
  assert(f1, 'missing failed test')
  assert(f1[1].line == 19)
  assert(f1[1].message == 'not true')

  local f2 =
      failed_tests['tests/examples/arithmetic_test.lua::arithmetic_test::addition_broken']
  assert(f2, 'missing failed test')
  assert(f2[1].line == 8)
  assert(f2[1].message == 'not true')
  assert(f2[2].line == 9)
  assert(f2[2].message == 'not true')
  -- for k, v in pairs(failed_tests) do
  --   print(k)
  --   for i, e in ipairs(v) do print(i, e.line, e.message) end
  -- end
end)

case('Checking running single test', function()
  local count = 0
  local case =
      'tests/examples/arithmetic_test.lua::arithmetic_test::addition_broken'
  for s in exec_fang({'run', 'tests/examples', case}):gmatch('[^\r\n]+') do
    s = json_decode(s)
    assert(s.test, 'expect test run got ' .. tostring(s.type))
    assert(s.test == case, 'wrong test run ' .. tostring(s.test))
    count = count + 1
  end
  assert(count == 2, 'expect 2 messages for a single test case')
end)

case('Checking running 2 single test', function()
  local count = 0
  local case1 =
      'tests/examples/arithmetic_test.lua::arithmetic_test::addition_broken'
  local case2 =
      'tests/examples/factorial_test.lua::factorial_tests::broken::two'
  for s in exec_fang({'run', 'tests/examples', case1, case2}):gmatch('[^\r\n]+') do
    s = json_decode(s)
    assert(s.test, 'expect test run got ' .. tostring(s.type))
    assert(s.test == case1 or s.test == case2,
           'wrong test run ' .. tostring(s.test))
    count = count + 1
  end
  assert(count == 4, 'expect 4 messages for 2 single test case')
end)

case('Checking running single test suite', function()
  local count = 0
  local suite = 'tests/examples/factorial_test.lua::factorial_tests::broken'
  for s in exec_fang({'run', 'tests/examples', suite}):gmatch('[^\r\n]+') do
    -- print(s)
    s = json_decode(s)
    assert(s[s.type]:sub(1, #suite) == suite,
           'wrong test run ' .. tostring(s.test))
    count = count + 1
  end
  assert(count == 4, 'expect 4 messages for this suite')
end)

case('Checking running other single test suite...', function()
  local count = 0
  local suite = 'tests/examples/arithmetic_test.lua::arithmetic_test'
  for s in exec_fang({'run', 'tests/examples', suite}):gmatch('[^\r\n]+') do
    -- print(s)
    s = json_decode(s)
    assert(s[s.type]:sub(1, #suite) == suite,
           'wrong test run ' .. tostring(s.test))
    count = count + 1
  end
  assert(count == 6, 'expect 4 messages for this suite')
end)
