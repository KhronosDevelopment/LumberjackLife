-- externals
local KDKit = require(game.ReplicatedFirst:WaitForChild("KDKit"))
local WoodUtils = require(game.ServerScriptService:WaitForChild("Wood"):WaitForChild("Utils"))
local Assembly = require(game.ServerScriptService:WaitForChild("Assembly"))
local CONSTANTS = WoodUtils.constants
local PhysicsService = game:GetService("PhysicsService")

-- class
local Lumber = KDKit.Class("Lumber")
Lumber.folder = workspace:WaitForChild("LUMBER")
Lumber.branchInstanceToLumberMap = {}
Lumber.list = {}

-- klass functions
function Lumber:kFindFromInstance(instance)
    local lumber = self.branchInstanceToLumberMap[instance]
    if not lumber then
        return nil, nil
    end

    local locator = lumber:getLocator(instance)
    if not locator then
        return nil, nil
    end

    return lumber, locator
end

-- implementation
function Lumber:__init(config, root)
    Lumber.list[self] = true
    self.config = config
    self.root = root
    --[[
    fuck typed luau all my homies hate typed luau
    (i'm way too lazy to get real typing working w/ KDKit.Class)
    
    root = {
        instance = Instance,
        cframe = CFrame [relative to parent, if the parent exists - otherwise holds no meaning],
        size = Vector3,
        decorations = {
            { instance = Instance, weld = Instance },
            ...
        },
        cuts = { [ sorted by cut.at, ascending ]
            { at = float, area = float, flipped = boolean, instance = Instance, weld = Instance },
            ...
        },
        sliced = { top = boolean, bottom = boolean },
        branches = {
            {
                weld = Instance,
                parent = {...root},
                ...root
            },
            ...
        }
    }
    --]]
    self.assembly = Assembly(self.root.instance, self)
    self.claimed = {
        at = os.clock(),
        by = nil
    }
    self:branchAdded(self.root)
end

function Lumber:getLocator(instance)
    return WoodUtils:getBranchLocator(instance, self.root)
end

function Lumber:locate(locator)
    return WoodUtils:locateBranch(self.root, locator)
end

function Lumber:mustLocate(locator)
    return WoodUtils:mustLocateBranch(self.root, locator)
end

function Lumber:getVolume()
    return WoodUtils:getVolume(self.root)
end

function Lumber:evaluate()
    return self.config:getLumberValue() * self:getVolume()
end

function Lumber:branchAdded(branch)
    PhysicsService:SetPartCollisionGroup(branch.instance, "Millable")
    
    Lumber.branchInstanceToLumberMap[branch.instance] = self
    for _, child in ipairs(branch.branches) do
        self:branchAdded(child)
    end
end

function Lumber:branchRemoved(branch, destroy)
    PhysicsService:SetPartCollisionGroup(branch.instance, "Default")
    Lumber.branchInstanceToLumberMap[branch.instance] = nil
    if destroy then
        branch.instance:Destroy()
        branch.instance = nil
        
        if branch.weld then
            branch.weld:Destroy()
            branch.weld = nil
        end
        
        for _, cut in ipairs(branch.cuts) do
            cut.instance:Destroy()
            cut.weld:Destroy()
        end
        table.clear(branch.cuts)
        
        for _, decoration in pairs(branch.decorations) do
            decoration.instance:Destroy()
            decoration.weld:Destroy()
        end
        table.clear(branch.decorations)
    end
    
    for _, child in ipairs(branch.branches) do
        self:branchRemoved(child, destroy)
    end
end

function Lumber:chop(locator, at, flipped, power)
    local branch = self:mustLocate(locator)

    local createdWood
    local mode, cut = WoodUtils:chopBranch(branch, at, flipped, power)
    if mode == "decouple" then
        createdWood = self:decouple(branch, cut.at < 0)
    elseif mode == "slice" then
        createdWood = { self:slice(branch, cut.at) }
    elseif mode == "cut" then
        self.assembly:anchor()

        if not cut.instance then
            cut.instance = self.config:getStyledCut()
            cut.instance.Parent = workspace
            cut.weld = WoodUtils:weld(cut.instance, branch.instance)
            cut.instance.Anchored = false
        end

        cut.weld.Enabled = false
        WoodUtils:redrawCut(cut, branch.instance)
        cut.weld.Enabled = true

        self.assembly:unanchor()
    end

    return createdWood
end

function Lumber:unweld(branch)
    if branch.weld then
        branch.weld:Destroy()
        branch.weld = nil
    end

    for _, child in ipairs(branch.branches) do
        if child.weld then
            child.weld:Destroy()
            child.weld = nil
        end
    end

    for _, decoration in pairs(branch.decorations) do
        if decoration.weld then
            decoration.weld:Destroy()
            decoration.weld = nil
        end
    end

    for _, cut in ipairs(branch.cuts) do
        if cut.weld then
            cut.weld:Destroy()
            cut.weld = nil
        end
    end
end

function Lumber:weld(branch)
    if branch.parent then
        branch.weld = WoodUtils:weld(branch.instance, branch.parent.instance, branch.weld)
    end

    for _, child in ipairs(branch.branches) do
        child.weld = WoodUtils:weld(child.instance, branch.instance, child.weld)
    end

    for _, decoration in pairs(branch.decorations) do
        local weldable
        if decoration.instance:IsA("BasePart") then
            weldable = decoration.instance
        else
            weldable = decoration.instance.PrimaryPart
        end
        
        decoration.weld = WoodUtils:weld(weldable, branch.instance, decoration.weld)
    end

    for _, cut in ipairs(branch.cuts) do
        cut.weld = WoodUtils:weld(cut.instance, branch.instance, cut.weld)
    end
end

function Lumber:decorate(branch)
    self.config:decorateBranch(branch, true)
    
    for name, decoration in pairs(branch.decorations) do
        if decoration.instance:IsA("BasePart") then
            decoration.instance.Anchored = false
        end
        
        for i, v in ipairs(decoration.instance:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Anchored = false
            end
        end
    end
end

function Lumber:getOwner()
    return self.owner
end

function Lumber:slice(branch, at)
    self.assembly:anchor()
    self:unweld(branch)
    
    local newBranch = WoodUtils:sliceBranch(branch, at)
    newBranch.instance.Parent = Lumber.folder
    
    self:decorate(newBranch)
    self:weld(newBranch)
    
    self:decorate(branch)
    self:weld(branch)

    newBranch.instance.Anchored = false
    self.assembly:unanchor()
    
    return self:transformBranchIntoLumber(newBranch)
end

function Lumber:decouple(branch, isBottom)
    if isBottom then
        if branch == self.root then
            -- no action required, since the root is already decoupled
            return nil
        end
        
        self.assembly:anchor()
        
        -- remove this branch from the parent
        local siblings = branch.parent.branches
        table.remove(siblings, table.find(siblings, branch))

        if #siblings == 0 then
            branch.parent.sliced.top = true
            self:unweld(branch.parent)
            self:decorate(branch.parent)
            self:weld(branch.parent)
        end
        
        branch.weld:Destroy()
        branch.weld = nil
        branch.sliced.bottom = true
        branch.parent = nil
        self:unweld(branch)
        self:decorate(branch)
        self:weld(branch)

        self.assembly:unanchor()
        return { self:transformBranchIntoLumber(branch) }
    else
        self.assembly:anchor()
        
        -- move all children branches into new lumber
        local createdWood = table.create(#branch.branches)
        for _, child in ipairs(branch.branches) do
            -- remove from parent
            child.weld:Destroy()
            child.weld = nil
            child.parent = nil
            child.sliced.bottom = true
            self:unweld(child)
            self:decorate(child)
            self:weld(child)
            
            -- create new lumber
            table.insert(createdWood, self:transformBranchIntoLumber(child))
        end
        branch.branches = {}
        if #createdWood > 0 then
            branch.sliced.top = true
            self:unweld(branch)
            self:decorate(branch)
            self:weld(branch)
        end

        self.assembly:unanchor()
        return createdWood
    end
end

function Lumber:sellBranch(locator)
    local branch = self:mustLocate(locator)
    
    -- remove all children
    self:decouple(branch, false)
    
    -- create new lumber with only this branch
    local newLumber = self:decouple(branch, true) or { self }
    newLumber = newLumber[1]
    
    local value = newLumber:evaluate()
    newLumber:delete()
    return value
end

function Lumber:transformBranchIntoLumber(branch)
    self:branchRemoved(branch)
    
    local lumber = Lumber(self.config, branch)
    lumber:setOwner(self.owner)
    return lumber
end

function Lumber:setOwner(plr)
    self.owner = plr
    self:claim(plr)
end

function Lumber:claim(by)
    self.assembly:setNetworkOwner(if by == nil then "auto" else by.instance)
    self.claimed.at = os.clock()
    self.claimed.by = by
end

function Lumber:delete()
    Lumber.list[self] = nil
    self:branchRemoved(self.root, true)
    self.assembly:delete()
end

return Lumber
