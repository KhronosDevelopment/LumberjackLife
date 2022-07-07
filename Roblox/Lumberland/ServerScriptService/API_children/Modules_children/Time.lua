-- externals
local KDKit = require(game.ReplicatedStorage.KDKit)
local HttpService = game:GetService("HttpService")
local API = require(script.Parent.Parent)
local Modules = require(script.Parent)

-- class
local Time = {
    endpoint = API / Modules.Config.time.endpoint,
}

function Time:sync()
    local finishRemoteSync = KDKit.Time:startRemoteSync()
    
    -- no OTP token since obviously the [T]ime aspect won't be ready
    local response = self.endpoint:eGET(nil, nil, false)
    
    finishRemoteSync(response.time)
end

function Time:safeSync()
    while true do
        local s, r = pcall(self.sync, self)
        if not s then
            warn("[API.Modules.Time] - Time synchronization failed. Will try again. Error:", r)
            task.wait(1)
        else
            break
        end
    end
end

function Time:now()
    return KDKit.Time:now()
end

task.defer(function()
    while true do
        Time:safeSync()
        task.wait(Modules.Config.time.updateRate)
    end
end)

return setmetatable(Time, {__call = Time.now})
