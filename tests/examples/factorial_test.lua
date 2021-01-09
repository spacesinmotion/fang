local function factorial(number)
  if number <= 1 then return number end
  return factorial(number - 1) * number
end

return TestSuite('factorial_tests', function(s)

  s:case('one', function() CHECK(factorial(1) == 1) end)

  s:case('two', function() CHECK(factorial(2) == 2) end)

  s:case('three', function() CHECK(factorial(3) == 6) end)

  s:SubSuite('complex', function(ss)
    ss:case('ten', function() CHECK(factorial(10) == 3628800) end)
  end)

  s:SubSuite('broken', function(b)
    b:case('two', function() CHECK(factorial(2) == 42) end)
  end)
end)
