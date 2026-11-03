-- lua-web-scav
-- A small web resource scavenger built on lua-webcall-model.

local fs = require("fs")
local webcall = require("./vendor/lua-webcall-model/webcall")

local M = {}

local RESOURCE_EXTENSIONS = {
    txt = "txt",
    xml = "xml",
    json = "json",
    rdf = "xml",
    opds = "xml",
}

local CONTENT_TYPES = {
    ["text/plain"] = "txt",
    ["text/xml"] = "xml",
    ["application/xml"] = "xml",
    ["application/rdf+xml"] = "xml",
    ["application/atom+xml"] = "xml",
    ["application/json"] = "json",
    ["text/json"] = "json",
}

local function lower(value)
    return type(value) == "string" and value:lower() or ""
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function extension(url)
    local path = (url or ""):match("^([^?#]*)") or ""
    local value = path:match("%.([%w]+)$")
    return value and value:lower() or nil
end

local function classify_extension(url)
    local path = lower((url or ""):match("^([^?#]*)") or "")

    -- Some resource endpoints add a format or encoding suffix after the
    -- actual resource extension, e.g. Gutenberg's .txt.utf-8.
    for resource_extension, kind in pairs(RESOURCE_EXTENSIONS) do
        if path:match("%." .. resource_extension .. "[%._-]")
            or path:match("%." .. resource_extension .. "$") then
            return kind
        end
    end

    return RESOURCE_EXTENSIONS[extension(url)]
end

local function classify(url, headers)
    local content_type = lower(headers and (headers["content-type"] or headers["Content-Type"]))
    content_type = content_type:match("^([^;]+)") or content_type

    if CONTENT_TYPES[content_type] then
        return CONTENT_TYPES[content_type]
    end

    return classify_extension(url)
end

local function strip_fragment(url)
    return (url or ""):match("^([^#]*)") or url
end

local function split_url(url)
    local scheme, authority, path = url:match("^([%a][%w+.-]*)://([^/]+)(.*)$")
    if not scheme then
        return nil
    end

    return scheme, authority, path == "" and "/" or path
end

local function normalize_path(path)
    local query = ""
    local base = path

    local q = path:find("?", 1, true)
    if q then
        base = path:sub(1, q - 1)
        query = path:sub(q)
    end

    local parts = {}
    for part in base:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 then
                table.remove(parts)
            end
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end

    local result = "/" .. table.concat(parts, "/")
    if base:sub(-1) == "/" and result ~= "/" then
        result = result .. "/"
    end

    return result .. query
end

local function resolve_url(base_url, target)
    target = trim(strip_fragment(target))

    if target == "" then
        return nil
    end

    if target:match("^[%a][%w+.-]*:") then
        if target:match("^https?://") then
            return target
        end
        return nil
    end

    local scheme, authority, base_path = split_url(base_url)
    if not scheme then
        return nil
    end

    -- A query-only reference addresses the current document, not its directory.
    if target:sub(1, 1) == "?" then
        return scheme .. "://" .. authority .. base_path:gsub("%?.*$", "") .. target
    end

    if target:sub(1, 2) == "//" then
        return scheme .. ":" .. target
    end

    if target:sub(1, 1) == "/" then
        return scheme .. "://" .. authority .. normalize_path(target)
    end

    local directory = base_path:match("^(.*)/") or ""
    return scheme .. "://" .. authority .. normalize_path(directory .. "/" .. target)
end

local function authority_host(url)
    local _, authority = split_url(url)
    if not authority or authority:find("@", 1, true) then
        return nil
    end

    if authority:sub(1, 1) == "[" then
        return nil
    end

    local host = authority
    local port = authority:match("^(.+):(%d+)$")
    if port then
        host = authority:match("^(.+):%d+$")
    elseif authority:find(":", 1, true) then
        return nil
    end

    if not host
        or host == ""
        or host:match("[^%w%._%-]")
        or host:match("^%.")
        or host:match("%.$")
        or host:match("%.%.") then
        return nil
    end

    return lower(host)
end

local function is_http_url(url)
    if type(url) ~= "string"
        or url:find("[%c%s]")
        or url:find("{{", 1, true)
        or url:find("}}", 1, true) then
        return false
    end

    if not url:match("^https?://") then
        return false
    end

    return authority_host(url) ~= nil
