local webcall = require("../webcall")

local prompt = "webcall> "

local function print_help()
    print("lua-webcall-model interactive CLI")
    print("")
    print("Commands:")
    print("  get <url>")
    print("  post <url> <body>")
    print("  request <method> <url>")
    print("  help")
    print("  quit")
    print("")
end

local function print_response(response, err)
    if err then
        print("error: " .. tostring(err))
    end

    if response then
        print("HTTP " .. tostring(response.status) .. " " .. response.method .. " " .. response.url)
        print("body: " .. tostring(#response.body) .. " bytes")
        print(response.body)
    end

    process.stdin:resume()
    io.write(prompt)
end

local function run_request(options)
    webcall.request(options, print_response)
end

local function handle(line)
    local command, first, rest = line:match("^%s*(%S+)%s*(%S*)%s*(.*)$")
    command = (command or ""):lower()

    if command == "quit" or command == "exit" then
        os.exit(0)
    elseif command == "help" then
        print_help()
        io.write(prompt)
    elseif command == "get" and first ~= "" then
        run_request({method = "GET", url = first})
    elseif command == "post" and first ~= "" then
        run_request({method = "POST", url = first, body = rest})
    elseif command == "request" and first ~= "" and rest ~= "" then
        run_request({method = first:upper(), url = rest})
    else
        print("unknown command or missing arguments; try 'help'")
        io.write(prompt)
    end
end

print("lua-webcall-model interactive CLI")
print("Type 'help' for commands or 'quit' to exit.")
io.write(prompt)
process.stdin:resume()

process.stdin:on("data", function(chunk)
    for line in tostring(chunk):gmatch("[^\r\n]+") do
        handle(line)
    end
end)

process.stdin:on("end", function()
    os.exit(0)
end)
