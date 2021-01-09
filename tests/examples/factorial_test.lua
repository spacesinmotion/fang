local function factorial(number)
  if number <= 1 then return number end
  return factorial(number - 1) * number
end

local suite = TestSuite('factorial_tests')

function suite.one() CHECK(factorial(1) == 1) end

function suite.two() CHECK(factorial(2) == 2) end

function suite.three() CHECK(factorial(3) == 6) end

suite.sub = suite:SubSuite('complex')

function suite.sub.ten() CHECK(factorial(10) == 3628800) end

suite.broken = suite:SubSuite('broken')

function suite.broken.two() CHECK(factorial(2) == 42) end

return suite
