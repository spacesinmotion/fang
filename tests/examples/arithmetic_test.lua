local suite = TestSuite('arithmetic_test')

function suite.addition()
  CHECK(1 + 1 == 2)
  CHECK(2 + 2 == 4)
end

function suite.addition_broken()
  CHECK(1 + 1 == 4)
  CHECK(2 + 2 == 2)
end

return suite
