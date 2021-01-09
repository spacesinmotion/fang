local function factorial(number)
  if number <= 1 then return number end
  return factorial(number - 1) * number
end

local suite = TestSuite('factorial_tests')

suite:case('one', function() CHECK(factorial(1) == 1) end)

suite:case('two', function() CHECK(factorial(2) == 2) end)

suite:case('three', function() CHECK(factorial(3) == 6) end)

suite.sub = suite:SubSuite('complex')

suite.sub:case('ten', function() CHECK(factorial(10) == 3628800) end)

suite.broken = suite:SubSuite('broken')

suite.broken:case('two', function() CHECK(factorial(2) == 42) end)

return suite
