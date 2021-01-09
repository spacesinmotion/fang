local function class(n, init)
  local class_mt = {}
  local c = setmetatable({type = n}, class_mt)
  function class_mt:__call(...) return init(setmetatable(init(...), c)) end
  c.__index = c
  return c
end

local ID = {}
ID.__index = ID
function ID.new(r) return setmetatable({r}, ID) end
function ID:added(p)
  local r = setmetatable({table.unpack(self)}, ID)
  r[#r + 1] = p
  return r
end
function ID:tostring() return table.concat(self, '::') end

local function json_object(o, ...)
  io.write('{')
  for i, k in ipairs(...) do
    if o[k] then
      if i > 1 then io.write(',') end
      io.write('"' .. k .. '":')
      if type(o[k]) == 'string' then
        io.write('"' .. o[k]:gsub('\n', '\\n') .. '"')
      end
      if type(o[k]) == 'number' then io.write(tostring(o[k])) end
      if type(o[k]) == 'table' then
        io.write('[')
        local sub = o[k]
        for j = 1, #sub do
          if j > 1 then io.write(',') end
          sub[j]:list_suite_json()
        end
        io.write(']')
      end
    end
  end
  io.write('}')
end

local RunState = class('RunState', function(...) return ... end)
function RunState.test(id, state)
  return RunState {type = 'test', test = id, state = state}
end
function RunState.suite(id, state)
  return RunState {type = 'suite', suite = id, state = state}
end
function RunState:set_errors(name, errors)
  self.decorations = errors
  if #errors == 0 then return self end
  self.message = name .. ':\n  '
  for _, v in ipairs(errors) do
    v.list_suite_json = function(self)
      return json_object(self, {'line', 'message'})
    end
    self.message = self.message .. v.line + 1 .. ': ' .. v.message .. '\n  '
  end
  return self
end
function RunState:json_out()
  print(
      json_object(self, {'type', self.type, 'state', 'message', 'decorations'}))
end

local Test = class('test', function(...) return ... end)

function Test:list_suite_json()
  json_object(self, {'type', 'id', 'label', 'line', 'file', 'tooltip'})
end

function Test:runner(fun, name, id)
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

  RunState.test(id, 'running'):json_out()
  local ok, err = pcall(run_test_call, fun)
  if not ok and err ~= ASSERT then push_error(0, tostring(err)) end
  RunState.test(id, #current_errors == 0 and 'passed' or 'failed'):set_errors(
      name, current_errors):json_out()
end
function Test:run(select)
  if not select or select[self.id] then
    self:runner(self.test_fn, self.name, self.id)
  end
end

local Suite = class('suite', function(...) return ... end)

function Suite:case(case_name, fn)
  local db = debug.getinfo(fn)
  self.children[#self.children + 1] = Test {
    idx = self.idx:added(case_name),
    id = self.idx:added(case_name):tostring(),
    file = self.file,
    line = db.linedefined - 1,
    name = case_name,
    label = case_name,
    test_fn = fn,
  }
end

function Suite:SubSuite(subname, scb)
  local ss = TestSuite(subname, scb, self.idx)
  self.children[#self.children + 1] = ss
  return ss
end

function Suite:list_suite_json()
  json_object(self,
              {'type', 'id', 'label', 'line', 'file', 'tooltip', 'children'})
end
Suite.is_suite = true

function TestSuite(suite_name, cb, parent_id)
  local db = debug.getinfo(cb)
  local f = db.source:sub(2)
  local idx = (parent_id or ID.new(f)):added(suite_name)
  local s = Suite {
    idx = idx,
    id = idx:tostring(),
    children = {},
    label = suite_name,
    name = suite_name,
    file = f,
    line = db.linedefined - 1,
  }
  if cb then cb(s) end
  return s
end

function Suite:run(select)
  local sel = nil
  if select and not select[self.id] then sel = select end
  if not sel then RunState.suite(self.id, 'running'):json_out() end
  for i, v in ipairs(self.children) do v:run(sel) end
  if not sel then RunState.suite(self.id, 'completed'):json_out() end
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

  local root = Suite {id = 'root', label = 'FangLuaTest', children = {}}
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

local function main()
  package.path = arg[#arg] .. '/?.lua;' .. package.path
  if arg[1] == 'suite' then
    get_suites(arg[2]):list_suite_json()
  elseif arg[1] == 'run' then
    local as_set = #arg > 2 and {}
    for i = 3, #arg do as_set[arg[i]] = true end
    get_suites(arg[2]):run(as_set)
  end
end

main()
