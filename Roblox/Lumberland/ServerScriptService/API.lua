if script.Parent ~= game.ServerScriptService and script.Parent ~= game.ServerStorage then
    return error("THIS MODULE MUST BE LOCATED EXCLUSIVELY ON THE SERVER - PUT IT UNDER ServerScriptService OR ServerStorage")
end

-- externals
local HttpService = game:GetService("HttpService")
local Modules = require(script:WaitForChild("Modules"))
local LOG_HTTP_IO = game:GetService("RunService"):IsStudio()

-- utils
local HTTP_REQUESTS_SENT_IN_LAST_60_SECONDS = 0
local function httpRateLimit()
    while HTTP_REQUESTS_SENT_IN_LAST_60_SECONDS > 450 do
        task.wait(0.1)
    end
    
    HTTP_REQUESTS_SENT_IN_LAST_60_SECONDS += 1
    task.delay(60, function()
        HTTP_REQUESTS_SENT_IN_LAST_60_SECONDS -= 1
    end)
end

local requestIndex = 0
local function makeRequest(args_dict)
    local me = requestIndex
    requestIndex += 1
    
    local logstr = ("[API REQUEST %d] %s %s"):format(me, args_dict.Method, args_dict.Url)
    if LOG_HTTP_IO then
        print(logstr, args_dict)
    else
        print(logstr)
    end
    
    httpRateLimit()
    local httpSuccess, httpResponse = pcall(HttpService.RequestAsync, HttpService, args_dict)
    
    if not httpSuccess then
        print(("[API REQUEST %d] RequestAsync pcall failed w/ error: %s"):format(me, httpResponse))
        return false, "HTTP error: " .. httpResponse, nil
    end

    if not httpResponse.Success then -- response.StatusCode not on [200, 299]
        print(("[API REQUEST %d] Failed with status code %d"):format(me, httpResponse.StatusCode))
        return false, (
            "Bad HTTP Response Code %d. Response: %s"
        ):format(
            httpResponse.StatusCode,
            httpResponse.Body
        ), httpResponse.StatusCode
    end

    local jsonDecodeSuccess, jsonDecodeResponse = pcall(HttpService.JSONDecode, HttpService, httpResponse.Body)
    if not jsonDecodeSuccess then
        print(("[API REQUEST %d] JSON decode error: %s"):format(me, jsonDecodeResponse))
        return false, "Non-JSON response: " .. httpResponse.Body, httpResponse.StatusCode
    end
    
    local logstr = ("[API REQUEST %d] Succeeded with status code %d"):format(me, httpResponse.StatusCode)
    if LOG_HTTP_IO then
        print(logstr, jsonDecodeResponse)
    else
        print(logstr)
    end

    return true, jsonDecodeResponse, httpResponse.StatusCode, httpResponse
end

-- POST, PATCH, PUT, DELETE
local function genericJSONBodyRequest(self, method, data, headers, useToken)
    data = data or {}

    headers = headers or {}
    if not headers["Content-Type"] then
        headers["Content-Type"] = "application/json"
    end
    headers = Modules.Config.addGenericHeaders(headers)
    if useToken ~= false then
        headers = Modules.Config.addAuthenticationHeaders(headers)
    end

    local urlCopy = self.url:copy()
    urlCopy:normalize()

    local jsonEncodeSuccess, jsonEncodeResponse = pcall(HttpService.JSONEncode, HttpService, data)
    if not jsonEncodeSuccess then
        return false, "JSON encoding error: " .. jsonEncodeResponse, nil
    end

    return makeRequest({
        Method = method,
        Url = urlCopy:build(),
        Headers = headers,
        Body = jsonEncodeResponse
    })
end

--[[
    Setup HTTP methods, case insensitive
    
    get/post/... sends a get or post request to the url
    pget/ppost/... first call config.addPlayerHeaders then forward to :get or :post
    eget/epost/epget/eppost/... are equivalent to above, except they throw errors instead of returning them
    cget/cpget/cepget/... entire call happens in a coroutine; use if you don't care about the response
    note: if using `c` versions, then you should also add the `e` flag so that errors are output in console
    
    These methods are supported:
        GET, POST, PATCH, PUT, DELETE
]]--
local HTTPMethods = {}

function HTTPMethods:get(data, headers, useToken)
    data = data or {}
    
    headers = Modules.Config.addGenericHeaders(headers or {})
    if useToken ~= false then
        headers = Modules.Config.addAuthenticationHeaders(headers)
    end
    
    local urlCopy = self.url:copy()
    urlCopy:normalize()
    urlCopy:setQuery(data)
    
    return makeRequest({
        Method = "GET",
        Url = urlCopy:build(),
        Headers = headers
    })
end

for _, method in pairs({"post", "patch", "put", "delete"}) do
    HTTPMethods[method:lower()] = function(self, ...)
        return genericJSONBodyRequest(self, method:upper(), ...)
    end
end

-- add player variations
for name, func in pairs(table.clone(HTTPMethods)) do
    HTTPMethods["p" .. name] = function(self, plr, data, headers, useToken)
        if type(plr) == "table" and typeof(plr.instance) == "Instance" and plr.instance:IsA("Player") then
            plr = plr.instance
        elseif typeof(plr) ~= "Instance" or not plr:IsA("Player") then
            error(":p" .. name .. "() requires you pass a Player as the first argument. Got '" .. type(plr) .. "' instead.")
        end
        
        headers = Modules.Config.addPlayerHeaders(headers or {}, plr)
        return func(self, data, headers, useToken)
    end
end

-- add erroneous variations
for name, func in pairs(table.clone(HTTPMethods)) do
    HTTPMethods["e" .. name] = function(...)
        local success, response, statusCode = func(...)
        if not success then
            error(response)
        end
        
        return response, statusCode
    end
end

-- add coroutine versions
for name, func in pairs(table.clone(HTTPMethods)) do
    HTTPMethods["c" .. name] = function(...)
        task.defer(func, ...)
    end
end

setmetatable(HTTPMethods, {
    __index = function(t, key)
        if type(key) == "string" then
            key = key:lower()
        end
        return rawget(t, key)
    end
})

--[[
    The metatable that makes the magic happen
]]--
local mt
mt = {
    __div = function(t, a)
        return setmetatable({
            url = t.url / a
        }, mt)
    end,
    
    __index = HTTPMethods
}

--[[
    Constructs the base endpoint, divide this object to create new ones
]]--
local API = setmetatable({
    -- only the root API has these attributes, (API / "users") will not have them
    Modules = Modules,
    
    -- all endpoints will have a url
    url = Modules.URL.parse(Modules.Config.url),
}, mt)

-- error logger
task.defer(function()
    local httpRateLimitThresholdError = API.Modules.Error("HTTP request rate limit exceeded.")
    while task.wait() do
        if HTTP_REQUESTS_SENT_IN_LAST_60_SECONDS > 400 then
            httpRateLimitThresholdError(HTTP_REQUESTS_SENT_IN_LAST_60_SECONDS .. " HTTP requests have been made in the last 60 seconds.")
            task.wait(30) -- don't log it again for a while
        end
    end
end)

task.defer(function()
    print("[API.Modules.Time] Initial time synchronization complete:", API.Modules.Time())
end)

return API
