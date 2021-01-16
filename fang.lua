local function class(n, init)
  local class_mt = {}
  local c = setmetatable({type = n}, class_mt)
  init = init or function(...) return ... end
  function class_mt:__call(...) return setmetatable(init(...), c) end
  c.__index = c
  return c
end

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

local Test = class('test')

function Test:runner(reporter, fun, name, id)
  local current_errors = {}

  local function push_error(line, err)
    current_errors[#current_errors + 1] = {line = line, message = err}
  end

  local function add_error(e) push_error(debug.getinfo(3).currentline, e) end

  local ASSERT = {}
  local function add_assert(e)
    push_error(debug.getinfo(3).currentline, e .. ' STOP')
    error(ASSERT)
  end

  function CHECK(condition)
    if condition then return end
    add_error('condition not met \'' .. tostring(condition) .. '\'')
  end
  function REQUIRE(condition)
    if condition then return end
    add_assert('condition not met \'' .. tostring(condition) .. '\'')
  end

  local function run_test_call(fun)
    local _ENV = {}
    fun()
  end

  reporter.start_case(self)
  local ok, err = pcall(run_test_call, fun)
  if not ok and err ~= ASSERT then push_error(self.line, tostring(err)) end
  reporter.stop_case(self, current_errors)
end

function Test:run(reporter, select)
  if not select or select[self.id:tostring()] then
    self:runner(reporter, self.test_fn, self.name, self.id)
  end
end

local Suite = class('suite')

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

function Suite:SubSuite(subname, scb)
  local ss = TestSuite(subname, scb, self.id)
  self.children[#self.children + 1] = ss
  return ss
end
Suite.is_suite = true

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
  package.path = arg[#arg] .. '/?.lua;' .. package.path
  local parameter, filter = parse_args()

  local reporter = parameter.vscode and VSCodeReporter or CLIReporter

  if parameter.mode == 'suite' then
    reporter.list_suite_json(get_suites(parameter.path))
  elseif parameter.mode == 'run' then
    get_suites(parameter.path):run(reporter, filter)
  end
end

main()
