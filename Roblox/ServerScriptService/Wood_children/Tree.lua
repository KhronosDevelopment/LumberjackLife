-- externals
local KDKit = require(game.ReplicatedFirst:WaitForChild("KDKit"))
local Lumber = require(game.ServerScriptService:WaitForChild("Wood"):WaitForChild("Lumber"))
local WoodUtils = require(game.ServerScriptService:WaitForChild("Wood"):WaitForChild("Utils"))
local CONSTANTS = WoodUtils.constants

-- class
local Tree = KDKit.Class("Tree")
Tree.folder = workspace:WaitForChild("TREES")
Tree.list = {}
Tree.branchInstanceToTreeMap = {}
Tree.stages = {
    growing = 1,
    adult = 2,
    elderly = 3,
    dead = 4,
}

-- klass functions
function Tree:kFindFromInstance(instance)
    local tree = self.branchInstanceToTreeMap[instance]
    if not tree then
        return nil, nil
    end
    
    local locator = tree:getLocator(instance)
    if not locator then
        return nil, nil
    end
    
    return tree, locator
end

-- utils
local function findMaxDepth(branch)
    local m = 1
    for _, child in ipairs(branch.branches) do
        m = math.max(m, 1 + findMaxDepth(child))
    end

    return m
end

-- implementation
function Tree:__init(config, root, age)
    table.insert(Tree.list, self)

    self.config = config
    self.hitboxRadius = self.config:getHitboxRadius()

    local now = os.clock() - (age or 0)
    self.spawnedAt = now
    self.dieAt = now + config:getLifespan()
    self.adultAt = now + config:getGrowthTime()
    self.elderlyAt = self.dieAt - config:getElderlyTime()
    self.stage = Tree.stages.growing

    self.depth = findMaxDepth(root)

    self.root = root
    --[[
    root = {
        instance = ?Instance,
        cframe = CFrame [relative to parent, if the parent exists - otherwise cframe of base],
        size = Vector3,
        decorations = {
            [name] = { instance = BasePart | { PrimaryPart = BasePart }, attributes = {any} },
            ...
        },
        cuts = { [ sorted by cut.at, ascending ]
            { at = float, area = float, flipped = boolean, instance = Instance },
            ...
        },
        sliced = { top = boolean, bottom = boolean },
        branches = {
            {
                parent = {...root},
                ...root
            },
            ...
        }
    }
    --]]
end

function Tree:cycle()
    local now = os.clock()

    self:grow(self:getGrowthFactor())
    if now >= self.dieAt then
        self:died()
        return true
    elseif now >= self.elderlyAt then
        self:becomeElderly()
    end

    return false
end

function Tree:getLocator(instance)
    return WoodUtils:getBranchLocator(instance, self.root)
end

function Tree:locate(locator)
    return WoodUtils:locateBranch(self.root, locator)
end

function Tree:mustLocate(locator)
    return WoodUtils:mustLocateBranch(self.root, locator)
end

function Tree:grow(f)
    if self.stage > Tree.stages.growing then
        return false
    end

    local growthStep = math.round(f * CONSTANTS.N_TREE_GROWTH_STEPS)
    if self.lastDrawnAtGrowthStep and growthStep <= self.lastDrawnAtGrowthStep then
        return false
    end

    self.lastDrawnAtGrowthStep = growthStep
    self:redraw(growthStep / CONSTANTS.N_TREE_GROWTH_STEPS)

    if growthStep >= CONSTANTS.N_TREE_GROWTH_STEPS then
        self.stage = Tree.stages.adult
    end
    
    self:redecorate()

    return true
end

function Tree:redecorate()
    for _, branch in ipairs(self:flattenGrownBranches()) do
        self.config:decorateBranch(branch, self.stage >= Tree.stages.elderly)
    end
end

function Tree:getGrowthFactor()
    return math.clamp((os.clock() - self.spawnedAt) / (self.adultAt - self.spawnedAt), 0, 1)
end

function Tree:growthFactorToScale(growthFactor, branch)
    -- "siblingCount" includes the branch itself
    local branchIndex, siblingCount = 1, 1
    if branch ~= self.root then
        siblingCount = #branch.parent.branches
        branchIndex = table.find(branch.parent.branches, branch)
    end

    local depth = 1
    while branch ~= self.root do
        depth += 1
        branch = branch.parent
    end

    local siblingFactor = (branchIndex - 0.5) / siblingCount
    local center = (depth + siblingFactor - 1) / self.depth
    local startGrowingAt = math.clamp(center - 0.3, 0, 1 - 0.4)
    local stopGrowingAt = startGrowingAt + 0.4

    growthFactor = (math.clamp(growthFactor, startGrowingAt, stopGrowingAt) - startGrowingAt) / 0.4
    return growthFactor > 0, (growthFactor * 0.7 + 0.3)
end

function Tree:redraw(growthFactor, branch)
    branch = branch or self.root

    local shouldDraw, growthScale = self:growthFactorToScale(growthFactor, branch)
    if not shouldDraw then
        return
    end

    local size = branch.size * growthScale
    local cframe = branch.cframe
    if branch.parent then
        local parentInstance = branch.parent.instance or {
            Size = branch.parent.size,
            CFrame = branch.parent.cframe
        }

        cframe = parentInstance.CFrame * CFrame.new(
            (parentInstance.Size.X / 2) * cframe.p.X,
            (parentInstance.Size.Y / 2) * cframe.p.Y,
            (parentInstance.Size.Z / 2) * cframe.p.Z
        ) * (cframe - cframe.p)
    end
    cframe *= CFrame.new(0, size.Y / 2, 0)

    local firstDraw = not branch.instance
    if firstDraw then
        branch.instance = self.config:getStyledBranch()
        branch.instance.Parent = Tree.folder
        self:addedBranchInstance(branch.instance)
    end

    branch.instance.CFrame = cframe
    branch.instance.Size = size
    WoodUtils:redrawCuts(branch.cuts, branch.instance)

    for _, child in ipairs(branch.branches) do
        self:redraw(growthFactor, child)
    end
