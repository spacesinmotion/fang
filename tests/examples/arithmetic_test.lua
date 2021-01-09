local suite = TestSuite('arithmetic_test', function(s)

  s:case('addition', function()
    CHECK(1 + 1 == 2)
    CHECK(2 + 2 == 4)
  end)

  s:case('addition_broken', function()
    CHECK(1 + 1 == 4)
    CHECK(2 + 2 == 2)
  end)
end)
return suite
