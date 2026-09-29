local scav = require("../webscav")

local function assert_equal(actual, expected, message)
    assert(actual == expected,
        (message or "values differ")
        .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local parsed = scav.resolve_url(
    "https://example.com/archive/index.html",
    "../data/example.txt"
)
assert_equal(parsed, "https://example.com/data/example.txt", "relative URL")

parsed = scav.resolve_url(
    "https://example.com/archive/index.html",
    "/data/example.txt"
)
assert_equal(parsed, "https://example.com/data/example.txt", "root URL")

parsed = scav.resolve_url(
    "https://example.com/archive/index.html",
    "//cdn.example.com/data.txt"
)
assert_equal(parsed, "https://cdn.example.com/data.txt", "network URL")

assert_equal(
    scav.classify("https://example.com/data.txt", { ["content-type"] = "text/plain; charset=utf-8" }),
    "txt",
    "TXT content type"
)

assert_equal(
    scav.classify("https://example.com/data", { ["content-type"] = "application/json" }),
    "json",
    "JSON content type"
)

assert_equal(
    scav.classify("https://www.gutenberg.org/ebooks/2641.txt.utf-8", {}),
    "txt",
    "compound TXT extension"
)

assert_equal(
    scav.classify("https://example.com/data.txt-utf8", {}),
    "txt",
    "hyphenated TXT suffix"
)

assert_equal(
    scav.is_http_url("https://example.com/path"),
    true,
    "valid HTTP URL"
)

assert_equal(
    scav.is_http_url("https://ssl'"),
    false,
    "malformed hostname"
)

assert_equal(
    scav.is_http_url("https://example.com/{{ url }}"),
    false,
    "template URL"
)

assert_equal(
    scav.is_http_url("http://www')"),
    false,
    "malformed hostname punctuation"
)

assert_equal(
    scav.classify("https://example.com/data.txt_extra", {}),
    "txt",
    "underscored TXT suffix"
)

local discovered = scav.discover_urls(
    [[
        <a href="/one.txt">one</a>
        <a href="two.xml">two</a>
        <a href='https://example.com/three.json'>three</a>
    ]],
    "https://example.com/start/index.html"
)

local seen = {}
for _, url in ipairs(discovered) do
    seen[url] = true
end

assert_equal(seen["https://example.com/one.txt"], true, "discover root-relative URL")
assert_equal(seen["https://example.com/start/two.xml"], true, "discover relative URL")
assert_equal(seen["https://example.com/three.json"], true, "discover absolute URL")

local nearby = scav.nearby_txt_urls("https://example.com/data/report12.xml")
local nearby_seen = {}
for _, url in ipairs(nearby) do
    nearby_seen[url] = true
end

assert_equal(nearby_seen["https://example.com/data/report12.txt"], true, "extension mutation")
assert_equal(nearby_seen["https://example.com/data/report13.txt"], true, "numeric neighbor")

local crawler = scav.new()
crawler:start("https://www.example.com/index.html")

assert_equal(
    crawler:allowed_url("https://example.com/data.txt"),
    true,
    "same-site root host"
)

assert_equal(
    crawler:allowed_url("https://cdn.example.com/data.txt"),
    true,
    "same-site subdomain"
)

assert_equal(
    crawler:allowed_url("https://example.net/data.txt"),
    false,
    "cross-site URL"
)

local host_crawler = scav.new({ scope = "same-host" })
host_crawler:start("https://www.example.com/index.html")

assert_equal(
    host_crawler:allowed_url("https://example.com/data.txt"),
    false,
    "same-host rejects alternate root host"
)

assert_equal(
    host_crawler:allowed_url("https://cdn.example.com/data.txt"),
    false,
    "same-host rejects subdomain"
)

local scoped_crawler = scav.new({
    scope = "same-host",
    allowed_hosts = { "cdn.example.com" },
})
scoped_crawler:start("https://www.example.com/index.html")

assert_equal(
    scoped_crawler:allowed_url("https://cdn.example.com/data.txt"),
    true,
    "explicit allowed host"
)

local finished_reason
local limit_crawler = scav.new({ max_resources = 1 })
limit_crawler:on("done", function(_, reason)
    finished_reason = reason
end)
limit_crawler.fetched = 1
limit_crawler:step()

assert_equal(finished_reason, "max_resources", "resource limit completion")

print("web-scav tests passed")
