local scav = require("../webscav")

local function usage()
    print("lua-web-scav")
    print("")
    print("Usage:")
    print("  luvit cli <url> [--output <directory>] [--max-resources <number>] [--timeout <milliseconds>]")
    print("")
end

local function argument_value(arguments, index)
    return arguments[index + 1], index + 1
end

-- Luvit exposes command-line arguments through the zero-indexed global
-- args table. args[1] is the script path (cli or init.lua), so
-- application arguments begin at args[2].
local arguments = {}
for index = 2, #args do
    arguments[#arguments + 1] = args[index]
end

local url = arguments[1]
if not url or url == "--help" or url == "-h" then
    usage()
    if not url then
        os.exit(1)
    end
    os.exit(0)
end

local options = {
    output_dir = "scavenged",
    max_resources = 100,
    timeout = 10000,
}

local i = 2
while i <= #arguments do
    local parameter = arguments[i]

    if parameter == "--output" then
        options.output_dir, i = argument_value(arguments, i)
        if not options.output_dir then
            error("--output requires a directory")
        end
    elseif parameter == "--max-resources" then
        local value
        value, i = argument_value(arguments, i)
        options.max_resources = tonumber(value)
        if not options.max_resources then
            error("--max-resources requires a number")
        end
    elseif parameter == "--timeout" then
        local value
        value, i = argument_value(arguments, i)
        options.timeout = tonumber(value)
        if not options.timeout then
            error("--timeout requires milliseconds")
        end
    else
        error("unknown argument: " .. parameter)
    end

    i = i + 1
end

local crawler = scav.new(options)

crawler:on("fetch", function(fetch_url)
    print("[fetch] " .. fetch_url)
end)

crawler:on("resource", function(resource)
    print(string.format("[gathered] %s %s -> %s",
        resource.kind, resource.url, resource.path))
end)

crawler:on("error", function(err, error_url)
    print(string.format("[error] %s: %s", error_url or "", tostring(err)))
end)

crawler:on("done", function(resources)
    print("")
    print("Scavenging complete.")
    print("Resources gathered: " .. tostring(#resources))
end)

crawler:start(url)
