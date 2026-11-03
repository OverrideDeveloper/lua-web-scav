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

local selective_crawler = scav.new()
selective_crawler.site_host = "www.gutenberg.org"
selective_crawler.site_domain = "gutenberg.org"
assert_equal(
    selective_crawler:enqueue_discovered("https://www.gutenberg.org/ebooks/75948.txt.utf-8"),
    true,
    "enqueue supported TXT resource"
)
assert_equal(
    selective_crawler:enqueue_discovered("https://www.gutenberg.org/ebooks/75948.epub3.images"),
    false,
    "skip EPUB image package"
)
assert_equal(
    selective_crawler:enqueue_discovered("https://www.gutenberg.org/ebooks/send/gdrive/75948.epub3.images"),
    false,
    "skip download-provider endpoint"
)
assert_equal(
    selective_crawler:enqueue_discovered("https://www.gutenberg.org/gutenberg/globals.css"),
    false,
    "skip stylesheet"
)
assert_equal(
    selective_crawler:enqueue_discovered("https://www.gutenberg.org/about/"),
    true,
    "retain extensionless HTML navigation"
)
assert_equal(
    selective_crawler:enqueue_discovered("https://www.gutenberg.org/ebooks/75948.opds"),
    true,
    "retain supported OPDS XML feed"
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

-- A redirect must be processed before unrelated URLs already waiting in the
-- discovery queue (for example, Gutenberg's EPUB image endpoints).
local redirect_crawler = scav.new()
redirect_crawler.site_host = "www.gutenberg.org"
redirect_crawler.site_domain = "gutenberg.org"
redirect_crawler.queue = {
    "https://www.gutenberg.org/ebooks/75948.txt.utf-8",
    "https://www.gutenberg.org/ebooks/75948.epub.images",
}
redirect_crawler.queued = {
    ["https://www.gutenberg.org/ebooks/75948.txt.utf-8"] = true,
    ["https://www.gutenberg.org/ebooks/75948.epub.images"] = true,
}
redirect_crawler.position = 2
redirect_crawler:process(
    "https://www.gutenberg.org/ebooks/75948.txt.utf-8",
    {
        status = 302,
        headers = {
            location = "/cache/epub/75948/pg75948.txt",
        },
        body = "",
    },
    "HTTP request failed with status 302"
)
assert_equal(
    redirect_crawler:next(),
    "https://www.gutenberg.org/cache/epub/75948/pg75948.txt",
    "redirect target takes priority over queued assets"
)
assert_equal(
    redirect_crawler:next(),
    "https://www.gutenberg.org/ebooks/75948.epub.images",
    "queued assets remain after redirect target"
)

assert_equal(
    scav.resolve_url("https://example.com/catalog/page.html?old=1", "?download=1"),
    "https://example.com/catalog/page.html?download=1",
    "query-only URL"
)

local extra_discovered = scav.discover_urls(
    [[
        <a data-href="/download/book.txt">download</a>
        <img srcset="/images/cover.jpg 1x, /images/cover@2x.jpg 2x">
        <form action="../export.xml"></form>
    ]],
    "https://example.com/catalog/index.html"
)
local extra_seen = {}
for _, url in ipairs(extra_discovered) do extra_seen[url] = true end
assert_equal(extra_seen["https://example.com/download/book.txt"], true, "discover data-href")
assert_equal(extra_seen["https://example.com/images/cover.jpg"], true, "discover first srcset URL")
assert_equal(extra_seen["https://example.com/images/cover@2x.jpg"], true, "discover second srcset URL")
assert_equal(extra_seen["https://example.com/export.xml"], true, "discover form action")

print("web-scav tests passed")
