local depends = require 'depends'

return TestSuite('depends_test', function(s)
  s:case('ok', function()
    CHECK(depends)
    CHECK_EQ(depends.key, 'value')
  end)

  s:case('fail', function()
    CHECK(depends)
    CHECK_EQ(depends.key, 'not value')
  end)
end)
