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

  local function get_line()
    local text = debug.traceback()
    local i = 0
    for s in text:gmatch('[^\r\n]+') do
      i = i + 1
      if i == 5 then
        local b = s:find(':', 4) + 1
        local e = s:find(':', b) - 1
        return tonumber(s:sub(b, e)) + 1
      end
    end
    return 666
  end

  local function push_error(line, err)
    current_errors[#current_errors + 1] = {line = line - 1, message = err}
  end

  local function add_error(e) push_error(get_line(), e) end

  local ASSERT = {}
  local function add_assert(e)
    push_error(get_line(), e .. ' STOP')
    error(ASSERT)
  end

  function CHECK(condition)
    if condition then return end
    add_error('not true')
  end
  function REQUIRE(condition)
    if condition then return end
    add_assert('not true')
  end

  local function run_test_call(fun)
    local _ENV = {}
    fun()
  end

  reporter.start_case(self)
  local ok, err = pcall(run_test_call, fun)
  if not ok and err ~= ASSERT then push_error(0, tostring(err)) end
  reporter.stop_case(self, current_errors)
end

function Test:run(reporter, select)
  if not select or select[self.id] then
    self:runner(reporter, self.test_fn, self.name, self.id)
  end
end

local Suite = class('suite')

function Suite:case(case_name, fn)
  local db = debug.getinfo(fn)
  self.children[#self.children + 1] = Test {
    idx = self.idx:added(case_name),
    id = self.idx:added(case_name):tostring(),
    file = self.file,
    line = db.linedefined - 1,
    name = case_name,
    test_fn = fn,
  }
end

function Suite:SubSuite(subname, scb)
  local ss = TestSuite(subname, scb, self.idx)
  self.children[#self.children + 1] = ss
  return ss
end
Suite.is_suite = true

function TestSuite(suite_name, cb, parent_id)
  local db = debug.getinfo(cb)
  local f = db.source:sub(2)
  local idx = (parent_id or ID(f)):added(suite_name)
  local s = Suite {
    idx = idx,
    id = idx:tostring(),
    children = {},
    name = suite_name,
    file = f,
    line = db.linedefined - 1,
  }
  if cb then cb(s) end
  return s
end

function Suite:run(reporter, select)
  local sel = nil
  if select and not select[self.id] then sel = select end
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

  local root = Suite {idx = ID('root'), name = 'FangLuaTest', children = {}}
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
    local c = {}
    for _, v in ipairs(a) do
      c[#c + 1] = v.type == 'suite' and sss(v) or ttt(v)
    end
    return c
  end
  function sss(s)
    return {
      type = 'suite',
      id = s.idx:tostring(),
      label = s.name,
      line = s.line,
      file = s.file,
      children = all(s.children),
    }
  end
  function ttt(t)
    return {
      type = 'test',
      id = t.idx:tostring(),
      label = t.name,
      line = t.line,
      file = t.file,
    }
  end
  json(sss(suite))
end
function VSCodeReporter.start_suite(s)
  json {type = 'suite', suite = s.idx:tostring(), state = 'running'}
end
function VSCodeReporter.stop_suite(s)
  json {type = 'suite', suite = s.idx:tostring(), state = 'completed'}
end
function VSCodeReporter.start_case(c)
  json {type = 'test', test = c.idx:tostring(), state = 'running'}
end
function VSCodeReporter.stop_case(c, errors)
  local function m()
    local message = c.name .. ':\n  '
    for _, v in ipairs(errors) do
      message = message .. v.line + 1 .. ': ' .. v.message .. '\n  '
    end
    return message
  end
  json {
    type = 'test',
    test = c.idx:tostring(),
    state = #errors == 0 and 'passed' or 'failed',
    message = m(),
    decorations = errors,
  }
end

local function main()
  package.path = arg[#arg] .. '/?.lua;' .. package.path
  if arg[1] == 'suite' then
    VSCodeReporter.list_suite_json(get_suites(arg[2]))
  elseif arg[1] == 'run' then
    local as_set = #arg > 2 and {}
    for i = 3, #arg do as_set[arg[i]] = true end
    get_suites(arg[2]):run(VSCodeReporter, as_set)
  end
end

main()
