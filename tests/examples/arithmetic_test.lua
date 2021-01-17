return TestSuite('arithmetic_test', function(s)
  s:case('addition', function()
    CHECK(1 + 1 == 2)
    CHECK(2 + 2 == 4)
    CHECK_EQ(3 + 3, 6)
  end)

  s:case('addition_broken', function()
    CHECK(1 + 1 == 4)
    REQUIRE(2 + 2 == 2)
  end)

  s:case('assert_options', function()
    CHECK_NE(1 + 1, 22)
    CHECK_EQ(2 + 2, 4)
    CHECK_GT(2 + 2, 3)
    CHECK_LT(2 + 2, 5)
    CHECK_GE(2 + 2, 3)
    CHECK_GE(2 + 2, 4)
    CHECK_LE(2 + 2, 5)
    CHECK_LE(2 + 2, 4)
  end)

  s:case('assert_options_broken', function()
    CHECK_NE(1 + 1, 2)
    CHECK_EQ(2 + 2, 22)
    CHECK_GT(2 + 2, 4)
    CHECK_GT(2 + 2, 5)
    CHECK_LT(2 + 2, 3)
    CHECK_LT(2 + 2, 4)
    CHECK_GE(2 + 2, 5)
    CHECK_LE(2 + 2, 3)
  end)
end)
