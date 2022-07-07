local rs = game:GetService("RunService")

local function randomString(len)
    local hat = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local s = table.create(len, "")
    for i = 1, len do
        local n = math.random(1, hat:len())
        s[i] = hat:sub(n, n)
    end
    return table.concat(s)
end

if rs:IsStudio() then
    -- game.JobId is an empty string
    -- so just generate a new one
    return "RobloxStudio_" .. randomString(32)
else
    -- roblox jobids are occasionally reused
    -- I submitted a bug report about this with 
    -- with suffficient proof and logging info,
    -- and am awaiting a fix.
    -- for now, just make it unique by adding some extra stuff
    return game.JobId .. "_" .. randomString(8)
end
