local json = require 'json'

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

print('Checking a list of all suites...')
local suites = json.decode(exec_fang({'suite', 'tests/'}))
tests_suites(suites)

local num_suites, num_cases = count_suites_and_cases(suites)
assert(num_suites == 5,
       'expected different test suite count then ' .. num_suites)
assert(num_cases == 7, 'expected different test case count then ' .. num_cases)
print('', '...ok')

print('Checking running all test...')
local unique_running_set = {}
local running = {suite = {}, test = {}}
local failed_tests = {}
for s in exec_fang({'run', 'tests/'}):gmatch('[^\r\n]+') do
  local event = json.decode(s)
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
    failed_tests['two.broken.factorial_tests.tests//examples/factorial_test.lua']
assert(f1, 'missing failed test')
assert(f1[1].line == 19)
assert(f1[1].message == 'not true')

local f2 =
    failed_tests['addition_broken.arithmetic_test.tests//examples/arithmetic_test.lua']
assert(f2, 'missing failed test')
assert(f2[1].line == 8)
assert(f2[1].message == 'not true')
assert(f2[2].line == 9)
assert(f2[2].message == 'not true')

-- for k, v in pairs(failed_tests) do
--   print(k)
--   for i, e in ipairs(v) do print(i, e.line, e.message) end
-- end

print('', '...ok')
