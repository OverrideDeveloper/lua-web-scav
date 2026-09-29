local webcall = require("../webcall")

local function assert_equal(actual, expected, message)
    assert(actual == expected,
        (message or "values differ")
        .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local parsed = webcall.parse_url("https://example.com:8443/api/items?q=lua#ignored")

assert_equal(parsed.scheme, "https", "scheme")
assert_equal(parsed.host, "example.com", "host")
assert_equal(parsed.port, 8443, "port")
assert_equal(parsed.path, "/api/items?q=lua", "path")

parsed = webcall.parse_url("http://localhost")

assert_equal(parsed.scheme, "http", "default scheme")
assert_equal(parsed.host, "localhost", "host")
assert_equal(parsed.port, 80, "default HTTP port")

parsed = webcall.parse_url("https://localhost/path")

assert_equal(parsed.port, 443, "default HTTPS port")

local ok = pcall(function()
    webcall.parse_url("ftp://example.com/file")
end)

assert_equal(ok, false, "unsupported schemes must fail")

print("webcall tests passed")
