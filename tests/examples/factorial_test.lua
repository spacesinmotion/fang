local function factorial(number)
  if number <= 1 then return number end
  return factorial(number - 1) * number
end

local t = TestSuite('factorial_function')

function t.factorial_test()
  CHECK(factorial(1) == 1)
  CHECK(factorial(2) == 2)
  CHECK(factorial(3) == 6)
  CHECK(factorial(10) == 3628800)
end

return t
