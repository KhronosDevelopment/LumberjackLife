-- externals
local KDKit = require(game.ReplicatedFirst:WaitForChild("KDKit"))
local WoodConfigs = require(game.ServerStorage:WaitForChild("WoodConfigs"))
local WoodUtils = require(game.ServerScriptService:WaitForChild("Wood"):WaitForChild("Utils"))
local Items = require(game.ServerScriptService:WaitForChild("Items"))
local PhysicsService = game:GetService("PhysicsService")

-- class
local Plank = KDKit.Class("Plank")
Plank.folder = Items.folder
Plank.instanceToPlankMap = {}

-- klass functions
function Plank:kFindFromInstance(instance)
    local plank = self.instanceToPlankMap[instance]
    if not plank then
        return nil, nil
    end

    local locator = plank:getLocator(instance)
    if not locator then
        return nil, nil
    end

    return plank, locator
end

-- implementation
function Plank:__init(item)
    self.item = item
    self.config = WoodConfigs[self.item.attributes[1]]
    
    self.root = {
        instance = self.item.instance.PrimaryPart,
        cuts = {},
        
        -- all of these are unused for Planks
        -- I just want to keep everything in the same format
        decorations = {},
        size = self.item.instance.PrimaryPart.Size,
        cframe = self.item.instance.PrimaryPart.CFrame,
        branches = {},
        sliced = {top = true, bottom = true}
    }
    
    Plank.instanceToPlankMap[self.root.instance] = self
    PhysicsService:SetPartCollisionGroup(self.root.instance, "Millable")
end

function Plank:getLocator(instance)
    return WoodUtils:getBranchLocator(instance, self.root)
end

function Plank:locate(locator)
    return WoodUtils:locateBranch(self.root, locator)
end

function Plank:mustLocate(locator)
    return WoodUtils:mustLocateBranch(self.root, locator)
end

function Plank:getVolume()
    return self.root.instance.Size.X * self.root.instance.Size.Y * self.root.instance.Size.Z
end

function Plank:evaluate()
    return self.config:getPlankValue() * self:getVolume()
end

function Plank:chop(locator, at, flipped, power)
    self:mustLocate(locator)
    
    local createdWood
    local mode, cut = WoodUtils:chopBranch(self.root, at, flipped, power)
    if mode == "decouple" then
        createdWood = self:decouple(cut.at < 0)
    elseif mode == "slice" then
        createdWood = { self:slice(cut.at) }
    elseif mode == "cut" then
        self.item.assembly:anchor()

        if not cut.instance then
            cut.instance = self.config:getStyledCut()
            cut.instance.Parent = workspace
            cut.weld = WoodUtils:weld(cut.instance, self.root.instance)
            cut.instance.Anchored = false
        end

        cut.weld.Enabled = false
        WoodUtils:redrawCut(cut, self.root.instance)
        cut.weld.Enabled = true

        self.item.assembly:unanchor()
    end

    return createdWood
end

function Plank:slice(at)
    self.item.assembly:anchor()
    self:unweld()

    local newBranch = WoodUtils:sliceBranch(self.root, at)
    local newItem = Items:create(
        'plank',
        self.item.owner,
        newBranch.instance.CFrame,
        {
            self.config.name,
            math.floor(newBranch.instance.Size.X * 100),
            math.floor(newBranch.instance.Size.Y * 100),
            math.floor(newBranch.instance.Size.Z * 100),
        }
    )
    local newPlank = newItem._plank
    
    newPlank.root.cuts = newBranch.cuts
    newPlank:weld()
    
    self:weld()
    self.item.assembly:unanchor()
end

function Plank:decouple(isBottom)
    -- nothing to decouple on planks
    return nil
end

function Plank:weld()
    for _, cut in ipairs(self.root.cuts) do
        cut.weld = WoodUtils:weld(cut.instance, self.root.instance, cut.weld)
    end
end

function Plank:unweld()
    for _, cut in ipairs(self.root.cuts) do
        if cut.weld then
            cut.weld:Destroy()
            cut.weld = nil
        end
    end
end

function Plank:dropoff(locator)
    local value = self:evaluate()
    self:delete()
    return value
end

function Plank:setOwner(plr)
    return self.item:setOwner(plr)
end

function Plank:getOwner()
    return self.item.owner
end

function Plank:delete(doNotForward)
    Plank.instanceToPlankMap[self.root.instance] = nil
    if not doNotForward then
        Items:delete(self.item)
    end
end

return Plank
