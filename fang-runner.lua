local fang = require 'fang'

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

  each_lua_test_file(path, function(filepath)
    local xprint = print
    print = function() end
    local ok, suite = pcall(dofile, filepath)
    print = xprint
    if ok and suite and suite.is_suite then
      fang.children[#fang.children + 1] = suite
    end
  end)
  return fang
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

main()