end

local function unique_append(list, seen, value)
    if value and not seen[value] then
        seen[value] = true
        list[#list + 1] = value
    end
end

local function discover_urls(body, base_url)
    local results = {}
    local seen = {}

    local function add(value)
        value = value:gsub("&amp;", "&")
        local resolved = resolve_url(base_url, value)
        if is_http_url(resolved) then
            unique_append(results, seen, resolved)
        end
    end

    for value in body:gmatch("[Hh][Rr][Ee][Ff]%s*=%s*[\"']([^\"']+)[\"']") do
        add(value)
    end

    for value in body:gmatch("[Ss][Rr][Cc]%s*=%s*[\"']([^\"']+)[\"']") do
        add(value)
    end

    for value in body:gmatch("[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]%s*=%s*[\"']([^\"']+)[\"']") do
        add(value)
    end

    for value in body:gmatch("[Ll][Oo][Cc]%s*=%s*[\"']([^\"']+)[\"']") do
        add(value)
    end

    -- Common download and embedded-resource attributes.
    for _, attribute in ipairs({ "data%-href", "data%-url", "action", "poster", "formaction" }) do
        local pattern = attribute .. "%s*=%s*[\"']([^\"']+)[\"']"
        for value in body:gmatch(pattern) do
            add(value)
        end
    end

    -- srcset contains comma-separated URL/descriptor pairs.
    for value in body:gmatch("[Ss][Rr][Cc][Ss][Ee][Tt]%s*=%s*[\"']([^\"']+)[\"']") do
        for candidate in value:gmatch("[^,]+") do
            add(trim(candidate):match("^(%S+)"))
        end
    end

    for value in body:gmatch("https?://[%w%-%._~:/%?#%[%]@!$&'()*+,;=%%]+") do
        add(value)
    end

    return results
end

local function nearby_txt_urls(url)
    local results = {}
    local seen = {}

    local scheme, authority, path = split_url(url)
    if not scheme then
        return results
    end

    local query = path:match("(%?.*)$") or ""
    local clean_path = path:gsub("%?.*$", "")
    local directory = clean_path:match("^(.*)/") or ""
    local filename = clean_path:match("([^/]+)$") or ""
    local stem = filename:gsub("%.[^%.]+$", "")

    local function add(path_value)
        local candidate = scheme .. "://" .. authority .. normalize_path(path_value)
        if not seen[candidate] then
            seen[candidate] = true
            results[#results + 1] = candidate
        end
    end

    if filename ~= "" then
        if not filename:match("%.txt$") then
            add(clean_path:gsub("%.[^%.]+$", "") .. ".txt" .. query)
        end

        add(clean_path .. ".txt" .. query)
    end

    if directory ~= "" then
        add(directory .. "/index.txt")
    end

    local prefix, value = stem:match("^(.-)(%d+)$")
    local number = tonumber(value)
    if number then
        add(directory .. "/" .. prefix .. tostring(number + 1) .. ".txt" .. query)
        if number > 0 then
            add(directory .. "/" .. prefix .. tostring(number - 1) .. ".txt" .. query)
        end
    end

    return results
end

local function sanitize_filename(url, kind)
    local value = url:gsub("^https?://", "")
    value = value:gsub("[^%w%._%-]+", "_")
    value = value:gsub("_+", "_")
    value = value:gsub("^_+", ""):gsub("_+$", "")

    if value == "" then
        value = "resource"
    end

    return value .. "." .. kind
end

local function mkdir(path, callback)
    fs.mkdir(path, function(err)
        -- Luvit/OS error codes may be uppercase (for example EEXIST).
        -- Normalize before checking so repeated scavenging runs can reuse
        -- their output directory.
        local message = err and lower(tostring(err)) or ""
        if not err or message:find("exist", 1, true) then
            callback()
            return
        end

        callback(err)
    end)
end

local function write_resource(output_dir, url, kind, body, callback)
    mkdir(output_dir, function(err)
        if err then
            callback(nil, err)
            return
        end

        local path = output_dir .. "/" .. sanitize_filename(url, kind)
        fs.writeFile(path, body, function(write_err)
            if write_err then
                callback(nil, write_err)
                return
            end

            callback(path)
        end)
    end)
end

local Scavenger = {}
Scavenger.__index = Scavenger

function Scavenger:on(event, callback)
    assert(type(callback) == "function", "callback must be a function")
    self.listeners[event] = self.listeners[event] or {}
    self.listeners[event][#self.listeners[event] + 1] = callback
    return self
end

function Scavenger:emit(event, ...)
    for _, callback in ipairs(self.listeners[event] or {}) do
        callback(...)
    end
end

function Scavenger:finish(reason)
    if self.done_emitted then return false end
    self.stop_reason = reason or self.stop_reason or "exhausted"
    self.stopped = true
    if (self.pending_writes or 0) > 0 then
        self.finish_pending = true
        return true
    end
    self.done_emitted = true
    self:emit("done", self.resources, self.stop_reason)
    return true
end

function Scavenger:write_finished()
    self.pending_writes = math.max(0, (self.pending_writes or 0) - 1)
    if self.stopped and self.finish_pending and self.pending_writes == 0 then
        self.finish_pending = false
        self:finish(self.stop_reason)
    end
end

function Scavenger:allowed_url(url)
    if not is_http_url(url) then
        return false
    end

    if self.scope == "any" then
        return true
    end

    local host = authority_host(url)
    if not host then
        return false
    end

    if self.allowed_hosts[host] then
        return true
    end

    if self.scope == "same-host" then
        return host == self.site_host
    end

    if self.scope == "same-site" then
        return host == self.site_domain
            or host:sub(-( #self.site_domain + 1)) == "." .. self.site_domain
    end

    return false
end

function Scavenger:enqueue(url)
    url = strip_fragment(url)

    if not self:allowed_url(url) or self.queued[url] then
        return false
    end

    self.queued[url] = true
    self.queue[#self.queue + 1] = url
    return true
end

function Scavenger:enqueue_priority(url)
    url = strip_fragment(url)

    if not self:allowed_url(url) or self.queued[url] then
        return false
    end

    -- Redirect destinations must be followed before unrelated links discovered
    -- on the source page. Otherwise a slow/large asset later in the FIFO queue
    -- can prevent the actual document from ever being gathered.
    self.queued[url] = true
    table.insert(self.queue, self.position, url)
    return true
end

local IGNORED_EXTENSIONS = {
    css = true, ico = true, png = true, jpg = true, jpeg = true,
    gif = true, svg = true, webp = true, bmp = true, tif = true,
    tiff = true, avif = true,
    epub = true, mobi = true, azw = true, azw3 = true, kf8 = true,
    mp3 = true, mp4 = true, m4a = true, wav = true, ogg = true,
    webm = true, zip = true, gz = true, tar = true, pdf = true,
    woff = true, woff2 = true, ttf = true, otf = true, eot = true,
}

function Scavenger:enqueue_discovered(url)
    url = strip_fragment(url)
    if not self:allowed_url(url) or self.queued[url] then
        return false
    end

    local path = (url:match("^([^?#]*)") or ""):lower()

    -- Download-provider endpoints and EPUB package variants are not useful
    -- to this TXT/XML/JSON scavenger, and can be very large.
    if path:find("/send/", 1, true)
        or path:find("%.epub", 1, true)
        or path:find("%.kf8", 1, true)
        or path:find("%.mobi", 1, true) then
        return false
    end

    local ext = extension(url)
    if ext and not classify_extension(url) then
        return false
    end
    if ext and IGNORED_EXTENSIONS[ext] then
        return false
    end

    -- Put known gatherable formats ahead of extensionless HTML navigation.
    if classify_extension(url) then
        return self:enqueue_priority(url)
    end

    return self:enqueue(url)
end

function Scavenger:next()
    if self.position > #self.queue then
        return nil
    end

    local url = self.queue[self.position]
    self.position = self.position + 1
    return url
end

function Scavenger:fetch(url, callback)
    self:emit("fetch", url)

    webcall.get(url, {
        timeout = self.timeout,
        headers = self.headers,
    }, function(response, err)
        callback(response, err)
    end)
end

function Scavenger:collect(url, response, kind)
    local resource = {
        url = url,
        source_url = url,
        kind = kind,
        status = response.status,
        content_type = response.headers and (response.headers["content-type"] or response.headers["Content-Type"]),
        body = response.body,
    }

    self.pending_writes = (self.pending_writes or 0) + 1
    write_resource(self.output_dir, url, kind, response.body, function(path, err)
        if err then
            resource.error = err
            self:emit("error", err, url)
        else
            resource.path = path
            self.resources[#self.resources + 1] = resource
            self:emit("resource", resource)
        end
        self:write_finished()
    end)
end

function Scavenger:process(url, response, err)
    if err and not response then
        self:emit("error", err, url)
        return
    end

    if not response then
        self:emit("error", "empty response", url)
        return
    end

    self:emit("response", response, err)

    local status = tonumber(response.status) or 0
    if status >= 300 and status < 400 then
        local location = response.headers
            and (response.headers["location"] or response.headers["Location"])

        local redirect = location and resolve_url(url, location)
        if redirect then
            self:enqueue_priority(redirect)
        else
            self:emit("error", "redirect response did not include a usable Location header", url)
        end
        return
    end

    if status < 200 or status >= 300 then
        self:emit("error", err or ("HTTP status " .. tostring(status)), url)
        return
    end

    local kind = classify(url, response.headers)
    if kind then
        self:collect(url, response, kind)

        -- Resource bodies can themselves contain paths to more resources.
        -- Keep discovery separate from collection so XML/JSON/TXT can all
        -- participate in the next scavenging step.
        for _, discovered in ipairs(discover_urls(response.body or "", url)) do
            self:enqueue_discovered(discovered)
        end

        if kind == "txt" then
            for _, candidate in ipairs(self.mutate(url, response) or {}) do
                self:enqueue(candidate)
            end
        end

        return
    end

    for _, discovered in ipairs(discover_urls(response.body or "", url)) do
        self:enqueue_discovered(discovered)
    end
end

function Scavenger:step()
    if self.stopped then
        return false
    end

    if self.fetched >= self.max_resources then
        self:finish("max_resources")
        return false
    end

    local url = self:next()
    if not url then
        self:finish("exhausted")
        return false
    end

    self.fetched = self.fetched + 1
    self:fetch(url, function(response, err)
        self:process(url, response, err)
        self:step()
    end)

    return true
end

function Scavenger:start(url)
    assert(is_http_url(url), "start URL must be an http:// or https:// URL")

    local host = authority_host(url)
    self.site_host = host
    self.site_domain = host:gsub("^www%.", "")
    self.stopped = false
    self.done_emitted = false
    self.finish_pending = false
    self.stop_reason = nil
    self.pending_writes = 0
    self:enqueue(url)
    self:step()
    return self
end

function Scavenger:stop()
    self:finish("stopped")
    return self
end

function M.new(options)
    options = options or {}

    local scope = options.scope or "same-site"
    assert(
        scope == "same-site" or scope == "same-host" or scope == "any",
        "scope must be same-site, same-host, or any"
    )

    local allowed_hosts = options.allowed_hosts or {}
    local allowed_host_set = {}

    for _, host in ipairs(allowed_hosts) do
        host = lower(host):gsub("^https?://", "")
        allowed_host_set[host] = true
    end

    return setmetatable({
        output_dir = options.output_dir or "scavenged",
        timeout = options.timeout or 10000,
        max_resources = options.max_resources or 100,
        headers = options.headers,
        mutate = options.mutate or nearby_txt_urls,

        scope = scope,
        allowed_hosts = allowed_host_set,
        site_host = nil,
        site_domain = nil,

        queue = {},
        position = 1,
        queued = {},
        fetched = 0,
        resources = {},
        pending_writes = 0,
        finish_pending = false,
        done_emitted = false,
        stopped = false,
        listeners = {},
    }, Scavenger)
end

M.classify = classify
M.discover_urls = discover_urls
M.is_http_url = is_http_url
M.authority_host = authority_host
M.nearby_txt_urls = nearby_txt_urls
M.resolve_url = resolve_url

return M
