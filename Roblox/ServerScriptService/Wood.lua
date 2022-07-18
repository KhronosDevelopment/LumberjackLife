--- externals
local KDKit = require(game.ReplicatedFirst:WaitForChild("KDKit"))
local Remotes = require(game.ReplicatedStorage:WaitForChild("Remotes"))
local WoodConfigs = require(game.ServerStorage:WaitForChild("WoodConfigs"))
local Tree = require(script:WaitForChild("Tree"))
local Lumber = require(script:WaitForChild("Lumber"))
local Plank = require(script:WaitForChild("Plank"))
local Items = require(game.ServerScriptService:WaitForChild("Items"))
local TreeBiome = require(script:WaitForChild("TreeBiome"))

local simulationTime = workspace:GetAttribute("simulationTime")
local IS_STUDIO = game:GetService("RunService"):IsStudio()

-- class
local Wood = {
    folders = {
        trees = Tree.folder,
        lumber = Lumber.folder,
        planks = Plank.folder,
        biomes = TreeBiome.folder,
    },
    classes = {
        plank = Plank,
        lumber = Lumber,
        tree = Tree
    },
    configs = WoodConfigs,
}

-- implementation
function Wood:cycle()
    for biomeName, biome in pairs(TreeBiome.list) do
        biome:cycle()
    end
    
    local lumberPerPlayer = {}
    for lumber, _ in pairs(Lumber.list) do
        if lumber.config:shouldUnclaimLumber(lumber) then
            lumber:claim(nil)
        elseif lumber.config:shouldDeleteLumber(lumber) then
            lumber:delete()
        elseif lumber.claimed.by then
            local t = lumberPerPlayer[lumber.claimed.by] or {}
            lumberPerPlayer[lumber.claimed.by] = t
            table.insert(t, lumber)
        end
    end
    
    for player, ownedLumber in pairs(lumberPerPlayer) do
        local delete = #ownedLumber - 125
        if delete > 0 then
            -- delete the oldest pieces of wood
            -- TODO: may want to consider deleting the smallest/lowest value pieces instead
            table.sort(ownedLumber, function(a, b)
                return a.claimed.at < b.claimed.at
            end)
            
            for i = 1, delete do
                ownedLumber[i]:delete()
            end
        end
    end
end

function Wood:get(something)
    if typeof(something) == "table" then
        something = something.instance
    end
    if typeof(something) ~= "Instance" then
        warn("tried to Wood:get() with an invalid argument!", something)
        return nil, nil
    end

    for class, Class in pairs(self.classes) do
        local wood, locator = Class:kFindFromInstance(something)
        if wood then
            return wood, locator 
        end
    end

    return nil, nil
end

function Wood:Classify(something)
    for klass, Klass in pairs(self.classes) do
        if klass == something or Klass == something then
            return Klass
        end
    end

    return (self:get(something) or {}).class
end

function Wood:classify(something)
    return (self:Classify(something) or {}).name
end

function Wood:chop(wood, ...)
    return wood:chop(...) or {}
end

function Wood:create(config, class, cframe)
    local Class = self:Classify(class)
    if not Class then
        error("invalid class: " .. tostring(class))
    end

    return Class(config, cframe)
end

function Wood:setOwner(wood, ...)
    if wood.class.name == "Tree" then
        error("trees do not have owners")
    else
        return wood:setOwner(...)
    end
end

function Wood:getOwner(wood)
    if wood.class.name == "Tree" then
        return nil
    else
        return wood:getOwner()
    end
end

-- spawn trees
local s = os.clock()
for biomeName, biome in pairs(TreeBiome.list) do
    biome:simulateSecondsOfSpawning(simulationTime)
end
print("INITIAL BIOME SIMULATION TIME:", os.clock() - s)

return Wood
