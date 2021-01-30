local function class(n, init)
  local class_mt = {}
  local c = setmetatable({type = n}, class_mt)
  init = init or function(...) return ... end
  function class_mt:__call(...) return setmetatable(init(...), c) end
  c.__index = c
  return c
end

---@class ID
local ID = class('ID', function(r) return {r} end)
function ID:added(p)
  local r = setmetatable({table.unpack(self)}, ID)
  r[#r + 1] = p
  return r
end
function ID:tostring() return table.concat(self, '::') end

local function json(o, newline)
  newline = newline or '\n'
  if type(o) == 'number' then
    io.write(tostring(o))
  elseif type(o) == 'string' then
    io.write('"' .. o:gsub('\n', '\\n') .. '"')
  elseif type(o) == 'table' and type(o[1]) == 'nil' then
    local start = true
    io.write('{')
    for k, v in pairs(o) do
      if not start then io.write(',') end
      start = false
      io.write('"' .. k .. '":')
      json(v, '')
    end
    io.write('}' .. newline)
  elseif type(o) == 'table' then
    io.write('[')
    for i, v in ipairs(o) do
      if i > 1 then io.write(',') end
      json(v, '')
    end
    io.write(']' .. newline)
  end
end

---defining a test case 
---@class Test
---@field name string name of the test case
---@field id ID unique id for that test case
---@field line number line of file, where it is defined
---@field test_fn function() the test function to be executed
local Test = class('test')

local current_errors = {}
local ASSERT = {}

local function push_error(line, err)
  current_errors[#current_errors + 1] = {line = line, message = err}
end

---push new error from case
---@param e string | nil
---@param a boolean
local function add_error(e, a)
  if e then
    push_error(debug.getinfo(3).currentline, e)
    if a then error(ASSERT) end
  end
end

---A simple condition to be met for the unit
---@param condition boolean
function CHECK(condition)
  add_error((not condition) and
                ('condition not met \'' .. tostring(condition) .. '\''))
end

---compare 2 values on equal (==)
---@param val1 any
---@param val2 any
function CHECK_EQ(val1, val2)
  add_error((not (val1 == val2)) and
                (tostring(val1) .. ' ~= ' .. tostring(val2)))
end

---compare 2 values on not equal (~=)
---@param val1 any
---@param val2 any
function CHECK_NE(val1, val2)
  add_error((not (val1 ~= val2)) and
                (tostring(val1) .. ' == ' .. tostring(val2)))
end

---compare 2 values in order greater then (>)
---@param val1 any
---@param val2 any
function CHECK_GT(val1, val2)
  add_error((not (val1 > val2)) and (tostring(val1) .. ' <= ' .. tostring(val2)))
end

---compare 2 values in order less then (<)
---@param val1 any
---@param val2 any
function CHECK_LT(val1, val2)
  add_error((not (val1 < val2)) and (tostring(val1) .. ' >= ' .. tostring(val2)))
end

---compare 2 values in order greater or equal (>=)
---@param val1 any
---@param val2 any
function CHECK_GE(val1, val2)
  add_error((not (val1 >= val2)) and (tostring(val1) .. ' < ' .. tostring(val2)))
end

---compare 2 values in order less or equal (<=)
---@param val1 any
---@param val2 any
function CHECK_LE(val1, val2)
  add_error((not (val1 <= val2)) and (tostring(val1) .. ' > ' .. tostring(val2)))
end

---A simple condition to be met for the unit
---immediately stop
---@param condition boolean
function REQUIRE(condition)
  add_error((not condition) and
                ('condition not met \'' .. tostring(condition) .. '\''), true)
end

---compare 2 values on equal (==)
---immediately stop
---@param val1 any
---@param val2 any
function REQUIRE_EQ(val1, val2)
  add_error((not (val1 == val2)) and
                (tostring(val1) .. ' ~= ' .. tostring(val2)), true)
end

---compare 2 values on not equal (~=)
---immediately stop
---@param val1 any
---@param val2 any
function REQUIRE_NE(val1, val2)
  add_error((not (val1 ~= val2)) and
                (tostring(val1) .. ' == ' .. tostring(val2)), true)
end

---compare 2 values in order greater then (>)
---immediately stop
---@param val1 any
---@param val2 any
function REQUIRE_GT(val1, val2)
  add_error(
      (not (val1 > val2)) and (tostring(val1) .. ' <= ' .. tostring(val2)), true)
end

---compare 2 values in order less then (<)
---immediately stop
---@param val1 any
---@param val2 any
function REQUIRE_LT(val1, val2)
  add_error(
      (not (val1 < val2)) and (tostring(val1) .. ' >= ' .. tostring(val2)), true)
end

---compare 2 values in order greater or equal (>=)
---immediately stop
---@param val1 any
---@param val2 any
function REQUIRE_GE(val1, val2)
  add_error(
      (not (val1 >= val2)) and (tostring(val1) .. ' < ' .. tostring(val2)), true)
end

---compare 2 values in order less or equal (<=)
---immediately stop
---@param val1 any
---@param val2 any
function REQUIRE_LE(val1, val2)
  add_error(
      (not (val1 <= val2)) and (tostring(val1) .. ' > ' .. tostring(val2)), true)
end

function Test:runner(reporter, fun, name, id)
  current_errors = {}
  reporter.start_case(self)
  local ok, err = pcall(fun)
  if not ok and err ~= ASSERT then push_error(self.line, tostring(err)) end
  reporter.stop_case(self, current_errors)
end

function Test:run(reporter, select)
  if not select or select[self.id:tostring()] then
    self:runner(reporter, self.test_fn, self.name, self.id)
  end
end

---Test suite container class
---@class Suite
---@field id string unique identifiery
---@field file string file that defines that suite 
---@field line number line number in file 
---@field children table
local Suite = class('suite')

---define test case to be executed by testing framework
---@param case_name string name of the test case
---@param fn fun() callback to be executed
function Suite:case(case_name, fn)
  local db = debug.getinfo(fn)
  self.children[#self.children + 1] = Test {
    id = self.id:added(case_name),
    file = self.file,
    line = db.linedefined,
    name = case_name,
    test_fn = fn,
  }
end

---create a sub suite 
---@param subname string name of the sub suite
---@param scb fun(s:Suite) sub suite builder function
---@return Suite
function Suite:SubSuite(subname, scb)
  local ss = TestSuite(subname, scb, self.id)
  self.children[#self.children + 1] = ss
  return ss
end
Suite.is_suite = true

---Define a test suite with a given name an a test builder cb
---@param suite_name string the name of the suite
---@param cb fun(s:Suite) test builder function
---@param parent_id ID (internal)
---@return Suite
function TestSuite(suite_name, cb, parent_id)
  local db = debug.getinfo(cb)
  local f = db.source:sub(2)
  local id = (parent_id or ID(f)):added(suite_name)
  local s = Suite {
    name = suite_name,
    id = id,
    file = f,
    line = db.linedefined,
    children = {},
  }
  if cb then cb(s) end
  return s
end

function Suite:run(reporter, select)
  local sel = nil
  if select and not select[self.id:tostring()] then sel = select end
  if not sel then reporter.start_suite(self) end
  for i, v in ipairs(self.children) do v:run(reporter, sel) end
  if not sel then reporter.stop_suite(self) end
end

local function get_suites(path)
  local function ends_with(string, ending)
    return ending == '' or string:sub(-#ending) == ending
  end

  local function exists(file)
    local ok, err, code = os.rename(file, file)
    if not ok and code == 13 then return true end
    return ok, err
  end

  local function isdir(path) return exists(path .. '/') end

  local SEPARATOR = package.config:sub(1, 1)

  local function is_windows() return SEPARATOR == '\\' end

  local function each_file_in(directory, cb)
    local call = is_windows() and 'dir "' .. directory .. '" /b' or 'ls "' ..
                     directory .. '"'
    local pfile = io.popen(call)
    for filename in pfile:lines() do cb(directory .. SEPARATOR .. filename) end
    pfile:close()
  end

  local function each_lua_test_file(directory, cb)
    each_file_in(directory, function(filepath)
      if isdir(filepath) then
        each_lua_test_file(filepath, cb)
      elseif ends_with(filepath, '_test.lua') then
        cb(filepath)
      end
    end)
  end

  local root = Suite {
    id = ID('root'),
    name = 'FangLuaTest',
    line = -1,
    children = {},
  }
  each_lua_test_file(path, function(filepath)
    local xprint = print
    print = function() end
    local ok, suite = pcall(dofile, filepath)
    print = xprint
    if ok and suite and suite.is_suite then
      root.children[#root.children + 1] = suite
    end
  end)
  return root
end

local function json(o, newline)
  newline = newline or '\n'
  if type(o) == 'number' then
    io.write(tostring(o))
  elseif type(o) == 'string' then
    io.write('"' .. o:gsub('\n', '\\n') .. '"')
  elseif type(o) == 'table' and type(o[1]) == 'nil' then
    local start = true
    io.write('{')
    for k, v in pairs(o) do
      if not start then io.write(',') end
      start = false
      io.write('"' .. k .. '":')
      json(v, '')
    end
    io.write('}' .. newline)
  elseif type(o) == 'table' then
    io.write('[')
    for i, v in ipairs(o) do
      if i > 1 then io.write(',') end
      json(v, '')
    end
    io.write(']' .. newline)
  end
end

local VSCodeReporter = {}

function VSCodeReporter.list_suite_json(suite)
  local sss, ttt
  local function all(a)
    if #a == 0 then return nil end
    local c = {}
    for _, v in ipairs(a) do
      c[#c + 1] = v.type == 'suite' and sss(v) or ttt(v)
    end
    return c
  end
  function sss(s)
    return {
      type = 'suite',
      id = s.id:tostring(),
      label = s.name,
      line = s.line - 1,
      file = s.file,
      children = all(s.children),
    }
  end
  function ttt(t)
    return {
      type = 'test',
      id = t.id:tostring(),
      label = t.name,
      line = t.line - 1,
      file = t.file,
    }
  end
  json(sss(suite))
end
function VSCodeReporter.start_suite(s)
  json {type = 'suite', suite = s.id:tostring(), state = 'running'}
end
function VSCodeReporter.stop_suite(s)
  json {type = 'suite', suite = s.id:tostring(), state = 'completed'}
end
function VSCodeReporter.start_case(c)
  json {type = 'test', test = c.id:tostring(), state = 'running'}
end
function VSCodeReporter.stop_case(c, errors)
  local decorations = {}
  local message = {c.name .. ':'}
  for _, v in ipairs(errors) do
    message[#message + 1] = v.line .. ': ' .. v.message
    decorations[#decorations + 1] = {line = v.line - 1, message = v.message}
  end
  message = table.concat(message, '\n  ')
  json {
    type = 'test',
    test = c.id:tostring(),
    state = #errors == 0 and 'passed' or 'failed',
    message = message,
    decorations = decorations,
  }
end

local CLIReporter = {}
function CLIReporter.list_suite_json(suite)
  local sss, ttt
  local function all(a, i)
    for _, v in ipairs(a) do
      if v.type == 'suite' then
        sss(v, i)
      else
        ttt(v, i)
      end
    end
  end
  function sss(s, i)
    print(i .. '"' .. s.name .. '" {')
    all(s.children, i .. ' ')
    print(i .. '}')
  end
  function ttt(t, i) print(i .. '"' .. t.name .. '"') end
  sss(suite, '')
end
function CLIReporter.start_suite(s)
  print('\27[32m[--------] --------------------------\27[0m')
  print('\27[32m[ SUITE  ] \27[93m' .. s.name .. '\27[0m')
  print('\27[32m[--------] --------------------------\27[0m')
end
function CLIReporter.stop_suite(s)
  print('\27[32m[--------] --------------------------\27[0m')
end
function CLIReporter.start_case(c)
  print('\27[32m[ RUN    ] \27[93m' .. c.name .. '\27[0m')
end
function CLIReporter.stop_case(c, errors)
  if #errors == 0 then
    print('\27[32m[     OK ] \27[93m' .. c.name .. '\27[0m')
  else
    local message = {}
    for _, v in ipairs(errors) do
      message[#message + 1] = c.file .. ':' .. v.line .. ': ' .. v.message
    end
    print(table.concat(message, '\n'))
    print('\27[31m[ FAILED ] ' .. c.name .. '\27[0m')
  end
end

local function parse_args()
  local filter_count = 0
  local filter_as_set = {}
  local parameter = {mode = arg[1], path = arg[2]}
  for i = 3, #arg do
    local v = arg[i]
    if v:sub(1, 2) == '--' then
      parameter[v:sub(3)] = true
    else
      filter_as_set[v] = true
      filter_count = filter_count + 1
    end
  end
  return parameter, filter_count > 0 and filter_as_set or nil
end

local function main()
  local parameter, filter = parse_args()

  local reporter = parameter.vscode and VSCodeReporter or CLIReporter
  package.path = parameter.path .. '/?.lua;' .. package.path

  if parameter.mode == 'suite' then
    reporter.list_suite_json(get_suites(parameter.path))
  elseif parameter.mode == 'run' then
    get_suites(parameter.path):run(reporter, filter)
  end
end

if arg[0] == debug.getinfo(1, 'S').source:sub(2) then main() end
