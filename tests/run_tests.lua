local function exec_fang(args)
  local a = table.concat(args, ' ')
  print('fang ' .. a)
  os.execute('lua fang.lua ' .. a)
  print('')
end

exec_fang({'suite', 'tests/'})
exec_fang({'run', 'tests/'})
