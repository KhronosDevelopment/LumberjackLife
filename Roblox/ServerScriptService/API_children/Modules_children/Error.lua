-- externals
local KDKit = require(game.ReplicatedStorage.KDKit)
local API = require(script.Parent.Parent)
local Modules = require(script.Parent)
local RunService = game:GetService("RunService")

-- class
local Error = KDKit.Class("Error")

-- utils
Error.endpoint = API / Modules.Config.error.endpoint
local nextErrorCode = 1000
local codeDescriptions = {}

local function toCharArray(s)
    local t = table.create(s:len(), '_')
    for i = 1, s:len() do
        t[i] = s:sub(i, i)
    end
    
    return t
end

local uuid_random = Random.new()
local uuid_hat = toCharArray("ABCDEFGHJKPQRSTUVWXYZ123456789") -- removed: i, l, m, n, 0, o
local uuid_hat_size = #uuid_hat -- 30
local function get_uuid()
    -- 16 random chars from uuid_hat
    
    -- I know about `for i = 1, 16 do`, this is more efficient for multiple reasons
    return table.concat({
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],

        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],

        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],

        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
        uuid_hat[uuid_random:NextInteger(1, uuid_hat_size)],
    })
end

function Error:wrap(logger, func)
    return function(...)
        local stuff = table.pack(pcall(func, ...))
        local s = stuff[1]
        if not s then
            local err = stuff[2]
            logger(err)
            error(err)
        else
            table.remove(stuff, 1) -- success status
            return table.unpack(stuff)
        end
    end
end

function Error:__init(description)
    self.code = nextErrorCode
    self.description = description
    
    nextErrorCode += 1
end

function Error:raise(message, plr)
    local uuid = get_uuid()
    
    if RunService:IsStudio() then
        print("[Error] Skipping HTTP logging for the following error because of studio environment")
    else
        local data = {
            uuid = uuid,
            code = self.code,
            description = self.description,
            message = message,
        }
        
        if plr then
            Error.endpoint:cepPOST(plr, data)
        else
            Error.endpoint:cePOST(data)
        end
    end
    
    warn("[Error]", message) -- make it show up in the output window

    return (
        "An error has occurred. Please send this information in our Discord server: [%X-%s] %s"
    ):format(
        self.code,
        uuid,
        self.description
    )
end

Error.__call = Error.raise

return Error
