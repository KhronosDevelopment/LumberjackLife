-- externals
local Modules = require(script.Parent)

-- class
local OTPAuth = {}

-- utils
OTPAuth.sha256 = require(script.sha256)

function OTPAuth:getPrefixAtTime(t)
    local c = Modules.Config
    return math.floor(t / c.otp.period + 0.5)
end

local tokenMemoize = setmetatable({}, {__mode = "kv"})
function OTPAuth:getTokenAtTime(t)
    local prefix = tostring(self:getPrefixAtTime(t))
    
    tokenMemoize[prefix] = tokenMemoize[prefix] or OTPAuth.sha256(prefix .. tostring(Modules.Config.otp.key))
    return tokenMemoize[prefix]
end

function OTPAuth:tokenIsValid(check)
    local now = Modules.Time:now()
    return
        check == self:getTokenAtTime(now) or
        check == self:getTokenAtTime(now + Modules.Config.otp.period) or
        check == self:getTokenAtTime(now - Modules.Config.otp.period)
end

function OTPAuth:getCurrentToken()
    return self:getTokenAtTime(Modules.Time:now())
end

return OTPAuth