end

function Tree:flattenGrownBranches(branch, t)
    branch = branch or self.root
    t = t or { branch }
    
    if not branch.instance then
        return {}
    end
    
    for _, child in ipairs(branch.branches) do
        if child.instance then
            table.insert(t, child)
        end
    end
    for _, child in ipairs(branch.branches) do
        self:flattenGrownBranches(child, t)
    end

    return t
end

function Tree:died()
    if self.stage >= Tree.stages.dead then
        return false
    elseif self.stage < Tree.stages.elderly then
        self:becomeElderly()
    end
    self.stage = Tree.stages.dead

    self.config:onTreeDied(self)
    self:delete()

    return true
end

function Tree:delete()
    table.remove(Tree.list, table.find(Tree.list, self))
    for _, branch in ipairs(self:flattenGrownBranches()) do
        Tree.branchInstanceToTreeMap[branch.instance] = nil
        branch.instance:Destroy()
        
        self.config:undecorateBranch(branch)

        for _, cut in ipairs(branch.cuts) do
            cut.instance:Destroy()
        end
    end
end

function Tree:addedBranchInstance(instance)
    Tree.branchInstanceToTreeMap[instance] = self
end

function Tree:becomeElderly()
    if self.stage >= Tree.stages.elderly then
        return false
    end
    self.stage = Tree.stages.elderly

    self.config:makeTreeElderly(self)
    return true
end

function Tree:chop(locator, at, flipped, power)
    local branch = self:mustLocate(locator)
    if not branch.instance then
        error("cannot chop that branch because it hasn't grown yet")
    end
    
    local createdWood
    local mode, cut = WoodUtils:chopBranch(branch, at, flipped, power)
    if mode == "decouple" then
        createdWood = self:decouple(branch, cut.at < 0)
    elseif mode == "slice" then
        createdWood = { self:slice(branch, cut.at) }
    elseif mode == "cut" then
        if not cut.instance then
            cut.instance = self.config:getStyledCut()
            cut.instance.Parent = workspace
        end

        WoodUtils:redrawCut(cut, branch.instance)
    end

    return createdWood
end

function Tree:slice(branch, at)
    self:becomeElderly()
    
    local newBranch = WoodUtils:sliceBranch(branch, at)
    self.config:decorateBranch(newBranch, true)
    self.config:decorateBranch(branch, true)
    
    return self:transformBranchIntoLumber(newBranch)
end

function Tree:decouple(branch, isBottom)
    self:becomeElderly()

    if isBottom then
        if branch == self.root then
            -- no action required, since the root is already decoupled
            return nil
        end

        local siblings = branch.parent.branches
        table.remove(siblings, table.find(siblings, branch))
        
        if #siblings == 0 then
            branch.parent.sliced.top = true
            self.config:decorateBranch(branch.parent, true)
        end
        
        branch.sliced.bottom = true
        branch.parent = nil
        self.config:decorateBranch(branch, true)


        return { self:transformBranchIntoLumber(branch) }
    else
        -- move all children branches into new lumber
        local createdWood = table.create(#branch.branches)
        for _, child in ipairs(branch.branches) do
            child.parent = nil
            child.sliced.bottom = true
            if child.instance then
                self.config:decorateBranch(child, true)
                table.insert(
                    createdWood,
                    self:transformBranchIntoLumber(child)
                )
            end
        end
        branch.branches = {}
        branch.sliced.top = true
        self.config:decorateBranch(branch, true)

        return createdWood
    end
end

function Tree:transformBranchIntoLumber(branch)
    for _, b in ipairs(self:flattenGrownBranches(branch)) do
        Tree.branchInstanceToTreeMap[b.instance] = nil
    end

    return Lumber(self.config, self:prepareBranchForLumber(branch))
end

function Tree:prepareBranchForLumber(branch)
    if not branch.instance then
        return nil
    end
    branch.instance.Parent = Lumber.folder

    -- weld & unanchor cuts
    for _, cut in ipairs(branch.cuts) do
        cut.weld = WoodUtils:weld(cut.instance, branch.instance, cut.weld)
        cut.instance.Anchored = false
    end

    -- weld & unanchor decorations
    for _, decoration in pairs(branch.decorations) do
        local weldable
        if decoration.instance:IsA("BasePart") then
            decoration.instance.Anchored = false
            weldable = decoration.instance
        else
            weldable = decoration.instance.PrimaryPart
        end

        for _, descendant in ipairs(decoration.instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = false
            end
        end
        
        decoration.weld = WoodUtils:weld(weldable, branch.instance, decoration.weld)
    end

    -- prepare children
    local preparedBranches = table.create(#branch.branches)
    for _, child in ipairs(branch.branches) do
        child = self:prepareBranchForLumber(child)
        if child then
            table.insert(preparedBranches, child)
        end
    end
    branch.branches = preparedBranches

    -- weld & unanchor branch
    if branch.parent then
        branch.weld = WoodUtils:weld(branch.instance, branch.parent.instance, branch.weld)
    end
    branch.instance.Anchored = false

    return branch
end

return Tree
